"""The gate phone's API: pair, pull state, push the offline queue.

Offline contract. The phone verifies codes with no network using the estate key(s) and the
expected visits from its last state pull. Everything it records (entries, exits, callbacks,
phone-announced visits, rollup checks) carries a client-generated UUID and is queued
locally, then pushed here when the network returns. Inserts are ON CONFLICT DO NOTHING on
that UUID, and side effects (notices to residents, visit state changes) run only for rows
that were actually new, so a phone that retries a batch five times notifies once.

Items that can never be accepted (a home from another estate, an unknown method) come back
in `rejected` with a reason, so one bad record cannot block the queue behind it.

Shifts. A guard, the CSO or a shuttle rider opens a shift on the phone with their PIN
(checked on the phone against the hash in the state) and a selfie. The shift, and every
record made during it, carries the shift's id. The selfie is uploaded separately, when there
is data for it.

Shuttle. Where the estate runs one, the state carries the open rides, the motorcycles, the
estate places, card hashes and house-code hashes. Rides booked on a phone, what happens to
them (ride events) and newly issued cards come back through the same sync. A rider phone also
reports its position while the rider's shift is open (POST /positions), outside the queue.
"""

import base64
import hashlib
import json
from datetime import datetime, timedelta
from typing import Literal
from datetime import time as dtime
from uuid import UUID, uuid5

from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import select, text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from .. import abuse, clock, db, directory, messaging, push, shifts, shuttle, storage, trust, visits
from .. import stay as stay_mod
from ..auth import DeviceAuth, current_device, new_device_token, sha256
from ..estate_settings import EstateSettings
from ..keys import key_store
from ..models import (
    RIDE_OPEN_STATES,
    Callback,
    Device,
    PinCheck,
    Place,
    Position,
    ResidentCard,
    Ride,
    RideEvent,
    Shift,
    Shuttle,
    Vehicle,
    Entry,
    Estate,
    Exit,
    Gate,
    Guard,
    Home,
    PhoneNumber,
    Resident,
    Rollup,
    RollupItem,
    Visit,
)
from ..phones import decrypt
from ..plates import normalise_plate

router = APIRouter(prefix="/v1/device", tags=["gate device"])

FUTURE_SKEW = timedelta(minutes=5)
WALK_UP_NS = UUID("6f1d7c2e-3b4a-4f5e-9a8b-0c1d2e3f4a5b")  # namespace for visits made from flow B entries
WALK_UP_METHODS = ("callback_confirmed", "pin_confirmed", "phone_announced", "walk_in_admitted")  # entries that get a visit when sent without one
# A caller's number as the phone may send it: never more than 4 leading and 4 trailing digits.
CALLER_MASK = r"^\+?\d{0,4}[•*]{2,4}\d{4}$"


# --- pairing -------------------------------------------------------------------------------


class PairIn(BaseModel):
    code: str = Field(min_length=6, max_length=16)
    fcm_token: str | None = None


class PairOut(BaseModel):
    token: str
    device_id: UUID
    estate_id: UUID
    estate_name: str
    gate_name: str


@router.post("/pair", response_model=PairOut)
def pair(body: PairIn, request: Request) -> PairOut:
    if not abuse.allow(abuse.PAIR_PER_IP, request.client.host if request.client else "unknown"):
        raise HTTPException(429, "Too many pairing attempts. Try again in an hour.")
    code_hash = sha256(body.code.strip().upper().replace("-", "").replace(" ", ""))
    with db.session() as s:
        row = s.execute(text("SELECT device_id, estate_id, expires_at FROM gatelog_find_pairing(:h)"), {"h": code_hash}).first()
        if row is None or row.expires_at is None or row.expires_at <= clock.now():
            raise HTTPException(400, "That pairing code is wrong or has expired. Ask the estate admin for a new one.")
        db.rescope(s, row.estate_id)
        d = s.get(Device, row.device_id)
        token = new_device_token(d.id, d.estate_id)
        d.token_hash, d.paired_at = sha256(token), clock.now()
        d.pairing_code_hash, d.pairing_expires_at = None, None
        d.fcm_token = body.fcm_token
        estate, gate = s.get(Estate, d.estate_id), s.get(Gate, d.gate_id)
        return PairOut(token=token, device_id=d.id, estate_id=d.estate_id, estate_name=estate.name, gate_name=gate.name)


class FcmIn(BaseModel):
    fcm_token: str


@router.put("/fcm-token", status_code=204)
def set_fcm_token(body: FcmIn, dev: DeviceAuth = Depends(current_device)) -> None:
    with db.session(dev.estate_id) as s:
        s.get(Device, dev.id).fcm_token = body.fcm_token


# --- state ---------------------------------------------------------------------------------


def _iso(dt: datetime | None) -> str | None:
    return dt.isoformat() if dt else None


