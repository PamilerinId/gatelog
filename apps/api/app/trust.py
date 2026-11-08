"""How well each entry was verified, and the second pair of eyes on the weak ones.

    verified       a code, or a callback to a registered number that the resident confirmed
    pin_verified   a caller from any number gave the home PIN (checked offline on the phone)
    unverified     admitted on a description: the CSO's decision, or an inbound call alone

Every unverified entry texts every registered number of the home at once ("Not you? Reply
NO"). A NO is logged against the entry and goes straight to the security head. Every wrong
home PIN tells the home too. Gatelog decides nothing; it makes sure someone else sees.

These alerts go by SMS whatever the resident's preference (an SMS reaches a phone with no
data) and are never billed against the estate's allowance.
"""

from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import abuse, clock, messaging, visits
from .models import Entry, Estate, Gate, Home, PhoneNumber, PinCheck, Resident, StaffUser, Visit

BY_METHOD = {
    "code": "verified",
    "callback_confirmed": "verified",
    "pin_confirmed": "pin_verified",
    "phone_announced": "unverified",
    "walk_in_admitted": "unverified",
}
DISPUTE_WINDOW = timedelta(hours=24)
WRONG_PIN_ALERTS = abuse.Limit("wrong-pin-alert", 5, timedelta(hours=1))  # per home: a burst of tries is one story


def entry_trust(method: str, visit: Visit | None) -> str | None:
    """None for a refusal. An entry on a visit someone announced with the home PIN stays
    PIN-verified however the guard then let them in."""
    if method == "refused":
        return None
    if visit is not None and method in ("callback_confirmed", "pin_confirmed") and visit.trust != "verified":
        return visit.trust
    return BY_METHOD[method]


def _home_numbers(s: Session, home_id) -> list[PhoneNumber]:
    active = select(Resident.id).where(Resident.home_id == home_id, Resident.active.is_(True))
    return s.scalars(select(PhoneNumber).where(PhoneNumber.home_id == home_id, PhoneNumber.resident_id.in_(active))).all()


def _to_home(s: Session, estate: Estate, home_id, kind: str, body: str) -> int:
    numbers = _home_numbers(s, home_id)
    for n in numbers:
        messaging.queue(s, estate.id, n, "sms", kind, body)
    return len(numbers)


def alert_unverified(s: Session, estate: Estate, e: Entry) -> int:
    home = s.get(Home, e.home_id)
    gate = s.get(Gate, e.gate_id)
    when = visits.clock_24h(e.at.astimezone(visits.tz(estate)))
    after = f"a call from {e.caller_masked}" if e.caller_masked else "the CSO's decision"
    body = f"A guest ({e.guest_name}) for {home.label} was admitted at {gate.name if gate else 'the gate'}, {when}, after {after}. Not you? Reply NO."
    return _to_home(s, estate, e.home_id, "unverified_entry", body)


def alert_wrong_pin(s: Session, estate: Estate, check: PinCheck) -> bool:
    if not abuse.hit(s, WRONG_PIN_ALERTS, str(check.home_id)):
        return False
    home = s.get(Home, check.home_id)
    when = visits.clock_24h(check.at.astimezone(visits.tz(estate)))
    where = "to the shuttle rider" if check.context == "shuttle" else "at the gate"
    call = f", on a call from {check.caller_masked}" if check.caller_masked else ""
    body = f"Someone gave a wrong home PIN for {home.label} {where}, {when}{call}. If it was not someone from your home, tell the estate office."
    _to_home(s, estate, check.home_id, "wrong_pin", body)
    return True


def dispute(s: Session, estate: Estate, resident: Resident) -> Entry | None:
    """The resident replied NO: the latest unverified entry for their home in the last 24 hours,
    not already disputed, is marked, and the security head is told at once."""
    e = s.scalars(
        select(Entry).where(
            Entry.home_id == resident.home_id, Entry.trust == "unverified", Entry.disputed_at.is_(None),
            Entry.at > clock.now() - DISPUTE_WINDOW,
        ).order_by(Entry.at.desc())
    ).first()
    if e is None:
        return None
    e.disputed_at, e.disputed_by = clock.now(), resident.id
    home = s.get(Home, e.home_id)
    gate = s.get(Gate, e.gate_id)
    when = visits.clock_24h(e.at.astimezone(visits.tz(estate)))
    body = (f"{home.address} says the guest admitted at {gate.name if gate else 'the gate'}, {when} ({e.guest_name}) "
            "was NOT expected. Please check now.")
    heads = s.scalars(select(StaffUser.id).where(StaffUser.estate_id == estate.id, StaffUser.role == "security_head", StaffUser.active.is_(True))).all()
    for n in s.scalars(select(PhoneNumber).where(PhoneNumber.staff_id.in_(heads))):
        messaging.queue(s, estate.id, n, "sms", "entry_disputed", body)
    return e
