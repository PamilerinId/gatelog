"""The estate shuttle: rides inside the estate, free to residents (the levy pays for them).

A ride is booked four ways (WhatsApp or SMS, the guard at the gate, flagged down, the CSO)
and lands in one queue. Riders take rides from it on their phones. Who rode is recorded at
pickup (or at drop-off for a parcel) by the resident's estate card, the home's house code,
or as vouched by the guard or the rider.

Ride changes arrive from phones as events, possibly late and out of order. One rule settles
conflicts: what physically happened wins over a claim. Two riders can both tap "take it"
and only the first gets the ride; but a pickup or drop-off is applied whoever made it,
because the passenger really was carried.
"""

import base64
import hashlib
import os
import re
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta
from uuid import UUID

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from . import clock, db, messaging, phones, stay
from .estate_settings import EstateSettings
from .models import (
    RIDE_OPEN_STATES,
    Estate,
    Gate,
    Guard,
    Home,
    Place,
    Position,
    Resident,
    ResidentCard,
    Ride,
    RideEvent,
    Shift,
    Shuttle,
)

CARD_PREFIX = "gatelog-card-v1"
HOUSE_CODE_ITERATIONS = 60_000  # the same slow hash as guard PINs, checked offline on the phone
POSITION_KEEP = timedelta(days=7)
RIDE_EXPIRY = timedelta(hours=6)  # an open ride nobody picked up this long after it was wanted closes itself
MAX_OPEN_RIDES_PER_HOME = 3


class RideError(ValueError):
    """A booking that cannot be made. The message is safe to show the guard or the resident."""


def enabled(estate: Estate) -> bool:
    return EstateSettings.model_validate(estate.settings).shuttle_enabled


# --- cards and house codes -----------------------------------------------------------------


def normalise_uid(uid: str) -> str:
    return re.sub(r"[^0-9A-Fa-f]", "", uid or "").upper()


def card_hash(estate_id: UUID, uid: str) -> str:
    """What the phone sends and stores for a card: the UID is public (any reader gets it), so
    this only keeps raw UIDs out of the database and ties a card to one estate."""
    return hashlib.sha256(f"{CARD_PREFIX}|{estate_id}|{normalise_uid(uid)}".encode()).hexdigest()


def hash_secret(code: str, iterations: int = HOUSE_CODE_ITERATIONS) -> str:
    salt = os.urandom(16)
    h = hashlib.pbkdf2_hmac("sha256", code.encode(), salt, iterations)
    return f"pbkdf2-sha256${iterations}${base64.b64encode(salt).decode()}${base64.b64encode(h).decode()}"


def set_house_code(home: Home) -> str:
    """A new 4-digit code for the home. The hash goes to the phones; the code is kept
    encrypted (with the field key that protects phone numbers) only so Gatelog can send it to
    the household when they ask."""
    code = f"{secrets.randbelow(10_000):04d}"
    home.house_code_hash, home.house_code_enc, home.house_code_set_at = hash_secret(code), phones.encrypt(code), clock.now()
    return code


def house_code(home: Home) -> str:
    return phones.decrypt(home.house_code_enc) if home.house_code_enc else set_house_code(home)


# --- stops -----------------------------------------------------------------------------------


@dataclass(frozen=True)
class Stop:
    kind: str  # home | gate | place
    ref: UUID
    label: str


def stop(s: Session, kind: str, ref: UUID) -> Stop:
    """A ride's end, checked against this estate (s.get goes through RLS)."""
    model = {"home": Home, "gate": Gate, "place": Place}.get(kind)
    obj = s.get(model, ref) if model else None
    if obj is None:
        raise RideError(f"unknown {kind}")
    return Stop(kind, ref, obj.address if kind == "home" else obj.name)


def point(s: Session, kind: str, ref: UUID | None) -> tuple[float, float] | None:
    model = {"home": Home, "gate": Gate, "place": Place}.get(kind)
    obj = s.get(model, ref) if model and ref else None
    return (obj.lat, obj.lng) if obj is not None and obj.lat is not None and obj.lng is not None else None


def main_gate(s: Session) -> Gate | None:
    gates = s.scalars(select(Gate).order_by(Gate.name)).all()
    return next((g for g in gates if "main" in g.name.lower()), gates[0] if gates else None)


# --- booking ---------------------------------------------------------------------------------


def book(
    s: Session, estate: Estate, *, kind: str, source: str, home: Home, pickup: Stop, dropoff: Stop, wanted_at: datetime,
    resident: Resident | None = None, passenger: str | None = None, note: str | None = None,
    booked_by: UUID | None = None, shift_id: UUID | None = None, ride_id: UUID | None = None,
) -> Ride:
    if not enabled(estate):
        raise RideError("this estate does not run a shuttle on Gatelog")
    if pickup == dropoff:
        raise RideError("the pickup and the drop-off are the same place")
    ride = Ride(
        estate_id=estate.id, home_id=home.id, resident_id=resident.id if resident else None, kind=kind, source=source,
        state="requested", passenger=(passenger or "").strip() or None,
        pickup_kind=pickup.kind, pickup_ref=pickup.ref, pickup_label=pickup.label,
        dropoff_kind=dropoff.kind, dropoff_ref=dropoff.ref, dropoff_label=dropoff.label,
        wanted_at=wanted_at, note=(note or "").strip() or None, booked_by=booked_by, booked_shift_id=shift_id,
        created_at=clock.now(),
    )
    if ride_id:
        ride.id = ride_id
    s.add(ride)
    s.flush()
    return ride