def build_state(s: Session, dev: DeviceAuth) -> dict:
    now = clock.now()
    estate = s.get(Estate, dev.estate_id)
    st = EstateSettings.model_validate(estate.settings)

    visible = s.scalars(
        select(Visit).where(
            Visit.state.in_(("expected", "inside", "overstay")),
            # Expected visits whose window closed more than 12h ago are of no use to the gate.
            (Visit.state != "expected") | (Visit.window_end > now - timedelta(hours=12)),
        )
    ).all()
    versions = {estate.hmac_key_version} | {v.key_version for v in visible if v.key_version}
    store = key_store()
    keys = [{"version": ver, "key_b64": base64.b64encode(store.get(estate.id, ver)).decode()} for ver in sorted(versions)]

    residents_by_home: dict[UUID, list[dict]] = {}
    numbers_by_resident: dict[UUID, list[dict]] = {}
    for n in s.scalars(select(PhoneNumber).where(PhoneNumber.resident_id.is_not(None))):
        # The gate dials these for callbacks, possibly with no data connection, so the phone
        # holds them, in its encrypted store. Nothing else outside the database ever does.
        numbers_by_resident.setdefault(n.resident_id, []).append({"id": str(n.id), "e164": decrypt(n.e164_enc), "last4": n.last4, "is_primary": n.is_primary})
    plates_by_home: dict[UUID, list[dict]] = {}
    for veh in s.scalars(select(Vehicle)):
        plates_by_home.setdefault(veh.home_id, []).append({"plate": veh.plate, "description": veh.description})
    callback_homes: set[UUID] = set()
    for r in s.scalars(select(Resident).where(Resident.active.is_(True))):
        residents_by_home.setdefault(r.home_id, []).append(
            {"id": str(r.id), "name": r.name, "contact_pref": r.contact_pref, "numbers": numbers_by_resident.get(r.id, [])}
        )
        if r.callback_required:
            callback_homes.add(r.home_id)

    with_shuttle = st.shuttle_enabled
    homes = [
        {
            "id": str(h.id), "label": h.label, "street": h.street.name, "zone": h.street.zone.name, "address": h.address,
            "callback_required": h.id in callback_homes, "residents": residents_by_home.get(h.id, []),
            "vehicles": plates_by_home.get(h.id, []),
            "lat": h.lat, "lng": h.lng,
            # The home PIN, checked offline at the gate (phone announcements) and by a shuttle
            # rider, like a guard PIN. Null until the household asks for it or the admin sets it.
            "house_code_hash": h.house_code_hash,
        }
        for h in s.scalars(select(Home))
    ]
    latest_entry = {
        e.visit_id: e for e in s.scalars(select(Entry).where(Entry.visit_id.in_([v.id for v in visible]), Entry.method != "refused").order_by(Entry.at))
    }
    rollup = s.scalars(select(Rollup).where(Rollup.handover_at.is_(None)).order_by(Rollup.for_date.desc())).first()
    return {
        "server_time": now.isoformat(),
        "estate": {
            "id": str(estate.id), "name": estate.name, "timezone": estate.timezone,
            "walk_in_policy": st.walk_in_policy, "key_version": estate.hmac_key_version,
        },
        "device": {"id": str(dev.id), "gate_id": str(dev.gate_id)},
        "keys": keys,
        "gates": [{"id": str(g.id), "name": g.name, "lat": g.lat, "lng": g.lng} for g in s.scalars(select(Gate))],
        # PIN hashes travel to every gate phone so a PIN works offline at any gate. A guard with
        # no hash sets their PIN at their next shift; one without consent cannot start a shift.
        "guards": [
            {"id": str(g.id), "name": g.name, "role": g.role, "pin_hash": g.pin_hash,
             "pin_reset_at": _iso(g.pin_reset_at), "consent": g.consent_at is not None}
            for g in s.scalars(select(Guard).where(Guard.active.is_(True)).order_by(Guard.name))
        ],
        "homes": homes,
        "visits": [
            {
                "id": str(v.id), "home_id": str(v.home_id), "resident_id": str(v.resident_id) if v.resident_id else None,
                "guest_name": v.guest_name, "window_start": int(v.window_start.timestamp()), "window_end": int(v.window_end.timestamp()),
                "key_version": v.key_version, "code_issued": v.code_issued, "source": v.source, "state": v.state,
                "expected_until": _iso(v.expected_until),
                "entry_id": str(latest_entry[v.id].id) if v.id in latest_entry else None,
                "entered_at": _iso(latest_entry[v.id].at) if v.id in latest_entry else None,
            }
            for v in visible
        ],
        "rollup": None if rollup is None else {
            "id": str(rollup.id), "for_date": rollup.for_date.isoformat(),
            "items": [
                {"id": str(i.id), "visit_id": str(i.visit_id), "guest_name": v.guest_name, "home_id": str(v.home_id), "address": v.home.address,
                 "expected_until": _iso(v.expected_until), "checked_at": _iso(i.checked_at), "check_result": i.check_result}
                for i, v in s.execute(select(RollupItem, Visit).join(Visit, Visit.id == RollupItem.visit_id).where(RollupItem.rollup_id == rollup.id)).all()
            ],
        },
        "directory": [
            {
                "id": str(e.id), "category": e.category, "name": e.name, "number": e.number,
                "verified_at": _iso(e.verified_at), "reported_not_working": e.reported_not_working_at is not None,
            }
            for e in directory.entries(s)
        ],
        "shuttle": shuttle_state(s, now) if with_shuttle else None,
    }


def ride_json(r: Ride, s: Session, names: dict[UUID, str]) -> dict:
    def end(kind: str, ref: UUID | None, label: str) -> dict:
        pt = shuttle.point(s, kind, ref)
        return {"kind": kind, "ref": str(ref) if ref else None, "label": label, "lat": pt[0] if pt else None, "lng": pt[1] if pt else None}

    return {
        "id": str(r.id), "kind": r.kind, "source": r.source, "state": r.state, "home_id": str(r.home_id),
        "resident_id": str(r.resident_id) if r.resident_id else None, "passenger": r.passenger,
        "pickup": end(r.pickup_kind, r.pickup_ref, r.pickup_label), "dropoff": end(r.dropoff_kind, r.dropoff_ref, r.dropoff_label),
        "wanted_at": _iso(r.wanted_at), "note": r.note, "rider_id": str(r.rider_id) if r.rider_id else None,
        "rider": names.get(r.rider_id) if r.rider_id else None, "shuttle_id": str(r.shuttle_id) if r.shuttle_id else None,
        "accepted_at": _iso(r.accepted_at), "picked_up_at": _iso(r.picked_up_at), "created_at": _iso(r.created_at),
    }


