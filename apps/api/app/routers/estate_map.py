"""The estate map behind the dashboard: the boundary the map is locked to, pins for gates,
places and homes, and the live view (who is on duty at each gate, where the shuttles are,
which rides are waiting).

Rider positions are personal data about staff: only the admin, the committee and the
security head see them. Everyone else who can read the dashboard sees the map without them.
"""

from datetime import timedelta
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .. import audit, clock, db, push, shuttle, sun, visits
from ..auth import Staff, require
from ..models import RIDE_OPEN_STATES, Device, Estate, Gate, Guard, Home, Place, Position, Ride, Shift, Shuttle, Visit
from .admin import _changed, _created, _deleted, _get, admin, reader

router = APIRouter(prefix="/v1/admin", tags=["estate map"])

POSITION_ROLES = ("admin", "committee", "security_head")
STALE_AFTER = timedelta(minutes=2)  # a rider position older than this shows greyed out
TRAIL = timedelta(minutes=10)
QUIET_AFTER = timedelta(minutes=30)  # the same rule as the CSO view's quiet phones
MAX_SPAN_DEG = 0.3  # about 33 km: no estate is larger, so a bigger boundary is a mistake
PIN_MARGIN_DEG = 0.002  # about 200 m outside the boundary's box, for a gate on the edge


def _iso(dt):
    return dt.isoformat() if dt else None


def _center(estate: Estate) -> tuple[float, float] | None:
    box = estate.bbox
    return ((box[1] + box[3]) / 2, (box[0] + box[2]) / 2) if box else None


def _sun(estate: Estate) -> dict | None:
    c = _center(estate)
    if c is None:
        return None
    now = clock.now()
    today = now.astimezone(visits.tz(estate)).date()
    rise, set_ = sun.times(today, *c)
    return {"sunrise": _iso(rise), "sunset": _iso(set_), "is_night": sun.is_night(now, c[0], c[1], today)}


def _check_pin(estate: Estate, lat: float, lng: float) -> None:
    box = estate.bbox
    if box is None:
        raise HTTPException(409, "draw the estate boundary first")
    w, s_, e, n = box
    if not (w - PIN_MARGIN_DEG <= lng <= e + PIN_MARGIN_DEG and s_ - PIN_MARGIN_DEG <= lat <= n + PIN_MARGIN_DEG):
        raise HTTPException(422, "that point is outside the estate boundary")


# --- the map ------------------------------------------------------------------------------------


@router.get("/map")
def get_map(staff: Staff = Depends(reader)) -> dict:
    with db.session(staff.estate_id) as s:
        estate = s.get(Estate, staff.estate_id)
        c = _center(estate)
        return {
            "boundary": estate.boundary,
            "bbox": estate.bbox,
            "center": {"lat": c[0], "lng": c[1]} if c else None,
            "sun": _sun(estate),
            "gates": [{"id": g.id, "name": g.name, "lat": g.lat, "lng": g.lng} for g in s.scalars(select(Gate).order_by(Gate.name))],
            "places": [{"id": p.id, "name": p.name, "kind": p.kind, "lat": p.lat, "lng": p.lng} for p in s.scalars(select(Place).order_by(Place.name))],
            "homes": [
                {"id": h.id, "address": h.address, "lat": h.lat, "lng": h.lng}
                for h in s.scalars(select(Home).where(Home.lat.is_not(None)))
            ],
        }


class BoundaryIn(BaseModel):
    """The estate's outline as [[lng, lat], ...] (GeoJSON order), 3 to 500 corners."""

    ring: list[tuple[float, float]] = Field(min_length=3, max_length=500)

    @field_validator("ring")
    @classmethod
    def _sane(cls, ring: list[tuple[float, float]]) -> list[tuple[float, float]]:
        if any(not (-180 <= lng <= 180 and -90 <= lat <= 90) for lng, lat in ring):
            raise ValueError("a corner is not a real coordinate")
        if ring[0] == ring[-1]:
            ring = ring[:-1]  # stored open; GeoJSON readers close it
        if len(ring) < 3:
            raise ValueError("an outline needs at least 3 corners")
        lngs, lats = [p[0] for p in ring], [p[1] for p in ring]
        if max(lngs) - min(lngs) > MAX_SPAN_DEG or max(lats) - min(lats) > MAX_SPAN_DEG:
            raise ValueError("that outline is larger than any estate; check the corners")
        return ring


