"""Visits: issuing codes, admitting, confirming exits, extending and closing."""

import uuid
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import clock, codes, messaging
from .keys import key_store
from .models import Entry, Estate, Exit, Gate, Resident, Visit

OPEN_STATES = ("inside", "overstay")


def tz(estate: Estate) -> ZoneInfo:
    return ZoneInfo(estate.timezone)


def local_now(estate: Estate) -> datetime:
    return clock.now().astimezone(tz(estate))


def clock_12h(dt: datetime) -> str:
    """'6pm', '6:30pm'."""
    h = dt.hour % 12 or 12
    suffix = "am" if dt.hour < 12 else "pm"
    return f"{h}{suffix}" if dt.minute == 0 else f"{h}:{dt.minute:02d}{suffix}"


def clock_24h(dt: datetime) -> str:
    return dt.strftime("%H:%M")


def day_phrase(d: date, today: date) -> str:
    if d == today:
        return "today"
    if d == today + timedelta(days=1):
        return "tomorrow"
    return d.strftime("%a %d %b").replace(" 0", " ")


def until_phrase(dt: datetime, estate: Estate) -> str:
    """'today until 6pm', 'Sun 25 Oct at 6pm'."""
    local = dt.astimezone(tz(estate))
    day = day_phrase(local.date(), local_now(estate).date())
    return f"{day} until {clock_12h(local)}" if day in ("today", "tomorrow") else f"{day}, {clock_12h(local)}"


def code_for(estate: Estate, v: Visit) -> str:
    key = key_store().get(estate.id, v.key_version or estate.hmac_key_version)
    return codes.derive(key, v.home_id, v.id, v.window_start, v.window_end)


def _active_codes(db: Session, estate: Estate, around: Visit) -> set[str]:
    """Codes of other coded visits whose entry windows overlap this one."""
    others = db.scalars(
        select(Visit).where(
            Visit.estate_id == estate.id,
            Visit.code_issued.is_(True),
            Visit.state.in_(("expected", "inside", "overstay")),
            Visit.window_start < around.window_end,
            Visit.window_end > around.window_start,
            Visit.id != around.id,
        )
    ).all()
    return {code_for(estate, o) for o in others}


def issue_code(db: Session, estate: Estate, v: Visit) -> str:
    """Give the visit a code that no other open visit in the estate shares, so a guard's
    lookup can never match two guests. The visit ID is an input to the HMAC, so a clash
    is resolved by drawing a new ID: call this before the visit is added to the session."""
    v.code_issued = True
    v.key_version = estate.hmac_key_version
    if v.id is None:  # the column default only fires on INSERT, and the ID is signed
        v.id = uuid.uuid4()
    taken = _active_codes(db, estate, v)
    for _ in range(10):
        code = code_for(estate, v)
        if code not in taken:
            return code
        v.id = uuid.uuid4()
    raise RuntimeError("could not draw a unique code")  # needs ~10^5 open visits to happen


def gate_name(db: Session, gate_id) -> str:
    g = db.get(Gate, gate_id)
    return g.name if g else "the gate"


def _resident_for(db: Session, v: Visit) -> Resident | None:
    return db.get(Resident, v.resident_id) if v.resident_id else None


def on_entry(db: Session, estate: Estate, entry: Entry) -> None:
    """Side effects of a newly synced entry. Runs once per entry (the sync skips duplicates)."""
    if entry.visit_id is None or entry.method == "refused":
        return
    v = db.get(Visit, entry.visit_id)
    if v is None:
        return
    if v.state == "expected":
        v.state = "inside"
        if v.stay_minutes:
            v.expected_until = entry.at + timedelta(minutes=v.stay_minutes)
    # An exit for this visit may have synced first (another gate's phone came online earlier).
    early_exit = db.scalars(select(Exit).where(Exit.visit_id == v.id, Exit.entry_id.is_(None), Exit.at >= entry.at)).first()
    if early_exit:
        early_exit.entry_id, early_exit.unmatched = entry.id, False
        v.state, v.closed_at = "left", early_exit.at
    resident = _resident_for(db, v)
    if resident:
        when = clock_24h(entry.at.astimezone(tz(estate)))
        gate = gate_name(db, entry.gate_id)
        messaging.to_resident(
            db, estate, resident, "arrival", f"{v.guest_name} is in. {gate}, {when}.",
            {"guest": v.guest_name, "gate": gate, "time": when},
        )


def on_exit(db: Session, estate: Estate, ex: Exit) -> None:
    """Link an exit to its entry and visit, close the visit, tell the resident if they want it."""
    v = db.get(Visit, ex.visit_id) if ex.visit_id else None
    if ex.entry_id is None and v is not None:
        latest = db.scalars(select(Entry).where(Entry.visit_id == v.id, Entry.method != "refused").order_by(Entry.at.desc())).first()
        ex.entry_id = latest.id if latest else None
    if ex.entry_id is not None and v is None:
        e = db.get(Entry, ex.entry_id)
        v = db.get(Visit, e.visit_id) if e and e.visit_id else None
        ex.visit_id = v.id if v else None
    ex.unmatched = ex.entry_id is None
    if v is not None and v.state not in ("left", "rollup_closed", "cancelled"):
        v.state, v.closed_at = "left", ex.at
        resident = _resident_for(db, v)
        if resident and resident.wants_exit_notices and ex.method in ("code", "list_tap"):
            when = clock_24h(ex.at.astimezone(tz(estate)))
            gate = gate_name(db, ex.gate_id) if ex.gate_id else "the gate"
            messaging.to_resident(
                db, estate, resident, "departure", f"{v.guest_name} has left. {gate}, {when}.",
                {"guest": v.guest_name, "gate": gate, "time": when},
            )


def close_by_resident(db: Session, estate: Estate, v: Visit) -> None:
    """Reply 2 to the overstay nudge: the resident says the guest has gone."""
    latest = db.scalars(select(Entry).where(Entry.visit_id == v.id, Entry.method != "refused").order_by(Entry.at.desc())).first()
    db.add(Exit(estate_id=estate.id, entry_id=latest.id if latest else None, visit_id=v.id, method="resident_confirmed", unmatched=latest is None, at=clock.now()))
    v.state, v.closed_at = "left", clock.now()


def extend(v: Visit, until: datetime) -> None:
    v.expected_until = until
    v.stay_minutes = None
    if v.state == "overstay":
        v.state = "inside"
    # The entry window is an input to the code, so it never moves once issued.