def shuttle_state(s: Session, now: datetime) -> dict:
    names = {g.id: g.name for g in s.scalars(select(Guard))}
    rides = s.scalars(
        select(Ride).where(Ride.state.in_(RIDE_OPEN_STATES), Ride.wanted_at <= now + timedelta(hours=24)).order_by(Ride.wanted_at)
    ).all()
    return {
        "shuttles": [{"id": str(v.id), "label": v.label, "plate": v.plate} for v in s.scalars(select(Shuttle).where(Shuttle.active.is_(True)).order_by(Shuttle.label))],
        "places": [{"id": str(p.id), "name": p.name, "kind": p.kind, "lat": p.lat, "lng": p.lng} for p in s.scalars(select(Place).order_by(Place.name))],
        # A card's hash is matched on the phone with no network: tap, hash the UID, look it up.
        "cards": [
            {"id": str(c.id), "uid_hash": c.uid_hash, "resident_id": str(c.resident_id), "home_id": str(c.home_id), "uid_last4": c.uid_last4}
            for c in s.scalars(select(ResidentCard).where(ResidentCard.revoked_at.is_(None)))
        ],
        "rides": [ride_json(r, s, names) for r in rides],
    }


@router.get("/state")
def state(response: Response, dev: DeviceAuth = Depends(current_device), if_none_match: str | None = Header(default=None)):
    with db.session(dev.estate_id) as s:
        payload = build_state(s, dev)
        s.get(Device, dev.id).last_sync_at = clock.now()
    etag = '"' + hashlib.sha256(json.dumps({k: v for k, v in payload.items() if k != "server_time"}, sort_keys=True).encode()).hexdigest()[:32] + '"'
    if if_none_match == etag:
        return Response(status_code=304, headers={"ETag": etag})
    response.headers["ETag"] = etag
    return payload


# --- sync ----------------------------------------------------------------------------------


class VisitIn(BaseModel):
    """A visit the guard created from a phone announcement (callback flow A)."""

    id: UUID
    home_id: UUID
    resident_id: UUID | None = None
    guest_name: str = Field(min_length=1, max_length=120)
    window_start: datetime
    window_end: datetime
    expected_until: datetime
    stay_type: Literal["hour", "hours", "overnight", "multi_day"]
    stay_minutes: int | None = None
    stay_given: bool = True
    # verified: confirmed on a callback; pin_verified: the caller gave the home PIN.
    trust: Literal["verified", "pin_verified"] = "verified"


class CallbackIn(BaseModel):
    id: UUID
    home_id: UUID
    number_id: UUID
    outcome: Literal["confirmed", "declined", "no_answer"]
    visit_id: UUID | None = None
    guard_id: UUID | None = None
    shift_id: UUID | None = None
    at: datetime


class EntryIn(BaseModel):
    id: UUID
    home_id: UUID
    guest_name: str = Field(min_length=1, max_length=120)
    method: Literal["code", "phone_announced", "callback_confirmed", "pin_confirmed", "walk_in_admitted", "refused"]
    visit_id: UUID | None = None
    guard_id: UUID | None = None
    shift_id: UUID | None = None
    gate_id: UUID | None = None
    plate: str | None = Field(default=None, max_length=20)
    # Walk-ins: who decided (a guard or the CSO) and the reason they gave.
    decided_by: UUID | None = None
    reason: str | None = Field(default=None, max_length=280)
    note: str | None = Field(default=None, max_length=280)
    caller_masked: str | None = Field(default=None, pattern=CALLER_MASK)  # the announcing call, if the phone saw it
    at: datetime


class PinCheckIn(BaseModel):
    """A home PIN checked on the phone, right or wrong. The PIN itself never leaves the phone."""

    id: UUID
    home_id: UUID
    ok: bool
    context: Literal["gate", "shuttle"] = "gate"
    caller_masked: str | None = Field(default=None, pattern=CALLER_MASK)
    guard_id: UUID | None = None
    shift_id: UUID | None = None
    at: datetime


class ExitIn(BaseModel):
    id: UUID
    method: Literal["code", "list_tap"]
    entry_id: UUID | None = None
    visit_id: UUID | None = None
    guest_name: str | None = Field(default=None, max_length=120)
    guard_id: UUID | None = None
    shift_id: UUID | None = None
    gate_id: UUID | None = None
    plate: str | None = Field(default=None, max_length=20)
    at: datetime


class ShiftIn(BaseModel):
    """Sent when the shift opens, and again when it ends (the server fills in the end)."""

    id: UUID
    guard_id: UUID
    started_at: datetime
    selfie_taken: bool = False
    shuttle_id: UUID | None = None  # rider shifts: which motorcycle
    ended_at: datetime | None = None
    end_reason: Literal["handover", "ended", "auto"] | None = None
    handed_to: UUID | None = None
    handover: dict | None = None


class PinIn(BaseModel):
    """A guard set (or reset) their PIN on this phone. Only the hash leaves the phone."""

    guard_id: UUID
    pin_hash: str = Field(max_length=200)
    set_at: datetime


class RollupCheckIn(BaseModel):
    item_id: UUID
    result: Literal["left", "still_inside"]
    guard_id: UUID | None = None
    at: datetime


class StopIn(BaseModel):
    kind: Literal["home", "gate", "place"]
    ref: UUID


class RideIn(BaseModel):
    """A ride booked on a phone: by the guard at the gate, by a rider flagged down, or by the CSO."""

    id: UUID
    kind: Literal["resident", "delivery", "guest"]
    source: Literal["gate", "flag", "dispatch"]
    home_id: UUID
    resident_id: UUID | None = None
    passenger: str | None = Field(default=None, max_length=120)
    pickup: StopIn
    dropoff: StopIn
    wanted_at: datetime | None = None
    note: str | None = Field(default=None, max_length=200)
    guard_id: UUID | None = None
    shift_id: UUID | None = None
    at: datetime