def open_rides_for_home(s: Session, home_id: UUID) -> list[Ride]:
    return s.scalars(
        select(Ride).where(Ride.home_id == home_id, Ride.state.in_(RIDE_OPEN_STATES)).order_by(Ride.wanted_at)
    ).all()


def booked_today(s: Session, home_id: UUID, day_start: datetime) -> int:
    return s.scalar(
        select(func.count()).select_from(Ride).where(Ride.home_id == home_id, Ride.source.in_(("whatsapp", "sms")), Ride.created_at >= day_start)
    )


# --- what happens to a ride ------------------------------------------------------------------


@dataclass
class Outcome:
    applied: bool
    reason: str | None = None


def apply(
    s: Session, estate: Estate, ride: Ride, event: str, at: datetime, guard: Guard | None, shift: Shift | None, *,
    confirmed_by: str | None = None, resident_id: UUID | None = None, card_id: UUID | None = None,
) -> Outcome:
    """Move a ride on. Returns whether it changed and, if not, why (shown on the phone)."""
    gid = guard.id if guard else None
    taken_by = s.get(Guard, ride.rider_id).name if ride.rider_id and ride.rider_id != gid else None
    st = ride.state

    if event == "accept":
        if st == "accepted" and ride.rider_id == gid:
            return Outcome(True)
        if st == "accepted":
            return Outcome(False, f"taken by {taken_by}")
        if st != "requested":
            return Outcome(False, f"this ride is already {_state_words(st)}")
        ride.state, ride.rider_id, ride.accepted_at = "accepted", gid, at
        ride.shuttle_id = shift.shuttle_id if shift else None
        _notify_on_way(s, estate, ride, guard)
        return Outcome(True)

    if event == "release":
        if st != "accepted" or ride.rider_id != gid:
            return Outcome(False, "this ride is not yours to hand back")
        ride.state, ride.rider_id, ride.shuttle_id, ride.accepted_at = "requested", None, None, None
        return Outcome(True)

    if event == "pick_up":
        if st == "picked_up" and ride.rider_id == gid:
            return Outcome(True)
        if st == "done":
            return Outcome(False, "this ride is already done")
        # Physical fact: applied even over another rider's claim or a cancellation.
        ride.state, ride.rider_id, ride.picked_up_at, ride.closed_at = "picked_up", gid, at, None
        ride.accepted_at = ride.accepted_at or at
        ride.shuttle_id = (shift.shuttle_id if shift else None) or ride.shuttle_id
        _confirm(s, ride, confirmed_by, resident_id, card_id)
        if ride.kind == "delivery":
            _notify_parcel(s, estate, ride)
        return Outcome(True)

    if event == "drop_off":
        if st == "done":
            return Outcome(True)
        ride.state, ride.done_at, ride.closed_at = "done", at, None
        ride.rider_id = ride.rider_id or gid
        ride.picked_up_at = ride.picked_up_at or at
        ride.accepted_at = ride.accepted_at or ride.picked_up_at
        _confirm(s, ride, confirmed_by, resident_id, card_id)
        return Outcome(True)

    if event in ("cancel", "no_show"):
        if st in ("cancelled", "no_show"):
            return Outcome(True)
        if st not in ("requested", "accepted"):
            return Outcome(False, f"this ride is already {_state_words(st)}")
        if event == "no_show" and st == "accepted" and ride.rider_id != gid:
            return Outcome(False, f"taken by {taken_by}")
        ride.state = "cancelled" if event == "cancel" else "no_show"
        ride.closed_at = at
        return Outcome(True)

    return Outcome(False, "unknown ride event")


def _state_words(state: str) -> str:
    return {"picked_up": "under way", "done": "done", "cancelled": "cancelled", "no_show": "closed as a no-show"}.get(state, state)


def _confirm(s: Session, ride: Ride, confirmed_by: str | None, resident_id: UUID | None, card_id: UUID | None) -> None:
    if not confirmed_by or ride.confirmed_by:
        return
    if card_id:
        card = s.get(ResidentCard, card_id)
        if card is not None:
            resident_id = resident_id or card.resident_id
    resident = s.get(Resident, resident_id) if resident_id else None
    ride.confirmed_by, ride.card_id = confirmed_by, card_id
    ride.confirmed_resident_id = resident.id if resident else None


def _resident_to_tell(s: Session, ride: Ride) -> Resident | None:
    if ride.resident_id:
        return s.get(Resident, ride.resident_id)
    return s.scalars(select(Resident).where(Resident.home_id == ride.home_id, Resident.active.is_(True)).order_by(Resident.created_at)).first()


