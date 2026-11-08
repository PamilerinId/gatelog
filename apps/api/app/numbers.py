"""Registering a resident's new number from the gate, with the home's consent.

A resident rings the gate from a number Gatelog does not know, and confirms on the callback
to their registered number. The guard can then offer to register the new one. It waits,
invisible, until an existing number of the home replies YES (48 hours at most): a guard,
or someone standing at the gate, cannot add a number to a home on their own say-so.
"""

from datetime import timedelta

from fastapi import HTTPException
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from . import audit, clock, db, messaging, phones
from .models import Conversation, Estate, Home, NumberOffer, PhoneNumber, Resident

OFFER_TTL = timedelta(hours=48)


def active(q):
    """Only numbers the home has confirmed: for routing, callbacks, the gate phone and alerts."""
    return q.where(PhoneNumber.pending_until.is_(None))


def _asked_number(s: Session, resident: Resident) -> PhoneNumber | None:
    """Ask the resident's own number first, otherwise anyone else's in the home."""
    own = s.scalars(active(select(PhoneNumber).where(PhoneNumber.resident_id == resident.id)).order_by(PhoneNumber.is_primary.desc())).first()
    if own:
        return own
    others = select(Resident.id).where(Resident.home_id == resident.home_id, Resident.active.is_(True))
    return s.scalars(active(select(PhoneNumber).where(PhoneNumber.resident_id.in_(others))).order_by(PhoneNumber.is_primary.desc())).first()


def offer(s: Session, estate: Estate, *, offer_id, resident: Resident, raw: str, guard_id, shift_id, device_id, at) -> str | None:
    """Start an offer. Returns why not, or None when the home has been asked."""
    from .routers.admin import add_number  # one place for the 3-per-home limit and duplicate check

    asked = _asked_number(s, resident)
    if asked is None:
        return "nobody at this home has a registered number to confirm it"
    try:
        number = add_number(s, estate.id, f"guard:{guard_id}", resident, raw, pending_until=clock.now() + OFFER_TTL)
    except HTTPException as e:
        return str(e.detail)
    s.add(NumberOffer(id=offer_id, estate_id=estate.id, home_id=resident.home_id, resident_id=resident.id, number_id=number.id,
                      asked_number_id=asked.id, last4=number.last4, guard_id=guard_id, shift_id=shift_id, device_id=device_id, at=at))
    asked_resident = s.get(Resident, asked.resident_id)
    c = s.scalars(select(Conversation).where(Conversation.resident_id == asked_resident.id)).first()
    if c is None:
        c = Conversation(estate_id=estate.id, resident_id=asked_resident.id)
        s.add(c)
    c.awaiting, c.visit_id, c.pending = "number_offer", None, {"offer_id": str(offer_id)}
    home = s.get(Home, resident.home_id)
    messaging.queue(
        s, estate.id, asked, "sms", "number_offer",
        f"The gate was asked to add a new number ending {number.last4} for {resident.name} at {home.label}. "
        "Reply YES to add it, or NO if you do not know this number.",
    )
    return None


def answer(s: Session, estate: Estate, resident: Resident, c: Conversation, yes: bool) -> str:
    o = s.get(NumberOffer, (c.pending or {}).get("offer_id"))
    c.awaiting, c.pending = None, None
    number = s.get(PhoneNumber, o.number_id) if o and o.number_id else None
    if o is None or o.state != "asked" or number is None or number.pending_until is None or number.pending_until < clock.now():
        return "That request has expired. The resident can ask the gate again."
    o.decided_at = clock.now()
    if not yes:
        o.state, o.number_id = "declined", None
        s.delete(number)
        return f"Not added. The number ending {o.last4} was not registered."
    o.state = "added"
    number.pending_until, number.verified_at = None, clock.now()
    if not s.scalar(select(PhoneNumber.id).where(PhoneNumber.resident_id == number.resident_id, PhoneNumber.is_primary.is_(True), PhoneNumber.id != number.id).limit(1)):
        number.is_primary = True
    audit.record(s, estate.id, f"resident:{resident.id}", "confirm_number", number)
    owner = s.get(Resident, number.resident_id)
    home = s.get(Home, number.home_id)
    messaging.queue(s, estate.id, number, "sms", "number_added",
                    f"This number is now registered to {owner.name} at {home.address} on Gatelog. You can tell the gate about guests from it.")
    return f"Added. The number ending {o.last4} is now registered for {owner.name}."


def housekeeping() -> dict[str, int]:
    """Offers nobody answered in 48 hours expire, and their pending numbers are deleted."""
    now = clock.now()
    with db.session(ops=True) as s:
        stale = s.scalars(select(NumberOffer).where(NumberOffer.state == "asked", NumberOffer.at < now - OFFER_TTL)).all()
        for o in stale:
            o.state, o.decided_at, o.number_id = "expired", now, None
        removed = s.execute(delete(PhoneNumber).where(PhoneNumber.pending_until.is_not(None), PhoneNumber.pending_until < now)).rowcount
    return {"number_offers_expired": len(stale), "pending_numbers_removed": removed}