class RideEventIn(BaseModel):
    id: UUID
    ride_id: UUID
    event: Literal["accept", "release", "pick_up", "drop_off", "cancel", "no_show"]
    guard_id: UUID | None = None
    shift_id: UUID | None = None
    # Who rode, at pickup (or at drop-off for a parcel).
    confirmed_by: Literal["card", "house_code", "guard", "rider"] | None = None
    resident_id: UUID | None = None
    card_id: UUID | None = None
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)
    at: datetime


class CardIn(BaseModel):
    """An estate card issued on a phone in the CSO view: tapped, then given to a resident."""

    id: UUID
    resident_id: UUID
    uid_hash: str = Field(pattern=r"^[0-9a-f]{64}$")
    uid_last4: str = Field(pattern=r"^[0-9A-F]{4}$")
    guard_id: UUID
    shift_id: UUID | None = None
    at: datetime


class SyncIn(BaseModel):
    pin_checks: list[PinCheckIn] = []
    cards: list[CardIn] = []
    rides: list[RideIn] = []
    ride_events: list[RideEventIn] = []
    visits: list[VisitIn] = []
    callbacks: list[CallbackIn] = []
    entries: list[EntryIn] = []
    exits: list[ExitIn] = []
    rollup_checks: list[RollupCheckIn] = []
    shifts: list[ShiftIn] = []
    pins: list[PinIn] = []


class Rejected(BaseModel):
    id: UUID
    reason: str


class SyncOut(BaseModel):
    accepted: list[UUID] = []
    duplicates: list[UUID] = []
    rejected: list[Rejected] = []