def _notify_on_way(s: Session, estate: Estate, ride: Ride, rider: Guard | None) -> None:
    """One message when a rider takes a resident's ride, so an elderly resident knows to be
    ready. Gate and flag-down rides need none: the passenger is standing with the rider."""
    if ride.kind != "resident" or ride.source not in ("whatsapp", "sms", "dispatch") or ride.resident_id is None:
        return
    resident = s.get(Resident, ride.resident_id)
    shuttle = s.get(Shuttle, ride.shuttle_id) if ride.shuttle_id else None
    name = rider.name if rider else "A rider"
    label = shuttle.label if shuttle else "the shuttle"
    messaging.to_resident(
        s, estate, resident, "ride_on_way", f"{name} is on the way on {label} to take you from {ride.pickup_label}.",
        {"rider": name, "shuttle": label, "from": ride.pickup_label},
    )


def _notify_parcel(s: Session, estate: Estate, ride: Ride) -> None:
    resident = _resident_to_tell(s, ride)
    if resident is None:
        return
    what = ride.passenger or "A parcel"
    messaging.to_resident(
        s, estate, resident, "parcel_on_way", f"{what} is on its way to you from {ride.pickup_label} on the estate shuttle.",
        {"parcel": what, "from": ride.pickup_label},
    )


def release_rider(s: Session, rider_id: UUID) -> int:
    """A rider's shift ended: rides they took but never picked up go back to the queue."""
    n = 0
    for r in s.scalars(select(Ride).where(Ride.rider_id == rider_id, Ride.state == "accepted")):
        r.state, r.rider_id, r.shuttle_id, r.accepted_at = "requested", None, None, None
        n += 1
    return n


# --- housekeeping ------------------------------------------------------------------------------


def housekeeping() -> dict[str, int]:
    """Positions older than 7 days are deleted; open rides long past their time close themselves."""
    now = clock.now()
    with db.session(ops=True) as s:
        positions = s.execute(delete(Position).where(Position.at < now - POSITION_KEEP)).rowcount
        expired = 0
        for r in s.scalars(select(Ride).where(Ride.state.in_(("requested", "accepted")), Ride.wanted_at < now - RIDE_EXPIRY)):
            r.state, r.closed_at = "cancelled", now
            s.add(RideEvent(estate_id=r.estate_id, ride_id=r.id, event="cancel", at=now))
            expired += 1
    return {"positions_deleted": positions, "rides_expired": expired}


# --- reading a ride request from a message ----------------------------------------------------


@dataclass
class RideAsk:
    to: Stop | None = None  # where the resident wants to go ("ride to clubhouse")
    from_: Stop | None = None  # where to collect them ("ride from gate")
    home: bool = False  # "ride home": from the main gate to their home
    when: datetime | None = None
    unknown_place: str | None = None


RIDE_WORD = re.compile(r"^\s*(ride|shuttle)\b[\s,.:-]*(?P<rest>.*)$", re.I | re.S)
_IN_MINUTES = re.compile(r"\bin\s+(\d{1,3})\s*(?:min(?:ute)?s?|m)\b", re.I)
_DIRECTION = re.compile(r"\b(to|from)\s+(?:the\s+|my\s+)?(?P<place>[a-z0-9'&. -]+?)\s*(?=\b(?:at|by|around|in|now|today)\b|$)", re.I)
_HOME_WORDS = {"home", "house", "my house", "my home"}


def parse_request(rest: str, now_local: datetime, s: Session) -> RideAsk:
    ask = RideAsk()
    text = rest.strip()
    m = _IN_MINUTES.search(text)
    if m:
        ask.when = now_local + timedelta(minutes=min(int(m.group(1)), 600))
    else:
        t = stay.parse_clock(text)
        if t is not None:
            when = stay.at(now_local.date(), t, now_local.tzinfo)
            ask.when = when if when > now_local - timedelta(minutes=15) else when + timedelta(days=1)
    bare = text.lower().strip(" .!")
    if bare in _HOME_WORDS:
        ask.home = True
        return ask
    d = _DIRECTION.search(text)
    if not d:
        return ask
    name = d.group("place").strip(" .").lower()
    if name in _HOME_WORDS:
        ask.home = True
        return ask
    found = _find_place(s, name)
    if found is None:
        ask.unknown_place = d.group("place").strip()
    elif d.group(1).lower() == "to":
        ask.to = found
    else:
        ask.from_ = found
    return ask


def _find_place(s: Session, name: str) -> Stop | None:
    if name in ("gate", "the gate", "main gate"):
        g = main_gate(s)
        return Stop("gate", g.id, g.name) if g else None
    candidates = [Stop("gate", g.id, g.name) for g in s.scalars(select(Gate))] + [Stop("place", p.id, p.name) for p in s.scalars(select(Place))]
    exact = [c for c in candidates if c.label.lower() == name]
    if exact:
        return exact[0]
    partial = [c for c in candidates if name in c.label.lower() or c.label.lower() in name]
    return partial[0] if len(partial) == 1 else None


def place_names(s: Session) -> list[str]:
    return [g.name for g in s.scalars(select(Gate).order_by(Gate.name))] + [p.name for p in s.scalars(select(Place).order_by(Place.name))]
