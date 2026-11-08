"""Gatelog ops (PI Technologies): provision estates, curate the state and LGA tier of the
emergency directory. A state-level number goes live only after ops has dialled it and
recorded who answered; numbers are never seeded from memory or a web list."""

from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy import select

from .. import db, directory, keys, messaging
from ..auth import Staff, require_ops
from ..estate_settings import EstateSettings
from ..models import AuditEvent, DirectoryEntry, Estate, Gate, MessageLog, Organisation, StaffUser
from .admin import _dir_out, dialable

router = APIRouter(prefix="/v1/ops", tags=["gatelog ops"])


class EstateIn(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    state: str = Field(min_length=2, max_length=60)
    lga: str = Field(min_length=2, max_length=80)
    timezone: str = "Africa/Lagos"
    admin_email: EmailStr
    admin_name: str = Field(min_length=2, max_length=120)
    gate_name: str = "Main Gate"


@router.get("/estates")
def list_estates(staff: Staff = Depends(require_ops)) -> list[dict]:
    with db.session(ops=True) as s:
        return [{"id": e.id, "name": e.name, "state": e.state, "lga": e.lga} for e in s.scalars(select(Estate).order_by(Estate.name))]


@router.post("/estates", status_code=201)
def create_estate(body: EstateIn, staff: Staff = Depends(require_ops)) -> dict:
    with db.session(ops=True) as s:
        if s.scalars(select(StaffUser).where(StaffUser.email == body.admin_email.lower())).first():
            raise HTTPException(409, "a staff member with that email already exists")
        e = Estate(name=body.name.strip(), state=body.state.strip(), lga=body.lga.strip(), timezone=body.timezone,
                   settings=EstateSettings().model_dump(mode="json"))
        s.add(e)
        s.flush()
        e.hmac_key_version = keys.next_version(e.id, 0)
        s.add(Gate(estate_id=e.id, name=body.gate_name))
        s.add(StaffUser(estate_id=e.id, email=body.admin_email.lower(), name=body.admin_name.strip(), role="admin"))
        s.add(AuditEvent(estate_id=e.id, actor=staff.actor, entity="estates", entity_id=str(e.id), action="create",
                         after={"name": e.name, "state": e.state, "lga": e.lga}))
        return {"id": e.id, "name": e.name}


class StateNumberIn(BaseModel):
    scope: Literal["state", "lga"]
    state: str = Field(min_length=2, max_length=60)
    lga: str | None = Field(default=None, max_length=80)
    category: Literal["crime", "fire", "medical", "utilities"]
    name: str = Field(min_length=2, max_length=120)
    number: str
    rank: int = Field(default=100, ge=1, le=1000)

    _number = field_validator("number")(dialable)


class TestCallIn(BaseModel):
    answered_by: str = Field(min_length=2, max_length=280)  # who answered, and what they said


@router.get("/directory")
def list_state_numbers(state: str | None = None, staff: Staff = Depends(require_ops)) -> list[dict]:
    with db.session(ops=True) as s:
        stmt = select(DirectoryEntry).where(DirectoryEntry.scope != "estate").order_by(DirectoryEntry.state, DirectoryEntry.lga, DirectoryEntry.rank)
        if state:
            stmt = stmt.where(DirectoryEntry.state == state)
        return [_dir_out(e) | {"state": e.state, "lga": e.lga} for e in s.scalars(stmt)]


@router.post("/directory", status_code=201)
def create_state_number(body: StateNumberIn, staff: Staff = Depends(require_ops)) -> dict:
    """Added inactive. It goes live only when a test call is recorded."""
    if body.scope == "lga" and not body.lga:
        raise HTTPException(422, "an LGA number needs the LGA")
    with db.session(ops=True) as s:
        e = DirectoryEntry(**body.model_dump(), active=False)
        s.add(e)
        s.flush()
        return _dir_out(e) | {"state": e.state, "lga": e.lga}


@router.post("/directory/{entry_id}/test-call")
def record_test_call(entry_id: UUID, body: TestCallIn, staff: Staff = Depends(require_ops)) -> dict:
    """Ops dialled the number and someone answered. Verifies it and puts it live."""
    with db.session(ops=True) as s:
        e = s.get(DirectoryEntry, entry_id)
        if e is None or e.scope == "estate":
            raise HTTPException(404, "no such state or LGA number")
        directory.mark_verified(s, e, staff.actor, body.answered_by)
        e.active = True
        return _dir_out(e) | {"state": e.state, "lga": e.lga}


@router.post("/directory/{entry_id}/withdraw")
def withdraw_state_number(entry_id: UUID, staff: Staff = Depends(require_ops)) -> dict:
    with db.session(ops=True) as s:
        e = s.get(DirectoryEntry, entry_id)
        if e is None or e.scope == "estate":
            raise HTTPException(404, "no such state or LGA number")
        e.active = False
        return _dir_out(e) | {"state": e.state, "lga": e.lga}


# --- held messages -------------------------------------------------------------------------


@router.get("/messages/held")
def held_messages(staff: Staff = Depends(require_ops)) -> list[dict]:
    """Messages held by the abuse limits (estate SMS budget, per-number cap). Bodies are kept
    until a person releases or drops them; numbers show as last four digits."""
    with db.session(ops=True) as s:
        rows = s.scalars(select(MessageLog).where(MessageLog.status == "held").order_by(MessageLog.created_at).limit(500)).all()
        names = {e.id: e.name for e in s.scalars(select(Estate))}
        return [{"id": m.id, "estate": names.get(m.estate_id), "to": f"***{m.to_last4}", "channel": m.channel, "kind": m.kind,
                 "created_at": m.created_at} for m in rows]


class HeldAction(BaseModel):
    ids: list[UUID] = Field(min_length=1, max_length=500)
    action: Literal["release", "drop"]


@router.post("/messages/held")
def act_on_held(body: HeldAction, staff: Staff = Depends(require_ops)) -> dict:
    """Release sends them now, bypassing the limit that held them. Drop discards them."""
    with db.session(ops=True) as s:
        rows = s.scalars(select(MessageLog).where(MessageLog.id.in_(body.ids), MessageLog.status == "held")).all()
        for m in rows:
            if body.action == "release":
                m.status, m.attempts = "queued", 1  # attempts > 0 skips the limit check once released
            else:
                m.status, m.body, m.params = "failed", None, None
    if body.action == "release":
        messaging.dispatch()
    return {"updated": len(rows)}


# --- contract terms ------------------------------------------------------------------------


class ContractIn(BaseModel):
    """Set by Gatelog from the signed contract, not by the estate's own admin."""

    sms_allowance_per_home: int | None = Field(default=None, ge=0, le=1000)
    sms_overage_naira: float | None = Field(default=None, ge=0, le=1000)


@router.patch("/estates/{estate_id}/contract")
def set_contract(estate_id: UUID, body: ContractIn, staff: Staff = Depends(require_ops)) -> dict:
    with db.session(ops=True) as s:
        e = s.get(Estate, estate_id)
        if e is None:
            raise HTTPException(404, "no such estate")
        merged = EstateSettings.model_validate({**e.settings, **body.model_dump(exclude_unset=True)})
        e.settings = merged.model_dump(mode="json")
        s.add(AuditEvent(estate_id=e.id, actor=staff.actor, entity="estates", entity_id=str(e.id), action="contract",
                         after=body.model_dump(exclude_unset=True)))
        return {"sms_allowance_per_home": merged.sms_allowance_per_home, "sms_overage_naira": merged.sms_overage_naira}


# --- organisations (associations, facility-management companies) ---------------------------


class OrganisationIn(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    kind: Literal["association", "facility_manager"]


class OrgUserIn(BaseModel):
    email: EmailStr
    name: str = Field(min_length=2, max_length=120)
    role: Literal["org_admin", "org_viewer"] = "org_admin"


@router.get("/organisations")
def list_organisations(staff: Staff = Depends(require_ops)) -> list[dict]:
    with db.session(ops=True) as s:
        estates: dict = {}
        for e in s.scalars(select(Estate).where(Estate.organisation_id.is_not(None))):
            estates.setdefault(e.organisation_id, []).append({"id": e.id, "name": e.name})
        return [{"id": o.id, "name": o.name, "kind": o.kind, "estates": estates.get(o.id, [])}
                for o in s.scalars(select(Organisation).order_by(Organisation.name))]


@router.post("/organisations", status_code=201)
def create_organisation(body: OrganisationIn, staff: Staff = Depends(require_ops)) -> dict:
    with db.session(ops=True) as s:
        o = Organisation(name=body.name.strip(), kind=body.kind)
        s.add(o)
        s.flush()
        return {"id": o.id, "name": o.name, "kind": o.kind}


@router.put("/organisations/{org_id}/estates/{estate_id}", status_code=204)
def attach_estate(org_id: UUID, estate_id: UUID, staff: Staff = Depends(require_ops)) -> None:
    """Only with the estate Exco's approval (recorded outside Gatelog). Leaving keeps the
    estate's data with the estate."""
    with db.session(ops=True) as s:
        o, e = s.get(Organisation, org_id), s.get(Estate, estate_id)
        if o is None or e is None:
            raise HTTPException(404, "no such organisation or estate")
        e.organisation_id = o.id
        s.add(AuditEvent(estate_id=e.id, actor=staff.actor, entity="estates", entity_id=str(e.id), action="join_organisation", after={"organisation_id": str(o.id)}))


@router.delete("/organisations/{org_id}/estates/{estate_id}", status_code=204)
def detach_estate(org_id: UUID, estate_id: UUID, staff: Staff = Depends(require_ops)) -> None:
    with db.session(ops=True) as s:
        e = s.get(Estate, estate_id)
        if e is None or e.organisation_id != org_id:
            raise HTTPException(404, "that estate is not in this organisation")
        e.organisation_id = None
        s.add(AuditEvent(estate_id=e.id, actor=staff.actor, entity="estates", entity_id=str(e.id), action="leave_organisation", after={"organisation_id": None}))


@router.post("/organisations/{org_id}/users", status_code=201)
def create_org_user(org_id: UUID, body: OrgUserIn, staff: Staff = Depends(require_ops)) -> dict:
    with db.session(ops=True) as s:
        if s.get(Organisation, org_id) is None:
            raise HTTPException(404, "no such organisation")
        if s.scalars(select(StaffUser).where(StaffUser.email == body.email.lower())).first():
            raise HTTPException(409, "a staff member with that email already exists")
        u = StaffUser(organisation_id=org_id, email=body.email.lower(), name=body.name.strip(), role=body.role)
        s.add(u)
        s.flush()
        return {"id": u.id, "email": u.email, "role": u.role}