class _Sync:
    def __init__(self, s: Session, dev: DeviceAuth) -> None:
        self.s, self.dev = s, dev
        self.estate = s.get(Estate, dev.estate_id)
        self.out = SyncOut()
        self.changed = False
        self.now = clock.now()

    def _at(self, at: datetime) -> datetime:
        # A gate phone's clock can be wrong. Never accept the future.
        return min(at, self.now) if at - self.now > FUTURE_SKEW else at

    def _insert(self, model, values: dict) -> bool:
        res = self.s.execute(insert(model).values(**values).on_conflict_do_nothing(index_elements=["id"]).returning(model.id))
        new = res.first() is not None
        (self.out.accepted if new else self.out.duplicates).append(values["id"])
        return new

    def _reject(self, id_: UUID, reason: str) -> None:
        self.out.rejected.append(Rejected(id=id_, reason=reason))

    def _ours(self, model, id_: UUID | None) -> bool:
        # Foreign keys are checked without RLS, so a home from another estate would pass them.
        # s.get goes through RLS and returns None for anything outside this estate.
        return id_ is None or self.s.get(model, id_) is not None

    def visit(self, v: VisitIn) -> None:
        if not self._ours(Home, v.home_id) or not self._ours(Resident, v.resident_id):
            return self._reject(v.id, "unknown home or resident")
        if v.resident_id and self.s.get(Resident, v.resident_id).home_id != v.home_id:
            return self._reject(v.id, "resident is not in that home")
        if self._insert(Visit, dict(
            id=v.id, estate_id=self.estate.id, home_id=v.home_id, resident_id=v.resident_id, guest_name=v.guest_name.strip(),
            window_start=v.window_start, window_end=v.window_end, source="phone_announced", code_issued=False,
            expected_until=v.expected_until, stay_type=v.stay_type, stay_minutes=v.stay_minutes, stay_given=v.stay_given, state="expected",
            trust=v.trust,
        )):
            self.changed = True

    def callback(self, c: CallbackIn) -> None:
        number = self.s.get(PhoneNumber, c.number_id)
        if number is None or number.home_id != c.home_id:
            return self._reject(c.id, "number is not registered to that home")
        if not self._ours(Guard, c.guard_id) or not self._ours(Visit, c.visit_id) or not self._ours(Shift, c.shift_id):
            return self._reject(c.id, "unknown guard, visit or shift")
        if not self._insert(Callback, dict(
            id=c.id, estate_id=self.estate.id, visit_id=c.visit_id, home_id=c.home_id, guard_id=c.guard_id, shift_id=c.shift_id, device_id=self.dev.id,
            number_id=number.id, number_last4=number.last4, outcome=c.outcome, at=self._at(c.at),
        )) and c.visit_id:
            # The phone records a confirmed call at once, then sends it again with the visit
            # once the guard picks "expect them". Link it once; never move an existing link.
            existing = self.s.get(Callback, c.id)
            if existing.visit_id is None and existing.outcome == "confirmed":
                existing.visit_id = c.visit_id

    def entry(self, e: EntryIn) -> None:
        if not self._ours(Home, e.home_id) or not self._ours(Guard, e.guard_id) or not self._ours(Gate, e.gate_id):
            return self._reject(e.id, "unknown home, guard or gate")
        if not self._ours(Shift, e.shift_id) or not self._ours(Guard, e.decided_by):
            return self._reject(e.id, "unknown shift or decider")
        if e.method == "walk_in_admitted" and (not e.decided_by or not (e.reason or "").strip()):
            return self._reject(e.id, "a walk-in needs who decided and the reason")
        visit = self.s.get(Visit, e.visit_id) if e.visit_id else None
        if e.visit_id and (visit is None or visit.home_id != e.home_id):
            return self._reject(e.id, "visit does not match home")
        if e.method == "code" and (visit is None or not visit.code_issued):
            return self._reject(e.id, "code entries need a coded visit")
        visit_id = e.visit_id
        if visit_id is None and e.method in WALK_UP_METHODS and not self._seen(Entry, e.id):
            visit_id = self._visit_for_walk_up(e)
        level = trust.entry_trust(e.method, self.s.get(Visit, visit_id) if visit_id else None)
        row = dict(
            id=e.id, estate_id=self.estate.id, visit_id=visit_id, home_id=e.home_id, guest_name=e.guest_name.strip(),
            guard_id=e.guard_id, shift_id=e.shift_id, device_id=self.dev.id, gate_id=e.gate_id or self.dev.gate_id, method=e.method,
            plate=normalise_plate(e.plate), decided_by=e.decided_by, reason=(e.reason or "").strip() or None, note=e.note, at=self._at(e.at),
            trust=level, caller_masked=e.caller_masked,
        )
        if self._insert(Entry, row):
            entry = self.s.get(Entry, e.id)
            visits.on_entry(self.s, self.estate, entry)
            if level == "unverified":
                trust.alert_unverified(self.s, self.estate, entry)
            self.changed = True

    def _seen(self, model, id_: UUID) -> bool:
        return self.s.get(model, id_) is not None

    def _visit_for_walk_up(self, e: EntryIn) -> UUID:
        """A guest with no code let in after a callback (flow B), or on the CSO's decision,
        arrives with no visit. Without one they would be invisible to the other gates' Inside
        lists, to overstay nudges and to the night list. Make one, with the estate's default
        stay. The ID is derived from the entry's, so a retried batch makes the same visit, once."""
        at = self._at(e.at)
        local = at.astimezone(visits.tz(self.estate))
        st = EstateSettings.model_validate(self.estate.settings)
        s = stay_mod.default_stay(local, st.default_stay_until)
        # Whoever confirmed on the phone is the resident to notify. A walk-in had no one
        # confirm, so it has no resident: it is on the lists and the night list, not messaged.
        cb = None if e.method == "walk_in_admitted" else self.s.scalars(
            select(Callback).where(Callback.home_id == e.home_id, Callback.outcome == "confirmed",
                                   Callback.at > at - timedelta(hours=2), Callback.at <= at + FUTURE_SKEW)
            .order_by(Callback.at.desc())
        ).first()
        resident_id = None
        if cb and cb.number_id:
            number = self.s.get(PhoneNumber, cb.number_id)
            resident_id = number.resident_id if number else None
        vid = uuid5(WALK_UP_NS, str(e.id))
        end_of_day = stay_mod.at(local.date(), dtime(23, 59), local.tzinfo)
        self.s.execute(insert(Visit).values(
            id=vid, estate_id=self.estate.id, home_id=e.home_id, resident_id=resident_id, guest_name=e.guest_name.strip(),
            window_start=at, window_end=max(end_of_day, at + timedelta(hours=1)), source="phone_announced", code_issued=False,
            expected_until=s.until, stay_type=s.type, stay_minutes=None, stay_given=False, state="expected",
            trust=trust.BY_METHOD[e.method],
        ).on_conflict_do_nothing(index_elements=["id"]))
        if cb and cb.visit_id is None:
            cb.visit_id = vid
        return vid

    def exit(self, x: ExitIn) -> None:
        if not self._ours(Entry, x.entry_id) or not self._ours(Visit, x.visit_id) or not self._ours(Guard, x.guard_id) or not self._ours(Gate, x.gate_id):
            return self._reject(x.id, "unknown entry, visit, guard or gate")
        if not self._ours(Shift, x.shift_id):
            return self._reject(x.id, "unknown shift")
        if self._insert(Exit, dict(
            id=x.id, estate_id=self.estate.id, entry_id=x.entry_id, visit_id=x.visit_id, guard_id=x.guard_id, shift_id=x.shift_id,
            device_id=self.dev.id, gate_id=x.gate_id or self.dev.gate_id, method=x.method, guest_name=x.guest_name,
            plate=normalise_plate(x.plate), at=self._at(x.at),
        )):
            visits.on_exit(self.s, self.estate, self.s.get(Exit, x.id))
            self.changed = True

    def shift(self, sh: ShiftIn) -> None:
        guard = self.s.get(Guard, sh.guard_id)
        if guard is None or not self._ours(Guard, sh.handed_to):
            return self._reject(sh.id, "unknown guard")
        existing = self.s.get(Shift, sh.id)
        if existing is not None and existing.device_id != self.dev.id:
            return self._reject(sh.id, "that shift belongs to another phone")
        if sh.shuttle_id and (guard.role != "rider" or not self._ours(Shuttle, sh.shuttle_id)):
            return self._reject(sh.id, "only a rider's shift has a shuttle, and it must be this estate's")
        if existing is None:
            self.s.add(Shift(
                id=sh.id, estate_id=self.estate.id, guard_id=guard.id, device_id=self.dev.id, gate_id=self.dev.gate_id,
                started_at=self._at(sh.started_at), selfie_taken=sh.selfie_taken, shuttle_id=sh.shuttle_id,
            ))
            self.s.flush()
            existing = self.s.get(Shift, sh.id)
            self.out.accepted.append(sh.id)
        else:
            self.out.duplicates.append(sh.id)
        # The end arrives later than the start, often in a separate batch. Fill it in once.
        if sh.ended_at and existing.ended_at is None:
            existing.ended_at = max(self._at(sh.ended_at), existing.started_at)
            existing.end_reason = sh.end_reason or "ended"
            existing.handed_to, existing.handover = sh.handed_to, sh.handover
            if guard.role == "rider":
                shuttle.release_rider(self.s, guard.id)
            self.changed = True
        existing.selfie_taken = existing.selfie_taken or sh.selfie_taken

    def pin(self, p: PinIn) -> None:
        guard = self.s.get(Guard, p.guard_id)
        if guard is None:
            return self._reject(p.guard_id, "unknown guard")
        if not shifts.valid_pin_hash(p.pin_hash):
            return self._reject(p.guard_id, "PIN hash is not in the expected format")
        set_at = self._at(p.set_at)
        if guard.pin_reset_at and set_at <= guard.pin_reset_at:
            return self._reject(p.guard_id, "the admin reset this PIN after it was set; set it again")
        if guard.pin_set_at and set_at <= guard.pin_set_at:
            self.out.duplicates.append(p.guard_id)
            return
        guard.pin_hash, guard.pin_set_at = p.pin_hash, set_at
        self.out.accepted.append(p.guard_id)
        self.changed = True

    def rollup_check(self, c: RollupCheckIn) -> None:
        item = self.s.get(RollupItem, c.item_id)
        if item is None or not self._ours(Guard, c.guard_id):
            return self._reject(c.item_id, "unknown rollup item or guard")
        if item.checked_at is not None:
            self.out.duplicates.append(c.item_id)
            return
        item.checked_at, item.checked_by, item.check_result = self._at(c.at), c.guard_id, c.result
        v = self.s.get(Visit, item.visit_id)
        if c.result == "left" and v.state in visits.OPEN_STATES:
            entry = self.s.scalars(select(Entry).where(Entry.visit_id == v.id, Entry.method != "refused").order_by(Entry.at.desc())).first()
            self.s.add(Exit(estate_id=self.estate.id, entry_id=entry.id if entry else None, visit_id=v.id, guard_id=c.guard_id,
                            device_id=self.dev.id, method="list_tap", unmatched=entry is None, at=self._at(c.at)))
            v.state, v.closed_at = "left", self._at(c.at)
            self.changed = True
        self.out.accepted.append(c.item_id)


    def pin_check(self, c: PinCheckIn) -> None:
        if self._seen(PinCheck, c.id):
            self.out.duplicates.append(c.id)
            return
        if not self._ours(Home, c.home_id) or not self._ours(Guard, c.guard_id) or not self._ours(Shift, c.shift_id):
            return self._reject(c.id, "unknown home, guard or shift")
        check = PinCheck(id=c.id, estate_id=self.estate.id, home_id=c.home_id, ok=c.ok, context=c.context, caller_masked=c.caller_masked,
                         guard_id=c.guard_id, shift_id=c.shift_id, device_id=self.dev.id, at=self._at(c.at))
        self.s.add(check)
        self.s.flush()
        if not c.ok:
            trust.alert_wrong_pin(self.s, self.estate, check)
        self.out.accepted.append(c.id)

    # --- the shuttle -------------------------------------------------------------------------

    def card(self, c: CardIn) -> None:
        issuer = self.s.get(Guard, c.guard_id)
        resident = self.s.get(Resident, c.resident_id)
        if issuer is None or issuer.role != "cso":
            return self._reject(c.id, "only the CSO issues estate cards")
        if resident is None or not resident.active:
            return self._reject(c.id, "unknown resident")
        if self._seen(ResidentCard, c.id):
            self.out.duplicates.append(c.id)
            return
        taken = self.s.scalars(select(ResidentCard).where(ResidentCard.uid_hash == c.uid_hash, ResidentCard.revoked_at.is_(None))).first()
        if taken is not None:
            owner = self.s.get(Resident, taken.resident_id)
            return self._reject(c.id, f"this card is already {owner.name if owner else 'issued'}'s; revoke it in the dashboard first")
        self.s.add(ResidentCard(
            id=c.id, estate_id=self.estate.id, resident_id=resident.id, home_id=resident.home_id, uid_hash=c.uid_hash,
            uid_last4=c.uid_last4, issued_at=self._at(c.at), issued_by=issuer.id,
        ))
        self.s.flush()
        self.out.accepted.append(c.id)
        self.changed = True

    def ride(self, r: RideIn) -> None:
        if self._seen(Ride, r.id):
            self.out.duplicates.append(r.id)
            return
        if not self._ours(Guard, r.guard_id) or not self._ours(Shift, r.shift_id) or not self._ours(Resident, r.resident_id):
            return self._reject(r.id, "unknown guard, shift or resident")
        home = self.s.get(Home, r.home_id)
        if home is None:
            return self._reject(r.id, "unknown home")
        try:
            pickup, dropoff = shuttle.stop(self.s, r.pickup.kind, r.pickup.ref), shuttle.stop(self.s, r.dropoff.kind, r.dropoff.ref)
            shuttle.book(
                self.s, self.estate, ride_id=r.id, kind=r.kind, source=r.source, home=home,
                resident=self.s.get(Resident, r.resident_id) if r.resident_id else None, passenger=r.passenger,
                pickup=pickup, dropoff=dropoff, wanted_at=self._at(r.wanted_at or r.at), note=r.note,
                booked_by=r.guard_id, shift_id=r.shift_id,
            )
        except shuttle.RideError as e:
            return self._reject(r.id, str(e))
        self.out.accepted.append(r.id)
        self.changed = True

    def ride_event(self, ev: RideEventIn) -> None:
        if self._seen(RideEvent, ev.id):
            self.out.duplicates.append(ev.id)
            return
        ride = self.s.get(Ride, ev.ride_id)
        guard = self.s.get(Guard, ev.guard_id) if ev.guard_id else None
        shift = self.s.get(Shift, ev.shift_id) if ev.shift_id else None
        if ride is None or (ev.guard_id and guard is None) or (ev.shift_id and shift is None):
            return self._reject(ev.id, "unknown ride, guard or shift")
        if ev.event in ("accept", "release", "no_show") and (guard is None or guard.role != "rider"):
            return self._reject(ev.id, "only a rider takes, hands back or closes a ride as a no-show")
        if ev.card_id and not self._ours(ResidentCard, ev.card_id):
            return self._reject(ev.id, "unknown card")
        at = self._at(ev.at)
        outcome = shuttle.apply(self.s, self.estate, ride, ev.event, at, guard, shift,
                                confirmed_by=ev.confirmed_by, resident_id=ev.resident_id, card_id=ev.card_id)
        # Recorded either way: the trail shows the second rider who tapped "take it" too.
        self.s.add(RideEvent(id=ev.id, estate_id=self.estate.id, ride_id=ride.id, event=ev.event, guard_id=ev.guard_id,
                             shift_id=ev.shift_id, device_id=self.dev.id, applied=outcome.applied, at=at, lat=ev.lat, lng=ev.lng))
        self.s.flush()
        if outcome.applied:
            self.out.accepted.append(ev.id)
            self.changed = True
        else:
            self._reject(ev.id, outcome.reason or "not applied")


