"""Estate admin (facility manager, secretary): the address register, residents and their
numbers, guards, gates, devices, the estate tier of the directory, staff and settings.
Every change to the register, contacts and directory is written to the audit log."""

from datetime import datetime, time, timedelta
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .. import audit, clock, db, directory, keys, phones, push, storage
from ..auth import Staff, new_pairing_code, require, sha256
from ..estate_settings import EstateSettings
from ..plates import normalise_plate
from ..models import (
    ENTRY_METHODS,
    DirectoryEntry,
    Device,
    Entry,
    Estate,
    Exit,
    Gate,
    Guard,
    Home,
    PhoneNumber,
    Resident,
    Shift,
    StaffUser,
    Vehicle,
    Street,
    Visit,
    VoiceClip,
    GatePhoto,
    Zone,
)

router = APIRouter(prefix="/v1/admin", tags=["estate admin"])
admin = require("admin")
reader = require("admin", "committee", "security_head", "treasurer", "org_admin", "org_viewer")
selfie_viewer = require("admin", "security_head")
# Who owes the levy is dues information: the Exco and the treasurer see it, the security head does not.
DUES_ROLES = ("admin", "committee", "treasurer")

MAX_NUMBERS_PER_HOME = 3
PAIRING_TTL = timedelta(hours=24)


def _flush(s: Session, what: str) -> None:
    try:
        s.flush()
    except IntegrityError:
        raise HTTPException(409, f"{what} already exists")


def _get(s: Session, model, id_: UUID, what: str):
    obj = s.get(model, id_)  # RLS: anything from another estate reads as missing
    if obj is None:
        raise HTTPException(404, f"no such {what}")
    return obj


def _changed(s: Session, staff: Staff, obj, body: BaseModel, what: str) -> None:
    before = audit.snapshot(obj)
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(obj, k, v)
    _flush(s, what)
    audit.record(s, staff.estate_id, staff.actor, "update", obj, before)


def _created(s: Session, staff: Staff, obj, what: str):
    s.add(obj)
    _flush(s, what)
    audit.record(s, staff.estate_id, staff.actor, "create", obj)
    return obj


def _deleted(s: Session, staff: Staff, obj, what: str) -> None:
    before = audit.snapshot(obj)
    s.delete(obj)
    try:
        s.flush()
    except IntegrityError:
        raise HTTPException(409, f"this {what} has visits or entries logged against it and cannot be deleted")
    audit.record(s, staff.estate_id, staff.actor, "delete", obj, before)


# --- estate and settings -------------------------------------------------------------------


@router.get("/estate")
def get_estate(staff: Staff = Depends(reader)) -> dict:
    with db.session(staff.estate_id) as s:
        e = s.get(Estate, staff.estate_id)
        return {
            "id": e.id, "name": e.name, "short_name": e.short_name, "sender_name": e.sender_name, "state": e.state, "lga": e.lga,
            "timezone": e.timezone, "settings": EstateSettings.model_validate(e.settings).model_dump(mode="json"), "role": staff.role,
        }


class EstatePatch(BaseModel):
    # Every message starts with this ("SKA Exco: ..."), because all estates share one WhatsApp number.
    short_name: str | None = Field(default=None, min_length=2, max_length=40)


