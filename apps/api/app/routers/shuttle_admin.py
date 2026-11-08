"""The estate shuttle in the dashboard: the motorcycles, the ride log, residents' cards, house
codes, and the monthly report the Exco reads to see who the shuttle serves."""

from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from statistics import median
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import select

from .. import audit, clock, db, push, shuttle, visits
from ..auth import Staff
from ..models import Estate, Guard, Home, Resident, ResidentCard, Ride, RideEvent, Shuttle
from .admin import _changed, _created, _get, admin, reader

router = APIRouter(prefix="/v1", tags=["shuttle"])


def _iso(dt):
    return dt.isoformat() if dt else None


# --- motorcycles ------------------------------------------------------------------------------------


class ShuttleIn(BaseModel):
    label: str = Field(min_length=1, max_length=40)
    plate: str | None = Field(default=None, max_length=16)


class ShuttlePatch(BaseModel):
    label: str | None = Field(default=None, min_length=1, max_length=40)
    plate: str | None = Field(default=None, max_length=16)
    active: bool | None = None


def _shuttle_out(v: Shuttle) -> dict:
    return {"id": v.id, "label": v.label, "plate": v.plate, "active": v.active}


@router.get("/admin/shuttles")
def list_shuttles(staff: Staff = Depends(reader)) -> list[dict]:
    with db.session(staff.estate_id) as s:
        return [_shuttle_out(v) for v in s.scalars(select(Shuttle).order_by(Shuttle.label))]