@router.put("/map/boundary")
def set_boundary(body: BoundaryIn, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        estate = s.get(Estate, staff.estate_id)
        before = audit.snapshot(estate)
        estate.boundary = [[lng, lat] for lng, lat in body.ring]
        audit.record(s, staff.estate_id, staff.actor, "update", estate, before)
        return {"boundary": estate.boundary, "bbox": estate.bbox}


class PinIn(BaseModel):
    """A point on the map; both null removes the pin."""

    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)


def _pin(s: Session, staff: Staff, obj, body: PinIn, what: str) -> dict:
    if (body.lat is None) != (body.lng is None):
        raise HTTPException(422, "give both lat and lng, or neither")
    if body.lat is not None:
        _check_pin(s.get(Estate, staff.estate_id), body.lat, body.lng)
    _changed(s, staff, obj, body, what)
    return {"id": obj.id, "lat": obj.lat, "lng": obj.lng}


@router.put("/map/gates/{gate_id}")
def pin_gate(gate_id: UUID, body: PinIn, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        out = _pin(s, staff, _get(s, Gate, gate_id, "gate"), body, "gate")
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.put("/map/homes/{home_id}")
def pin_home(home_id: UUID, body: PinIn, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        out = _pin(s, staff, _get(s, Home, home_id, "home"), body, "home")
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


class PlaceIn(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    kind: Literal["amenity", "pickup", "post"] = "amenity"
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)


class PlacePatch(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=80)
    kind: Literal["amenity", "pickup", "post"] | None = None
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)


def _place_out(p: Place) -> dict:
    return {"id": p.id, "name": p.name, "kind": p.kind, "lat": p.lat, "lng": p.lng}


@router.post("/places", status_code=201)
def create_place(body: PlaceIn, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        _check_pin(s.get(Estate, staff.estate_id), body.lat, body.lng)
        p = _created(s, staff, Place(estate_id=staff.estate_id, name=body.name.strip(), kind=body.kind, lat=body.lat, lng=body.lng), "place")
        out = _place_out(p)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.patch("/places/{place_id}")
def update_place(place_id: UUID, body: PlacePatch, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        p = _get(s, Place, place_id, "place")
        lat = body.lat if body.lat is not None else p.lat
        lng = body.lng if body.lng is not None else p.lng
        _check_pin(s.get(Estate, staff.estate_id), lat, lng)
        _changed(s, staff, p, body, "place")
        out = _place_out(p)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.delete("/places/{place_id}", status_code=204)
def delete_place(place_id: UUID, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> None:
    """Rides keep the place's name as it read when booked, so deleting a place loses no history."""
    with db.session(staff.estate_id) as s:
        _deleted(s, staff, _get(s, Place, place_id, "place"), "place")
    bg.add_task(push.estate_changed, staff.estate_id)


# --- live -----------------------------------------------------------------------------------------


@router.get("/live")
def live(staff: Staff = Depends(reader)) -> dict:
    """Everything the live map shows, in one call the dashboard repeats every 10 seconds."""
    now = clock.now()
    with db.session(staff.estate_id) as s:
        estate = s.get(Estate, staff.estate_id)
        people = {g.id: g for g in s.scalars(select(Guard))}
        devices = s.scalars(select(Device).where(Device.revoked_at.is_(None), Device.paired_at.is_not(None))).all()
        open_shifts = s.scalars(select(Shift).where(Shift.ended_at.is_(None)).order_by(Shift.started_at)).all()

        gates = []
        for g in s.scalars(select(Gate).order_by(Gate.name)):
            gate_devices = [d for d in devices if d.gate_id == g.id]
            last = max((d.last_sync_at for d in gate_devices if d.last_sync_at), default=None)
            on_duty = [sh for sh in open_shifts if sh.gate_id == g.id and people.get(sh.guard_id) and people[sh.guard_id].role != "rider"]
            gates.append({
                "id": g.id, "name": g.name, "lat": g.lat, "lng": g.lng,
                "on_duty": [{"guard": people[sh.guard_id].name, "role": people[sh.guard_id].role, "since": _iso(sh.started_at)} for sh in on_duty],
                "phone_last_sync_at": _iso(last),
                "phones": len(gate_devices),
                "quiet": bool(gate_devices) and (last is None or now - last > QUIET_AFTER),
            })

        waiting = s.scalars(
            select(Ride).where(Ride.state == "requested", Ride.wanted_at <= now + timedelta(minutes=15)).order_by(Ride.wanted_at)
        ).all()
        def ride_brief(r: Ride) -> dict:
            pt = shuttle.point(s, r.pickup_kind, r.pickup_ref)
            return {
                "id": r.id, "kind": r.kind, "state": r.state, "from": r.pickup_label, "to": r.dropoff_label,
                "lat": pt[0] if pt else None, "lng": pt[1] if pt else None, "wanted_at": _iso(r.wanted_at),
                "waiting_minutes": max(0, int((now - r.wanted_at).total_seconds() // 60)),
            }

        shuttles = None
        if staff.role in POSITION_ROLES:
            rider_shifts = [sh for sh in open_shifts if people.get(sh.guard_id) and people[sh.guard_id].role == "rider"]
            labels = {v.id: v.label for v in s.scalars(select(Shuttle))}
            shuttles = []
            for sh in rider_shifts:
                trail = s.scalars(
                    select(Position).where(Position.shift_id == sh.id, Position.at >= now - TRAIL).order_by(Position.at.desc()).limit(40)
                ).all()
                latest = trail[0] if trail else s.scalars(select(Position).where(Position.shift_id == sh.id).order_by(Position.at.desc()).limit(1)).first()
                current = s.scalars(
                    select(Ride).where(Ride.rider_id == sh.guard_id, Ride.state.in_(("accepted", "picked_up"))).order_by(Ride.accepted_at)
                ).first()
                shuttles.append({
                    "shift_id": sh.id, "rider": people[sh.guard_id].name, "shuttle": labels.get(sh.shuttle_id), "since": _iso(sh.started_at),
                    "lat": latest.lat if latest else None, "lng": latest.lng if latest else None,
                    "heading": latest.heading if latest else None, "speed": latest.speed if latest else None,
                    "at": _iso(latest.at) if latest else None, "stale": latest is None or now - latest.at > STALE_AFTER,
                    "trail": [[p.lng, p.lat] for p in reversed(trail)],
                    "ride": ride_brief(current) if current else None,
                })

        return {
            "server_time": now.isoformat(),
            "bbox": estate.bbox,
            "sun": _sun(estate),
            "gates": gates,
            "places": [_place_out(p) for p in s.scalars(select(Place).order_by(Place.name))],
            "shuttles": shuttles,  # null: this role does not see rider positions
            "rides_waiting": [ride_brief(r) for r in waiting],
            "counts": {
                "inside": s.scalar(select(func.count()).select_from(Visit).where(Visit.state.in_(visits.OPEN_STATES))),
                "overdue": s.scalar(select(func.count()).select_from(Visit).where(Visit.state.in_(visits.OPEN_STATES), Visit.expected_until < now)),
                "rides_open": s.scalar(select(func.count()).select_from(Ride).where(Ride.state.in_(RIDE_OPEN_STATES))),
                "on_duty": len([sh for sh in open_shifts if people.get(sh.guard_id) and people[sh.guard_id].role != "rider"]),
            },
        }