@router.patch("/estate")
def update_estate(body: EstatePatch, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        e = s.get(Estate, staff.estate_id)
        before = audit.snapshot(e)
        if "short_name" in body.model_fields_set:
            e.short_name = body.short_name.strip() if body.short_name else None
        audit.record(s, staff.estate_id, staff.actor, "update", e, before)
        return {"short_name": e.short_name, "sender_name": e.sender_name}


class SettingsPatch(BaseModel):
    """Any subset of EstateSettings. Validated field by field, so a bad value is a 422."""

    model_config = {"extra": "forbid"}
    default_stay_until: time | None = None
    code_valid_until: time | None = None
    rollup_time: time | None = None
    handover_time: time | None = None
    walk_in_policy: str | None = Field(default=None, min_length=5, max_length=280)
    daily_sms_budget: int | None = Field(default=None, ge=10, le=20000)
    max_visits_per_home_per_day: int | None = Field(default=None, ge=5, le=500)
    whatsapp_enabled: bool | None = None
    shuttle_enabled: bool | None = None
    visitor_photos: Literal["all", "phone_entries", "off"] | None = None
    max_rides_per_home_per_day: int | None = Field(default=None, ge=2, le=200)


@router.patch("/estate/settings")
def update_settings(body: SettingsPatch, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    changes = body.model_dump(exclude_unset=True, mode="json")
    with db.session(staff.estate_id) as s:
        e = s.get(Estate, staff.estate_id)
        before = audit.snapshot(e)
        merged = EstateSettings.model_validate({**e.settings, **changes})
        if merged.handover_time >= merged.rollup_time:
            raise HTTPException(422, "The morning handover must be earlier in the day than the night list.")
        e.settings = merged.model_dump(mode="json")
        audit.record(s, staff.estate_id, staff.actor, "update", e, before)
        out = e.settings
    bg.add_task(push.estate_changed, staff.estate_id)  # the walk-in rule and the shuttle switch reach the phones
    return out


# --- register ------------------------------------------------------------------------------


class NameIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)


class StreetIn(BaseModel):
    zone_id: UUID
    name: str = Field(min_length=1, max_length=120)


class StreetPatch(BaseModel):
    zone_id: UUID | None = None
    name: str | None = Field(default=None, min_length=1, max_length=120)


class HomeIn(BaseModel):
    street_id: UUID
    label: str = Field(min_length=1, max_length=40)
    levy_payer: Literal["landlord", "occupant"] = "occupant"


class HomePatch(BaseModel):
    street_id: UUID | None = None
    label: str | None = Field(default=None, min_length=1, max_length=40)
    levy_payer: Literal["landlord", "occupant"] | None = None


@router.get("/register")
def register(staff: Staff = Depends(reader)) -> list[dict]:
    """The whole four-level register: zones, their streets, their homes."""
    with db.session(staff.estate_id) as s:
        counts = dict(s.execute(select(Resident.home_id, func.count()).where(Resident.active.is_(True)).group_by(Resident.home_id)).all())
        homes_by_street: dict[UUID, list] = {}
        for h in s.scalars(select(Home).order_by(Home.label)):
            homes_by_street.setdefault(h.street_id, []).append({"id": h.id, "label": h.label, "address": h.address, "residents": counts.get(h.id, 0)})
        streets_by_zone: dict[UUID, list] = {}
        for st in s.scalars(select(Street).order_by(Street.name)):
            streets_by_zone.setdefault(st.zone_id, []).append({"id": st.id, "name": st.name, "homes": homes_by_street.get(st.id, [])})
        return [{"id": z.id, "name": z.name, "streets": streets_by_zone.get(z.id, [])} for z in s.scalars(select(Zone).order_by(Zone.name))]


@router.post("/zones", status_code=201)
def create_zone(body: NameIn, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        z = _created(s, staff, Zone(estate_id=staff.estate_id, name=body.name.strip()), "zone")
        return {"id": z.id, "name": z.name}


@router.patch("/zones/{zone_id}")
def update_zone(zone_id: UUID, body: NameIn, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        z = _get(s, Zone, zone_id, "zone")
        _changed(s, staff, z, body, "zone")
        return {"id": z.id, "name": z.name}


def _refuse_if_any(s: Session, stmt, message: str) -> None:
    if s.scalar(select(func.count()).select_from(stmt.subquery())):
        raise HTTPException(409, message)


@router.delete("/zones/{zone_id}", status_code=204)
def delete_zone(zone_id: UUID, staff: Staff = Depends(admin)) -> None:
    """Only an empty zone. Deleting must never take homes, residents and numbers with it."""
    with db.session(staff.estate_id) as s:
        z = _get(s, Zone, zone_id, "zone")
        _refuse_if_any(s, select(Street.id).where(Street.zone_id == z.id), "This zone still has streets. Delete or move them first.")
        _deleted(s, staff, z, "zone")


@router.post("/streets", status_code=201)
def create_street(body: StreetIn, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        _get(s, Zone, body.zone_id, "zone")
        st = _created(s, staff, Street(estate_id=staff.estate_id, zone_id=body.zone_id, name=body.name.strip()), "street")
        return {"id": st.id, "name": st.name, "zone_id": st.zone_id}


@router.patch("/streets/{street_id}")
def update_street(street_id: UUID, body: StreetPatch, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        st = _get(s, Street, street_id, "street")
        if body.zone_id:
            _get(s, Zone, body.zone_id, "zone")
        _changed(s, staff, st, body, "street")
        return {"id": st.id, "name": st.name, "zone_id": st.zone_id}


@router.delete("/streets/{street_id}", status_code=204)
def delete_street(street_id: UUID, staff: Staff = Depends(admin)) -> None:
    with db.session(staff.estate_id) as s:
        st = _get(s, Street, street_id, "street")
        _refuse_if_any(s, select(Home.id).where(Home.street_id == st.id), "This street still has homes. Delete or move them first.")
        _deleted(s, staff, st, "street")


@router.post("/homes", status_code=201)
def create_home(body: HomeIn, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        _get(s, Street, body.street_id, "street")
        h = _created(s, staff, Home(estate_id=staff.estate_id, street_id=body.street_id, label=body.label.strip().upper(), levy_payer=body.levy_payer), "home")
        s.refresh(h)
        out = {"id": h.id, "label": h.label, "address": h.address}
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.patch("/homes/{home_id}")
def update_home(home_id: UUID, body: HomePatch, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        h = _get(s, Home, home_id, "home")
        if body.street_id:
            _get(s, Street, body.street_id, "street")
        if body.label:
            body.label = body.label.strip().upper()
        _changed(s, staff, h, body, "home")
        s.refresh(h)
        out = {"id": h.id, "label": h.label, "address": h.address}
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.delete("/homes/{home_id}", status_code=204)
def delete_home(home_id: UUID, staff: Staff = Depends(admin)) -> None:
    with db.session(staff.estate_id) as s:
        h = _get(s, Home, home_id, "home")
        _refuse_if_any(s, select(Resident.id).where(Resident.home_id == h.id), "This home still has residents. Remove them first.")
        _deleted(s, staff, h, "home")


# --- residents and numbers -----------------------------------------------------------------


def _number_out(n: PhoneNumber) -> dict:
    return {"id": n.id, "last4": n.last4, "masked": f"***{n.last4}", "is_primary": n.is_primary, "verified_at": n.verified_at,
            "pending": n.pending_until is not None}  # offered at the gate, waiting for the home's YES


def _resident_out(s: Session, r: Resident) -> dict:
    nums = s.scalars(select(PhoneNumber).where(PhoneNumber.resident_id == r.id).order_by(PhoneNumber.is_primary.desc())).all()
    return {
        "id": r.id, "home_id": r.home_id, "address": r.home.address, "name": r.name, "relation": r.relation, "contact_pref": r.contact_pref,
        "callback_required": r.callback_required, "exit_notices": r.wants_exit_notices, "active": r.active,
        "numbers": [_number_out(n) for n in nums],
    }


def add_number(s: Session, estate_id: UUID, actor: str, resident: Resident, raw: str, is_primary: bool = False,
               pending_until=None) -> PhoneNumber:
    """Register a number to a resident. A home holds at most three (resident, spouse,
    live-in carer); only these count for callbacks. A pending number (offered at the gate)
    counts towards the three but is used for nothing until the home confirms it."""
    try:
        e164 = phones.normalise(raw)
    except phones.InvalidPhone:
        raise HTTPException(422, "That is not a phone number we can use. Nigerian numbers like 0803 123 4567, or +44... for abroad.")
    s.execute(select(Home.id).where(Home.id == resident.home_id).with_for_update())  # serialise concurrent adds to one home
    count = s.scalar(select(func.count()).select_from(PhoneNumber).where(PhoneNumber.home_id == resident.home_id))
    if count >= MAX_NUMBERS_PER_HOME:
        raise HTTPException(409, f"A home can register at most {MAX_NUMBERS_PER_HOME} numbers. Remove one first.")
    idx = phones.blind_index(e164)
    if s.scalar(select(func.count()).select_from(PhoneNumber).where(PhoneNumber.home_id == resident.home_id, PhoneNumber.e164_index == idx)):
        raise HTTPException(409, "That number is already registered to this home.")
    has_primary = s.scalar(select(func.count()).select_from(PhoneNumber).where(PhoneNumber.resident_id == resident.id, PhoneNumber.is_primary.is_(True)))
    if is_primary and has_primary:
        for other in s.scalars(select(PhoneNumber).where(PhoneNumber.resident_id == resident.id)):
            other.is_primary = False
    n = PhoneNumber(
        estate_id=estate_id, home_id=resident.home_id, resident_id=resident.id, e164_enc=phones.encrypt(e164), e164_index=idx,
        last4=phones.last4(e164), is_primary=pending_until is None and (is_primary or not has_primary), pending_until=pending_until,
    )
    s.add(n)
    s.flush()
    audit.record(s, estate_id, actor, "offer_number" if pending_until else "create", n)
    return n


class ResidentIn(BaseModel):
    home_id: UUID
    name: str = Field(min_length=2, max_length=120)
    relation: Literal["landlord", "occupant"] = "occupant"
    contact_pref: Literal["whatsapp", "sms", "call"] = "whatsapp"
    callback_required: bool = False
    exit_notices: bool | None = None
    numbers: list[str] = Field(default=[], max_length=3)


class ResidentPatch(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=120)
    relation: Literal["landlord", "occupant"] | None = None
    contact_pref: Literal["whatsapp", "sms", "call"] | None = None
    callback_required: bool | None = None
    exit_notices: bool | None = None
    active: bool | None = None


class NumberIn(BaseModel):
    number: str
    is_primary: bool = False


@router.get("/homes/{home_id}")
def get_home(home_id: UUID, staff: Staff = Depends(reader)) -> dict:
    with db.session(staff.estate_id) as s:
        h = _get(s, Home, home_id, "home")
        residents = s.scalars(select(Resident).where(Resident.home_id == h.id).order_by(Resident.name)).all()
        vehicles = s.scalars(select(Vehicle).where(Vehicle.home_id == h.id).order_by(Vehicle.plate)).all()
        return {
            "id": h.id, "label": h.label, "address": h.address,
            "levy_payer": h.levy_payer if staff.role in DUES_ROLES else None,
            "residents": [_resident_out(s, r) for r in residents],
            "vehicles": [{"id": v.id, "plate": v.plate, "description": v.description} for v in vehicles],
        }


class VehicleIn(BaseModel):
    plate: str = Field(min_length=3, max_length=20)
    description: str | None = Field(default=None, max_length=80)


@router.post("/homes/{home_id}/vehicles", status_code=201)
def create_vehicle(home_id: UUID, body: VehicleIn, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        _get(s, Home, home_id, "home")
        v = _created(s, staff, Vehicle(estate_id=staff.estate_id, home_id=home_id, plate=normalise_plate(body.plate),
                                       description=(body.description or "").strip() or None), "vehicle with that plate")
        out = {"id": v.id, "plate": v.plate, "description": v.description}
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.delete("/vehicles/{vehicle_id}", status_code=204)
def delete_vehicle(vehicle_id: UUID, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> None:
    with db.session(staff.estate_id) as s:
        _deleted(s, staff, _get(s, Vehicle, vehicle_id, "vehicle"), "vehicle")
    bg.add_task(push.estate_changed, staff.estate_id)


@router.get("/residents")
def list_residents(q: str | None = None, staff: Staff = Depends(reader)) -> list[dict]:
    with db.session(staff.estate_id) as s:
        stmt = select(Resident).where(Resident.active.is_(True)).order_by(Resident.name).limit(200)
        if q:
            stmt = stmt.where(Resident.name.ilike(f"%{q}%"))
        return [_resident_out(s, r) for r in s.scalars(stmt)]


@router.post("/residents", status_code=201)
def create_resident(body: ResidentIn, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        _get(s, Home, body.home_id, "home")
        r = _created(s, staff, Resident(
            estate_id=staff.estate_id, home_id=body.home_id, name=body.name.strip(), relation=body.relation, contact_pref=body.contact_pref,
            callback_required=body.callback_required, exit_notices=body.exit_notices,
        ), "resident")
        for i, raw in enumerate(body.numbers):
            add_number(s, staff.estate_id, staff.actor, r, raw, is_primary=i == 0)
        out = _resident_out(s, r)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.patch("/residents/{resident_id}")
def update_resident(resident_id: UUID, body: ResidentPatch, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        r = _get(s, Resident, resident_id, "resident")
        _changed(s, staff, r, body, "resident")
        out = _resident_out(s, r)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.post("/residents/{resident_id}/numbers", status_code=201)
def create_number(resident_id: UUID, body: NumberIn, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        r = _get(s, Resident, resident_id, "resident")
        out = _number_out(add_number(s, staff.estate_id, staff.actor, r, body.number, body.is_primary))
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.delete("/numbers/{number_id}", status_code=204)
def delete_number(number_id: UUID, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> None:
    with db.session(staff.estate_id) as s:
        _deleted(s, staff, _get(s, PhoneNumber, number_id, "number"), "number")
    bg.add_task(push.estate_changed, staff.estate_id)


# --- staff ---------------------------------------------------------------------------------


class StaffIn(BaseModel):
    email: EmailStr
    name: str = Field(min_length=2, max_length=120)
    role: Literal["admin", "committee", "security_head", "treasurer"]
    phone: str | None = None  # the CSO (security head) gets the night list by SMS or WhatsApp


@router.get("/staff")
def list_staff(staff: Staff = Depends(admin)) -> list[dict]:
    with db.session(staff.estate_id) as s:
        rows = s.scalars(select(StaffUser).where(StaffUser.estate_id == staff.estate_id).order_by(StaffUser.name)).all()
        nums = {n.staff_id: n for n in s.scalars(select(PhoneNumber).where(PhoneNumber.staff_id.in_([r.id for r in rows])))}
        return [{"id": r.id, "email": r.email, "name": r.name, "role": r.role, "active": r.active,
                 "phone": f"***{nums[r.id].last4}" if r.id in nums else None} for r in rows]


@router.post("/staff", status_code=201)
def create_staff(body: StaffIn, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        u = StaffUser(estate_id=staff.estate_id, email=body.email.lower(), name=body.name.strip(), role=body.role)
        s.add(u)
        _flush(s, "a staff member with that email")
        if body.phone:
            try:
                e164 = phones.normalise(body.phone)
            except phones.InvalidPhone:
                raise HTTPException(422, "That is not a phone number we can use.")
            s.add(PhoneNumber(estate_id=staff.estate_id, staff_id=u.id, e164_enc=phones.encrypt(e164),
                              e164_index=phones.blind_index(e164), last4=phones.last4(e164), is_primary=True))
        s.flush()
        audit.record(s, staff.estate_id, staff.actor, "create", u)
        return {"id": u.id, "email": u.email, "name": u.name, "role": u.role}


@router.patch("/staff/{staff_id}")
def deactivate_staff(staff_id: UUID, active: bool, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        u = s.get(StaffUser, staff_id)
        if u is None or u.estate_id != staff.estate_id:
            raise HTTPException(404, "no such staff member")
        before = audit.snapshot(u)
        u.active = active
        audit.record(s, staff.estate_id, staff.actor, "update", u, before)
        return {"id": u.id, "active": u.active}


# --- gates, guards, devices ----------------------------------------------------------------


class GuardIn(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    role: Literal["guard", "cso", "rider"] = "guard"
    # The guard has signed the written consent to shift selfies (NDPA). Without it the gate
    # phone will not start their shift.
    consent_recorded: bool = False


class GuardPatch(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=120)
    role: Literal["guard", "cso", "rider"] | None = None
    consent_recorded: bool | None = None
    active: bool | None = None


def _guard_out(g: Guard) -> dict:
    return {"id": g.id, "name": g.name, "role": g.role, "active": g.active, "consent_at": g.consent_at,
            "pin_set": g.pin_hash is not None, "pin_set_at": g.pin_set_at}


class DeviceIn(BaseModel):
    gate_id: UUID
    label: str = Field(min_length=1, max_length=80)


@router.get("/gates")
def list_gates(staff: Staff = Depends(reader)) -> list[dict]:
    with db.session(staff.estate_id) as s:
        return [{"id": g.id, "name": g.name, "lat": g.lat, "lng": g.lng} for g in s.scalars(select(Gate).order_by(Gate.name))]


@router.post("/gates", status_code=201)
def create_gate(body: NameIn, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        g = _created(s, staff, Gate(estate_id=staff.estate_id, name=body.name.strip()), "gate")
        return {"id": g.id, "name": g.name}


@router.patch("/gates/{gate_id}")
def rename_gate(gate_id: UUID, body: NameIn, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        g = _get(s, Gate, gate_id, "gate")
        _changed(s, staff, g, body, "gate")
        out = {"id": g.id, "name": g.name}
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.get("/guards")
def list_guards(staff: Staff = Depends(reader)) -> list[dict]:
    with db.session(staff.estate_id) as s:
        return [_guard_out(g) for g in s.scalars(select(Guard).order_by(Guard.name))]


@router.post("/guards", status_code=201)
def create_guard(body: GuardIn, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        g = _created(s, staff, Guard(estate_id=staff.estate_id, name=body.name.strip(), role=body.role,
                                     consent_at=clock.now() if body.consent_recorded else None), "guard")
        out = _guard_out(g)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.patch("/guards/{guard_id}")
def update_guard(guard_id: UUID, body: GuardPatch, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        g = _get(s, Guard, guard_id, "guard")
        before = audit.snapshot(g)
        for k, v in body.model_dump(exclude_unset=True, exclude={"consent_recorded"}).items():
            setattr(g, k, v)
        if body.consent_recorded is not None:
            g.consent_at = (g.consent_at or clock.now()) if body.consent_recorded else None
        _flush(s, "guard")
        audit.record(s, staff.estate_id, staff.actor, "update", g, before)
        out = _guard_out(g)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.post("/guards/{guard_id}/reset-pin")
def reset_pin(guard_id: UUID, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    """A forgotten PIN. The guard sets a new one at their next shift; the admin never knows it."""
    with db.session(staff.estate_id) as s:
        g = _get(s, Guard, guard_id, "guard")
        before = audit.snapshot(g)
        g.pin_hash, g.pin_set_at, g.pin_reset_at = None, None, clock.now()
        audit.record(s, staff.estate_id, staff.actor, "reset_pin", g, before)
        out = _guard_out(g)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


# --- shifts --------------------------------------------------------------------------------


@router.get("/shifts")
def list_shifts(since: datetime | None = None, until: datetime | None = None, staff: Staff = Depends(reader)) -> list[dict]:
    with db.session(staff.estate_id) as s:
        stmt = select(Shift).order_by(Shift.started_at.desc()).limit(300)
        if since:
            stmt = stmt.where(Shift.started_at >= since)
        if until:
            stmt = stmt.where(Shift.started_at < until)
        rows = s.scalars(stmt).all()
        people = {g.id: g for g in s.scalars(select(Guard))}
        gates = {g.id: g.name for g in s.scalars(select(Gate))}
        return [
            {
                "id": sh.id, "guard": people[sh.guard_id].name if sh.guard_id in people else None,
                "role": people[sh.guard_id].role if sh.guard_id in people else None, "gate": gates.get(sh.gate_id),
                "started_at": sh.started_at, "ended_at": sh.ended_at, "end_reason": sh.end_reason,
                "handed_to": people[sh.handed_to].name if sh.handed_to in people else None, "handover": sh.handover,
                "selfie": "available" if sh.selfie_ref else "deleted" if sh.selfie_deleted_at else "pending" if sh.selfie_taken else "none",
            }
            for sh in rows
        ]


@router.get("/shifts/{shift_id}/selfie")
def view_selfie(shift_id: UUID, staff: Staff = Depends(selfie_viewer)) -> Response:
    """The shift-start selfie, for checking who held the phone after a dispute. Every view is
    written to the audit log."""
    with db.session(staff.estate_id) as s:
        sh = _get(s, Shift, shift_id, "shift")
        if not sh.selfie_ref:
            raise HTTPException(404, "no selfie for this shift (none taken, not uploaded yet, or past 30 days)")
        data = storage.get_decrypted(sh.selfie_ref)
        if data is None:
            raise HTTPException(404, "selfie missing from storage")
        audit.record(s, staff.estate_id, staff.actor, "view_selfie", sh)
    return Response(data, media_type="image/jpeg", headers={"Cache-Control": "no-store"})


@router.get("/photos/{photo_id}")
def view_photo(photo_id: UUID, staff: Staff = Depends(selfie_viewer)) -> Response:
    """A visitor or plate photo from the gate. Admin and CSO only; every view is audited."""
    with db.session(staff.estate_id) as s:
        p = _get(s, GatePhoto, photo_id, "photo")
        if not p.ref:
            raise HTTPException(404, "this photo was deleted after 30 days")
        data = storage.get_decrypted(p.ref)
        if data is None:
            raise HTTPException(404, "photo missing from storage")
        audit.record(s, staff.estate_id, staff.actor, "view_photo", p)
    return Response(data, media_type="image/jpeg", headers={"Cache-Control": "no-store"})


@router.get("/clips/{clip_id}")
def play_clip(clip_id: UUID, staff: Staff = Depends(selfie_viewer)) -> Response:
    """A visitor's name as the guard said it. Admin and CSO only; every play is audited."""
    with db.session(staff.estate_id) as s:
        c = _get(s, VoiceClip, clip_id, "clip")
        if not c.ref:
            raise HTTPException(404, "this clip was deleted after 7 days")
        data = storage.get_decrypted(c.ref)
        if data is None:
            raise HTTPException(404, "clip missing from storage")
        audit.record(s, staff.estate_id, staff.actor, "play_clip", c)
    return Response(data, media_type=c.content_type, headers={"Cache-Control": "no-store"})


class EntryNameIn(BaseModel):
    guest_name: str = Field(min_length=1, max_length=120)


@router.patch("/entries/{entry_id}")
def name_entry(entry_id: UUID, body: EntryNameIn, bg: BackgroundTasks, staff: Staff = Depends(selfie_viewer)) -> dict:
    """Type the name the guard said into the clip (or correct one). Audited; the visit the
    entry belongs to takes the name too."""
    with db.session(staff.estate_id) as s:
        e = _get(s, Entry, entry_id, "entry")
        before = audit.snapshot(e)
        e.guest_name = body.guest_name.strip()
        if e.visit_id:
            v = s.get(Visit, e.visit_id)
            if v is not None and v.name_clip_id is not None:
                v.guest_name = e.guest_name
        audit.record(s, staff.estate_id, staff.actor, "name_entry", e, before)
        out = {"id": e.id, "guest_name": e.guest_name}
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


def _device_out(d: Device) -> dict:
    status_ = "revoked" if d.revoked_at else "paired" if d.paired_at else "awaiting pairing"
    return {"id": d.id, "label": d.label, "gate_id": d.gate_id, "status": status_, "paired_at": d.paired_at,
            "last_sync_at": d.last_sync_at, "revoked_at": d.revoked_at}


def _issue_pairing(d: Device) -> str:
    code = new_pairing_code()
    d.pairing_code_hash, d.pairing_expires_at = sha256(code), clock.now() + PAIRING_TTL
    return f"{code[:4]}-{code[4:]}"


@router.get("/devices")
def list_devices(staff: Staff = Depends(reader)) -> list[dict]:
    with db.session(staff.estate_id) as s:
        return [_device_out(d) for d in s.scalars(select(Device).order_by(Device.created_at))]


@router.post("/devices", status_code=201)
def create_device(body: DeviceIn, staff: Staff = Depends(admin)) -> dict:
    """Register a gate phone. The pairing code is shown once and works for 24 hours."""
    with db.session(staff.estate_id) as s:
        _get(s, Gate, body.gate_id, "gate")
        d = Device(estate_id=staff.estate_id, gate_id=body.gate_id, label=body.label.strip())
        code = _issue_pairing(d)
        _created(s, staff, d, "device")
        return _device_out(d) | {"pairing_code": code}


@router.post("/devices/{device_id}/pairing-code")
def new_pairing_code_for(device_id: UUID, staff: Staff = Depends(admin)) -> dict:
    """Re-pair a phone (factory reset, new SIM). The old token stops working when the new
    code is used. A revoked phone cannot be re-paired: register a new device."""
    with db.session(staff.estate_id) as s:
        d = _get(s, Device, device_id, "device")
        if d.revoked_at:
            raise HTTPException(409, "This phone was revoked. Register it as a new device.")
        code = _issue_pairing(d)
        audit.record(s, staff.estate_id, staff.actor, "new_pairing_code", d)
        return _device_out(d) | {"pairing_code": code}


@router.post("/devices/{device_id}/revoke")
def revoke_device(device_id: UUID, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    """A lost or stolen gate phone. Its token stops working at once, and the estate moves to a
    new code key, so every code issued from now on is one the lost phone cannot verify or
    forge. Codes already issued keep working until their window closes."""
    with db.session(staff.estate_id) as s:
        d = _get(s, Device, device_id, "device")
        if d.revoked_at:
            return _device_out(d)
        before = audit.snapshot(d)
        d.revoked_at, d.token_hash, d.fcm_token = clock.now(), None, None
        audit.record(s, staff.estate_id, staff.actor, "revoke", d, before)
        estate = s.get(Estate, staff.estate_id, with_for_update=True)
        before = audit.snapshot(estate)
        estate.hmac_key_version = keys.next_version(estate.id, estate.hmac_key_version)
        audit.record(s, staff.estate_id, staff.actor, "rotate_key", estate, before)
        out = _device_out(d)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


# --- directory (estate tier) ---------------------------------------------------------------


def dialable(v: str | None) -> str | None:
    """Directory numbers are dialled as stored: short codes (112) and local numbers allowed."""
    if v is None:
        return None
    v = v.strip().replace(" ", "").replace("-", "")
    if not v.lstrip("+").isdigit() or not 3 <= len(v) <= 16:
        raise ValueError("digits only, for example 08031234567 or 112")
    return v


class DirectoryIn(BaseModel):
    category: Literal["estate", "crime", "fire", "medical", "utilities"]
    name: str = Field(min_length=2, max_length=120)
    number: str
    rank: int = Field(default=100, ge=1, le=1000)

    _number = field_validator("number")(dialable)


class DirectoryPatch(BaseModel):
    category: Literal["estate", "crime", "fire", "medical", "utilities"] | None = None
    name: str | None = Field(default=None, min_length=2, max_length=120)
    number: str | None = None
    rank: int | None = Field(default=None, ge=1, le=1000)
    active: bool | None = None

    _number = field_validator("number")(dialable)


class VerifyIn(BaseModel):
    note: str | None = Field(default=None, max_length=280)  # who answered


def _dir_out(e: DirectoryEntry) -> dict:
    return {
        "id": e.id, "scope": e.scope, "category": e.category, "name": e.name, "number": e.number, "rank": e.rank,
        "verified_at": e.verified_at, "verified_by": e.verified_by, "verification_note": e.verification_note,
        "reported_not_working": e.reported_not_working_at is not None, "overdue": directory.overdue(e),
        "editable": e.scope == "estate", "active": e.active,
    }


@router.get("/directory")
def list_directory(staff: Staff = Depends(reader)) -> list[dict]:
    """The merged list as the estate sees it: its own numbers plus the state and LGA tier."""
    with db.session(staff.estate_id) as s:
        return [_dir_out(e) for e in directory.entries(s)]


@router.post("/directory", status_code=201)
def create_directory_entry(body: DirectoryIn, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        e = _created(s, staff, DirectoryEntry(scope="estate", estate_id=staff.estate_id, **body.model_dump()), "number")
        out = _dir_out(e)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


def _estate_entry(s: Session, staff: Staff, entry_id: UUID) -> DirectoryEntry:
    e = _get(s, DirectoryEntry, entry_id, "number")
    if e.scope != "estate":
        raise HTTPException(403, "State and national numbers are maintained by Gatelog. Use 'This number didn't work' to report one.")
    return e


@router.patch("/directory/{entry_id}")
def update_directory_entry(entry_id: UUID, body: DirectoryPatch, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        e = _estate_entry(s, staff, entry_id)
        _changed(s, staff, e, body, "number")
        out = _dir_out(e)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.post("/directory/{entry_id}/verify")
def verify_directory_entry(entry_id: UUID, body: VerifyIn, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    """The admin dialled it and someone answered."""
    with db.session(staff.estate_id) as s:
        e = _estate_entry(s, staff, entry_id)
        before = audit.snapshot(e)
        directory.mark_verified(s, e, staff.actor, body.note)
        audit.record(s, staff.estate_id, staff.actor, "verify", e, before)
        out = _dir_out(e)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out


@router.post("/directory/{entry_id}/report", status_code=202)
def report_directory_entry(entry_id: UUID, staff: Staff = Depends(reader)) -> dict:
    try:
        return {"flagged": directory.report(staff.estate_id, entry_id, staff.actor)}
    except LookupError:
        raise HTTPException(404, "no such number")


@router.delete("/directory/{entry_id}", status_code=204)
def delete_directory_entry(entry_id: UUID, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> None:
    with db.session(staff.estate_id) as s:
        _deleted(s, staff, _estate_entry(s, staff, entry_id), "number")
    bg.add_task(push.estate_changed, staff.estate_id)


# --- gate log ------------------------------------------------------------------------------


@router.get("/entries")
def list_entries(
    since: datetime | None = None, until: datetime | None = None, method: str | None = None, gate_id: UUID | None = None,
    plate: str | None = None, limit: int = 200, staff: Staff = Depends(reader),
) -> list[dict]:
    with db.session(staff.estate_id) as s:
        stmt = select(Entry).order_by(Entry.at.desc()).limit(min(limit, 1000))
        if since:
            stmt = stmt.where(Entry.at >= since)
        if until:
            stmt = stmt.where(Entry.at < until)
        if method:  # one method, or several separated by commas
            methods = [m for m in method.split(",") if m]
            if any(m not in ENTRY_METHODS for m in methods):
                raise HTTPException(422, f"method must be among {', '.join(ENTRY_METHODS)}")
            stmt = stmt.where(Entry.method.in_(methods))
        if gate_id:
            stmt = stmt.where(Entry.gate_id == gate_id)
        if plate:
            stmt = stmt.where(Entry.plate.contains(normalise_plate(plate)))
        rows = s.scalars(stmt).all()
        homes = {h.id: h.address for h in s.scalars(select(Home).where(Home.id.in_({e.home_id for e in rows})))}
        gates = {g.id: g.name for g in s.scalars(select(Gate))}
        guards = {g.id: g.name for g in s.scalars(select(Guard))}
        exits = {x.entry_id: x for x in s.scalars(select(Exit).where(Exit.entry_id.in_([e.id for e in rows])))}
        return [
            {
                "id": e.id, "at": e.at, "guest_name": e.guest_name, "address": homes.get(e.home_id), "method": e.method,
                "gate": gates.get(e.gate_id), "guard": guards.get(e.guard_id), "note": e.note, "plate": e.plate,
                "decided_by": guards.get(e.decided_by), "reason": e.reason, "shift_id": e.shift_id,
                "trust": e.trust, "caller": e.caller_masked, "disputed_at": e.disputed_at, "name_clip_id": e.name_clip_id,
                "visitor_photo_id": e.visitor_photo_id, "plate_photo_id": e.plate_photo_id, "photo_skipped": e.photo_skipped,
                # The CSO admitted on their own decision while also being the one on the gate: the
                # home's "Not you?" text was the only other pair of eyes.
                "decided_alone": e.decided_by is not None and e.decided_by == e.guard_id,
                "exit_at": exits[e.id].at if e.id in exits else None, "exit_method": exits[e.id].method if e.id in exits else None,
            }
            for e in rows
        ]


@router.get("/exits/unmatched")
def unmatched_exits(staff: Staff = Depends(reader)) -> list[dict]:
    """Exits with no entry: the guest came in before Gatelog, or the entry was missed."""
    with db.session(staff.estate_id) as s:
        rows = s.scalars(select(Exit).where(Exit.unmatched.is_(True)).order_by(Exit.at.desc()).limit(200)).all()
        return [{"id": x.id, "at": x.at, "guest_name": x.guest_name, "method": x.method, "visit_id": x.visit_id} for x in rows]


@router.get("/visits")
def list_visits(state: str | None = None, staff: Staff = Depends(reader)) -> list[dict]:
    with db.session(staff.estate_id) as s:
        stmt = select(Visit).order_by(Visit.created_at.desc()).limit(200)
        if state:
            stmt = stmt.where(Visit.state == state)
        return [
            {"id": v.id, "guest_name": v.guest_name, "address": v.home.address, "source": v.source, "state": v.state,
             "window_start": v.window_start, "window_end": v.window_end, "expected_until": v.expected_until, "stay_type": v.stay_type}
            for v in s.scalars(stmt)
        ]