@router.post("/admin/shuttles", status_code=201)
def create_shuttle(body: ShuttleIn, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        v = _created(s, staff, Shuttle(estate_id=staff.estate_id, label=body.label.strip(), plate=(body.plate or "").strip().upper() or None), "shuttle")
        out = _shuttle_out(v)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.patch("/admin/shuttles/{shuttle_id}")
def update_shuttle(shuttle_id: UUID, body: ShuttlePatch, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    """No delete: rides point at the motorcycle. Retire one with active=false."""
    with db.session(staff.estate_id) as s:
        v = _get(s, Shuttle, shuttle_id, "shuttle")
        _changed(s, staff, v, body, "shuttle")
        out = _shuttle_out(v)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


# --- rides -----------------------------------------------------------------------------------------


def _ride_out(r: Ride, names: dict[UUID, str], residents: dict[UUID, str], labels: dict[UUID, str]) -> dict:
    return {
        "id": r.id, "kind": r.kind, "source": r.source, "state": r.state, "home_id": r.home_id, "passenger": r.passenger,
        "resident": residents.get(r.resident_id) if r.resident_id else None,
        "from": r.pickup_label, "to": r.dropoff_label, "wanted_at": _iso(r.wanted_at),
        "booked_by": names.get(r.booked_by) if r.booked_by else None,
        "rider": names.get(r.rider_id) if r.rider_id else None, "shuttle": labels.get(r.shuttle_id) if r.shuttle_id else None,
        "confirmed_by": r.confirmed_by,
        "confirmed_resident": residents.get(r.confirmed_resident_id) if r.confirmed_resident_id else None,
        "accepted_at": _iso(r.accepted_at), "picked_up_at": _iso(r.picked_up_at), "done_at": _iso(r.done_at),
        "closed_at": _iso(r.closed_at), "created_at": _iso(r.created_at),
    }


def _lookups(s) -> tuple[dict, dict, dict]:
    return (
        {g.id: g.name for g in s.scalars(select(Guard))},
        {r.id: r.name for r in s.scalars(select(Resident))},
        {v.id: v.label for v in s.scalars(select(Shuttle))},
    )


@router.get("/admin/rides")
def list_rides(
    since: datetime | None = None, until: datetime | None = None, state: str | None = None, home_id: UUID | None = None,
    rider_id: UUID | None = None, limit: int = 200, staff: Staff = Depends(reader),
) -> list[dict]:
    with db.session(staff.estate_id) as s:
        q = select(Ride).order_by(Ride.wanted_at.desc()).limit(min(limit, 1000))
        if since:
            q = q.where(Ride.wanted_at >= since)
        if until:
            q = q.where(Ride.wanted_at < until)
        if state:
            q = q.where(Ride.state.in_([x for x in state.split(",") if x]))
        if home_id:
            q = q.where(Ride.home_id == home_id)
        if rider_id:
            q = q.where(Ride.rider_id == rider_id)
        rides = s.scalars(q).all()
        names, residents, labels = _lookups(s)
        addresses = {h.id: h.address for h in s.scalars(select(Home).where(Home.id.in_({r.home_id for r in rides})))}
        return [_ride_out(r, names, residents, labels) | {"address": addresses.get(r.home_id)} for r in rides]


@router.get("/admin/rides/{ride_id}")
def get_ride(ride_id: UUID, staff: Staff = Depends(reader)) -> dict:
    """One ride with everything that happened to it, including taps that lost (a second rider)."""
    with db.session(staff.estate_id) as s:
        r = _get(s, Ride, ride_id, "ride")
        names, residents, labels = _lookups(s)
        events = s.scalars(select(RideEvent).where(RideEvent.ride_id == r.id).order_by(RideEvent.at)).all()
        return _ride_out(r, names, residents, labels) | {
            "address": s.get(Home, r.home_id).address,
            "events": [{"event": e.event, "by": names.get(e.guard_id) if e.guard_id else None, "applied": e.applied, "at": _iso(e.at)} for e in events],
        }


# --- cards and house codes ---------------------------------------------------------------------------


@router.get("/admin/cards")
def list_cards(home_id: UUID | None = None, staff: Staff = Depends(reader)) -> list[dict]:
    with db.session(staff.estate_id) as s:
        q = select(ResidentCard).order_by(ResidentCard.issued_at.desc())
        if home_id:
            q = q.where(ResidentCard.home_id == home_id)
        names, residents, _ = _lookups(s)
        return [
            {"id": c.id, "resident_id": c.resident_id, "resident": residents.get(c.resident_id), "home_id": c.home_id,
             "uid_last4": c.uid_last4, "issued_at": _iso(c.issued_at), "issued_by": names.get(c.issued_by) if c.issued_by else None,
             "revoked_at": _iso(c.revoked_at)}
            for c in s.scalars(q)
        ]


@router.post("/admin/cards/{card_id}/revoke")
def revoke_card(card_id: UUID, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    """A lost card stops identifying anyone at the next sync of each rider phone."""
    with db.session(staff.estate_id) as s:
        c = _get(s, ResidentCard, card_id, "card")
        if c.revoked_at is None:
            before = audit.snapshot(c)
            c.revoked_at = clock.now()
            audit.record(s, staff.estate_id, staff.actor, "revoke", c, before)
        out = {"id": c.id, "revoked_at": _iso(c.revoked_at)}
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.post("/admin/homes/{home_id}/house-code")
def new_house_code(home_id: UUID, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    """A new code for the home, shown once, for the admin to give an elderly resident by phone.
    The old code stops working at the next sync of each rider phone. Audited, without the code."""
    with db.session(staff.estate_id) as s:
        if not shuttle.enabled(s.get(Estate, staff.estate_id)):
            raise HTTPException(409, "turn the shuttle on in settings first")
        h = _get(s, Home, home_id, "home")
        code = shuttle.set_house_code(h)
        audit.record(s, staff.estate_id, staff.actor, "new_house_code", h)
    bg.add_task(push.estate_changed, staff.estate_id)
    return {"home_id": home_id, "code": code}


# --- report -----------------------------------------------------------------------------------------


@router.get("/reports/shuttle")
def shuttle_report(month: str | None = Query(None, pattern=r"^\d{4}-\d{2}$"), staff: Staff = Depends(reader)) -> dict:
    """Who the shuttle served in a month: rides by kind and how they were booked, by zone and by
    rider, how long people waited for a rider to take their ride, no-shows and cancellations."""
    with db.session(staff.estate_id) as s:
        estate = s.get(Estate, staff.estate_id)
        tz = visits.tz(estate)
        today = clock.now().astimezone(tz).date()
        first = date(int(month[:4]), int(month[5:]), 1) if month else today.replace(day=1)
        nxt = (first.replace(day=28) + timedelta(days=4)).replace(day=1)
        start = datetime(first.year, first.month, 1, tzinfo=tz)
        end = datetime(nxt.year, nxt.month, 1, tzinfo=tz)
        rides = s.scalars(select(Ride).where(Ride.wanted_at >= start, Ride.wanted_at < end)).all()
        names = {g.id: g.name for g in s.scalars(select(Guard))}
        zones = {h.id: h.street.zone.name for h in s.scalars(select(Home).where(Home.id.in_({r.home_id for r in rides})))}
        done = [r for r in rides if r.state == "done"]
        waits = [
            max(0.0, (r.accepted_at - max(r.wanted_at, r.created_at)).total_seconds() / 60)
            for r in rides if r.accepted_at and r.source in ("whatsapp", "sms", "dispatch")
        ]
        by_zone: dict[str, Counter] = defaultdict(Counter)
        for r in done:
            by_zone[zones.get(r.home_id, "?")][r.kind] += 1
        return {
            "month": first.strftime("%Y-%m"),
            "rides": len(rides),
            "done": len(done),
            "by_kind": dict(Counter(r.kind for r in done)),
            "by_source": dict(Counter(r.source for r in rides)),
            "by_state": dict(Counter(r.state for r in rides)),
            "by_zone": [{"zone": z, "rides": sum(c.values()), **c} for z, c in sorted(by_zone.items())],
            "by_rider": [{"rider": names.get(g, "?"), "rides": n} for g, n in Counter(r.rider_id for r in done if r.rider_id).most_common()],
            "homes_served": len({r.home_id for r in done}),
            "median_wait_minutes": round(median(waits), 1) if waits else None,
            "confirmed_by": dict(Counter(r.confirmed_by or "not recorded" for r in done)),
        }