@router.post("/sync", response_model=SyncOut)
def sync(body: SyncIn, bg: BackgroundTasks, dev: DeviceAuth = Depends(current_device)) -> SyncOut:
    with db.session(dev.estate_id) as s:
        run = _Sync(s, dev)
        # Order matters: PINs and shifts before the records made during them, visits before
        # the callbacks and entries that point at them, entries before the exits that close them.
        for p in body.pins:
            run.pin(p)
        for sh in sorted(body.shifts, key=lambda sh: sh.started_at):
            run.shift(sh)
        for pc in body.pin_checks:
            run.pin_check(pc)
        for c in body.cards:
            run.card(c)
        for r in body.rides:
            run.ride(r)
        for ev in sorted(body.ride_events, key=lambda ev: ev.at):
            run.ride_event(ev)
        for v in body.visits:
            run.visit(v)
        for c in body.callbacks:
            run.callback(c)
        for e in sorted(body.entries, key=lambda e: e.at):
            run.entry(e)
        for x in sorted(body.exits, key=lambda x: x.at):
            run.exit(x)
        for r in body.rollup_checks:
            run.rollup_check(r)
        s.get(Device, dev.id).last_sync_at = clock.now()
    bg.add_task(messaging.dispatch)
    if run.changed:
        bg.add_task(push.estate_changed, dev.estate_id)
    return run.out


@router.put("/shifts/{shift_id}/selfie", status_code=204)
async def upload_selfie(shift_id: UUID, request: Request, dev: DeviceAuth = Depends(current_device)) -> None:
    """The shift-start selfie, as a JPEG body. Uploaded after the shift itself has synced.
    Stored encrypted; only the estate admin and the CSO can view it, and each view is audited."""
    data = await request.body()
    if len(data) > shifts.MAX_SELFIE_BYTES:
        raise HTTPException(413, "selfie larger than 400 KB; send a smaller JPEG")
    if not shifts.is_jpeg(data):
        raise HTTPException(415, "send a JPEG")
    with db.session(dev.estate_id) as s:
        sh = s.get(Shift, shift_id)
        if sh is None or sh.device_id != dev.id:
            raise HTTPException(404, "no such shift on this phone")
        if sh.selfie_deleted_at is not None or sh.selfie_ref is not None:
            return  # already stored, or already past its 30 days
        key = shifts.selfie_key(dev.estate_id, shift_id)
        storage.put_encrypted(key, data)
        sh.selfie_ref, sh.selfie_taken = key, True


class PointIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0, le=10_000)
    heading: float | None = Field(default=None, ge=0, le=360)
    speed: float | None = Field(default=None, ge=0, le=100)
    at: datetime


class PositionsIn(BaseModel):
    shift_id: UUID
    points: list[PointIn] = Field(max_length=200)


@router.post("/positions")
def positions(body: PositionsIn, dev: DeviceAuth = Depends(current_device)) -> dict:
    """Where a rider phone is, every 15 seconds while the rider's shift is open, in batches when
    the network was down. Never accepted outside an open rider shift on this phone."""
    now = clock.now()
    with db.session(dev.estate_id) as s:
        sh = s.get(Shift, body.shift_id)
        if sh is None or sh.device_id != dev.id or sh.ended_at is not None:
            raise HTTPException(409, "no open shift with that id on this phone")
        if s.get(Guard, sh.guard_id).role != "rider":
            raise HTTPException(403, "positions are recorded for shuttle riders only")
        kept = [
            Position(estate_id=dev.estate_id, shift_id=sh.id, guard_id=sh.guard_id, shuttle_id=sh.shuttle_id, lat=pt.lat, lng=pt.lng,
                     accuracy_m=pt.accuracy_m, heading=pt.heading, speed=pt.speed, at=min(pt.at, now))
            for pt in body.points
            if sh.started_at - FUTURE_SKEW <= pt.at <= now + FUTURE_SKEW and pt.at > now - shuttle.POSITION_KEEP
        ]
        s.add_all(kept)
        s.get(Device, dev.id).last_sync_at = now
    return {"stored": len(kept)}


def _cso_shift(s: Session, dev: DeviceAuth, shift_id: str | None) -> Shift:
    try:
        sh = s.get(Shift, UUID(shift_id)) if shift_id else None
    except ValueError:
        sh = None
    if sh is None or sh.device_id != dev.id or sh.ended_at is not None:
        raise HTTPException(403, "open a CSO shift on this phone first")
    if s.get(Guard, sh.guard_id).role != "cso":
        raise HTTPException(403, "the CSO view is for the CSO")
    return sh


@router.get("/cso")
def cso_overview(dev: DeviceAuth = Depends(current_device), x_shift_id: str | None = Header(default=None)) -> dict:
    """What needs the CSO, who is on duty where, and today's shifts. Live, estate-wide: the
    phone shows when it last fetched this and keeps the last copy when offline. Expected and
    inside lists come from the normal state pull."""
    with db.session(dev.estate_id) as s:
        _cso_shift(s, dev, x_shift_id)
        estate = s.get(Estate, dev.estate_id)
        now = clock.now()
        tz = visits.tz(estate)
        day_start = now.astimezone(tz).replace(hour=0, minute=0, second=0, microsecond=0)
        gates = {g.id: g.name for g in s.scalars(select(Gate))}
        people = {g.id: g for g in s.scalars(select(Guard))}

        overdue = s.scalars(select(Visit).where(Visit.state.in_(visits.OPEN_STATES), Visit.expected_until < now).order_by(Visit.expected_until)).all()
        today = s.scalars(select(Entry).where(Entry.at >= day_start).order_by(Entry.at.desc())).all()
        refused = [e for e in today if e.method == "refused"]
        walk_ins = [e for e in today if e.method == "walk_in_admitted"]
        homes = {h.id: h.address for h in s.scalars(select(Home).where(Home.id.in_({v.home_id for v in overdue} | {e.home_id for e in today})))}
        devices = s.scalars(select(Device).where(Device.revoked_at.is_(None), Device.paired_at.is_not(None))).all()
        open_shifts = s.scalars(select(Shift).where(Shift.ended_at.is_(None)).order_by(Shift.started_at)).all()
        shifts_today = s.scalars(select(Shift).where((Shift.started_at >= day_start) | (Shift.ended_at >= day_start)).order_by(Shift.started_at)).all()
        rollup = s.scalars(select(Rollup).where(Rollup.handover_at.is_(None)).order_by(Rollup.for_date.desc())).first()
        unchecked = 0
        if rollup:
            unchecked = len(s.scalars(select(RollupItem.id).where(RollupItem.rollup_id == rollup.id, RollupItem.checked_at.is_(None))).all())

        def who(guard_id):
            g = people.get(guard_id)
            return g.name if g else None

        quiet = [d for d in devices if d.last_sync_at is None or now - d.last_sync_at > timedelta(minutes=30)]
        on_duty_by_device = {sh.device_id: sh for sh in open_shifts}
        return {
            "server_time": now.isoformat(),
            "needs": {
                "overdue": [
                    {"visit_id": str(v.id), "guest_name": v.guest_name, "home_id": str(v.home_id), "address": homes.get(v.home_id),
                     "expected_until": _iso(v.expected_until), "resident_id": str(v.resident_id) if v.resident_id else None}
                    for v in overdue
                ],
                "refused_today": [
                    {"entry_id": str(e.id), "guest_name": e.guest_name, "address": homes.get(e.home_id), "gate": gates.get(e.gate_id),
                     "by": who(e.guard_id), "reason": e.reason or e.note, "at": _iso(e.at)}
                    for e in refused
                ],
                "walk_ins_today": [
                    {"entry_id": str(e.id), "guest_name": e.guest_name, "address": homes.get(e.home_id), "gate": gates.get(e.gate_id),
                     "decided_by": who(e.decided_by), "reason": e.reason, "at": _iso(e.at)}
                    for e in walk_ins
                ],
                "quiet_phones": [
                    {"device_id": str(d.id), "gate": gates.get(d.gate_id), "label": d.label, "last_sync_at": _iso(d.last_sync_at),
                     "on_duty": who(on_duty_by_device[d.id].guard_id) if d.id in on_duty_by_device else None}
                    for d in quiet
                ],
                "night_list_unchecked": unchecked,
                # The home said NO to "Not you?": a stranger may be inside on a description.
                "disputed_today": [
                    {"entry_id": str(e.id), "guest_name": e.guest_name, "address": homes.get(e.home_id), "gate": gates.get(e.gate_id),
                     "decided_by": who(e.decided_by), "at": _iso(e.at), "disputed_at": _iso(e.disputed_at)}
                    for e in today if e.disputed_at is not None
                ],
                # Shuttle rides nobody has taken 10 minutes after they were wanted.
                "rides_waiting": [
                    {"ride_id": str(r.id), "kind": r.kind, "from": r.pickup_label, "to": r.dropoff_label, "wanted_at": _iso(r.wanted_at)}
                    for r in s.scalars(select(Ride).where(Ride.state == "requested", Ride.wanted_at < now - timedelta(minutes=10)).order_by(Ride.wanted_at))
                ],
            },
            "on_duty": [
                {"gate": gates.get(sh.gate_id), "guard": who(sh.guard_id), "role": people[sh.guard_id].role if sh.guard_id in people else None,
                 "since": _iso(sh.started_at), "phone_last_sync_at": _iso(next((d.last_sync_at for d in devices if d.id == sh.device_id), None))}
                for sh in open_shifts
            ],
            "shifts_today": [
                {"id": str(sh.id), "gate": gates.get(sh.gate_id), "guard": who(sh.guard_id), "started_at": _iso(sh.started_at),
                 "ended_at": _iso(sh.ended_at), "end_reason": sh.end_reason, "handed_to": who(sh.handed_to),
                 "handover": sh.handover, "selfie": sh.selfie_ref is not None}
                for sh in shifts_today
            ],
        }


class ReportIn(BaseModel):
    entry_id: UUID
    guard_id: UUID | None = None


@router.post("/directory/report", status_code=202)
def report_number(body: ReportIn, dev: DeviceAuth = Depends(current_device)) -> dict:
    try:
        flagged = directory.report(dev.estate_id, body.entry_id, f"guard:{body.guard_id}" if body.guard_id else dev.actor)
    except LookupError:
        raise HTTPException(404, "no such number")
    return {"flagged": flagged}
