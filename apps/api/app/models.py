"""Tables. Every tenant table carries estate_id and is guarded by Row-Level Security (see the
initial migration). Identity tables (staff_users, login_codes) are platform-level.

Enumerations are text with CHECK constraints rather than Postgres enum types, so adding a
value is a one-line migration.

Full phone numbers exist only in phone_numbers (encrypted). Every other table that needs to
mention a number stores its last four digits.
"""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def _check(column: str, values: tuple[str, ...], name: str) -> CheckConstraint:
    quoted = ", ".join(f"'{v}'" for v in values)
    return CheckConstraint(f"{column} IN ({quoted})", name=name)


CONTACT_PREFS = ("whatsapp", "sms", "call")
VISIT_SOURCES = ("whatsapp", "sms", "phone_announced", "ivr")
STAY_TYPES = ("hour", "hours", "overnight", "multi_day")
VISIT_STATES = ("expected", "inside", "left", "overstay", "rollup_closed", "cancelled")
CALLBACK_OUTCOMES = ("confirmed", "declined", "no_answer")
ENTRY_METHODS = ("code", "phone_announced", "callback_confirmed", "pin_confirmed", "walk_in_admitted", "refused")
# How well an admitted entry was verified (spec: call-the-gate, trust levels).
TRUST_LEVELS = ("verified", "pin_verified", "unverified")
PIN_CHECK_CONTEXTS = ("gate", "shuttle")
NUMBER_OFFER_STATES = ("asked", "added", "declined", "expired")
EXIT_METHODS = ("code", "list_tap", "resident_confirmed", "rollup_closed")
NUDGE_REPLIES = ("staying", "left", "none")
STAFF_ROLES = ("admin", "committee", "security_head", "treasurer", "org_admin", "org_viewer", "ops")
GUARD_ROLES = ("guard", "cso", "rider")
PLACE_KINDS = ("amenity", "pickup", "post")
RIDE_KINDS = ("resident", "delivery", "guest")
RIDE_SOURCES = ("whatsapp", "sms", "gate", "flag", "dispatch")
RIDE_STATES = ("requested", "accepted", "picked_up", "done", "cancelled", "no_show")
RIDE_OPEN_STATES = ("requested", "accepted", "picked_up")
RIDE_EVENTS = ("accept", "release", "pick_up", "drop_off", "cancel", "no_show")
STOP_KINDS = ("home", "gate", "place")
RIDE_CONFIRMATIONS = ("card", "house_code", "guard", "rider")
RESIDENT_RELATIONS = ("landlord", "occupant")
LEVY_PAYERS = ("landlord", "occupant")
ORG_KINDS = ("association", "facility_manager")
SHIFT_END_REASONS = ("handover", "ended", "auto")
DIRECTORY_SCOPES = ("estate", "state", "lga")
DIRECTORY_CATEGORIES = ("crime", "fire", "medical", "utilities", "estate")


class Base(DeclarativeBase):
    type_annotation_map = {uuid.UUID: UUID(as_uuid=True), dict: JSONB}


def pk() -> Mapped[uuid.UUID]:
    return mapped_column(primary_key=True, default=uuid.uuid4)


def created() -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), server_default=func.now())


def estate_fk() -> Mapped[uuid.UUID]:
    return mapped_column(ForeignKey("estates.id", ondelete="CASCADE"), index=True)


# --- Tenancy and the four-level address ------------------------------------------------


class Organisation(Base):
    """An umbrella residents' association, CDA or facility-management company above several
    estates. Platform-level (no RLS): its users act on one member estate at a time."""

    __tablename__ = "organisations"
    __table_args__ = (_check("kind", ORG_KINDS, "ck_org_kind"),)
    id: Mapped[uuid.UUID] = pk()
    name: Mapped[str] = mapped_column(String(160))
    kind: Mapped[str] = mapped_column(String(20))
    billing_settings: Mapped[dict] = mapped_column(default=dict)
    created_at: Mapped[datetime] = created()


class Estate(Base):
    __tablename__ = "estates"
    id: Mapped[uuid.UUID] = pk()
    organisation_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("organisations.id", ondelete="SET NULL"), index=True)
    name: Mapped[str] = mapped_column(String(160))
    # Names the estate in every message, since all estates share one WhatsApp number ("SKA Exco").
    short_name: Mapped[str | None] = mapped_column(String(40))
    state: Mapped[str] = mapped_column(String(60))
    lga: Mapped[str] = mapped_column(String(80))
    timezone: Mapped[str] = mapped_column(String(40), default="Africa/Lagos")
    # rollup_time, default_stay_until, handover_time, walk_in_policy: see settings.EstateSettings
    settings: Mapped[dict] = mapped_column(default=dict)
    sos_ladder: Mapped[dict | None] = mapped_column(default=None)  # Phase 2
    hmac_key_version: Mapped[int] = mapped_column(Integer, default=1)
    # The estate map: a GeoJSON polygon ring [[lng, lat], ...] drawn by the admin. The map is
    # locked to its bounding box. Unset until the admin draws it.
    boundary: Mapped[list | None] = mapped_column(JSONB, default=None)
    created_at: Mapped[datetime] = created()

    @property
    def bbox(self) -> tuple[float, float, float, float] | None:
        """(west, south, east, north), or None before a boundary is drawn."""
        if not self.boundary:
            return None
        lngs, lats = [p[0] for p in self.boundary], [p[1] for p in self.boundary]
        return min(lngs), min(lats), max(lngs), max(lats)

    @property
    def sender_name(self) -> str:
        return self.short_name or self.name


class Zone(Base):
    """Level 2: block or zone."""

    __tablename__ = "zones"
    __table_args__ = (UniqueConstraint("estate_id", "name"),)
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    name: Mapped[str] = mapped_column(String(80))


class Street(Base):
    """Level 3: street or court."""

    __tablename__ = "streets"
    __table_args__ = (UniqueConstraint("zone_id", "name"),)
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    zone_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("zones.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    zone: Mapped[Zone] = relationship(lazy="joined", innerjoin=True)


class Home(Base):
    """Level 4. A log line reads '14B Adeniyi Close, Block C'."""

    __tablename__ = "homes"
    __table_args__ = (UniqueConstraint("street_id", "label"), _check("levy_payer", LEVY_PAYERS, "ck_homes_levy_payer"))
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    street_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("streets.id", ondelete="CASCADE"), index=True)
    label: Mapped[str] = mapped_column(String(40))
    # The association decides who owes dues for a home, not Gatelog.
    levy_payer: Mapped[str] = mapped_column(String(10), default="occupant", server_default="occupant")
    # Shuttle house code: 4 digits the household knows. The phone checks the slow hash offline;
    # the code itself is kept encrypted only so Gatelog can send it to the household (HOUSE CODE).
    house_code_hash: Mapped[str | None] = mapped_column(String(200))
    house_code_enc: Mapped[bytes | None] = mapped_column(LargeBinary)
    house_code_set_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    lat: Mapped[float | None] = mapped_column(Float)
    lng: Mapped[float | None] = mapped_column(Float)
    street: Mapped[Street] = relationship(lazy="joined", innerjoin=True)

    @property
    def address(self) -> str:
        return f"{self.label} {self.street.name}, {self.street.zone.name}"


# --- People ------------------------------------------------------------------------------


class Resident(Base):
    __tablename__ = "residents"
    __table_args__ = (
        _check("contact_pref", CONTACT_PREFS, "ck_residents_contact_pref"),
        _check("relation", RESIDENT_RELATIONS, "ck_residents_relation"),
    )
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    home_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("homes.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(120))
    relation: Mapped[str] = mapped_column(String(10), default="occupant", server_default="occupant")
    contact_pref: Mapped[str] = mapped_column(String(10), default="whatsapp")
    callback_required: Mapped[bool] = mapped_column(Boolean, default=False)
    # None means the default: on for call and SMS residents, off for WhatsApp.
    exit_notices: Mapped[bool | None] = mapped_column(Boolean, default=None)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = created()
    home: Mapped[Home] = relationship(lazy="joined", innerjoin=True)

    @property
    def wants_exit_notices(self) -> bool:
        return self.exit_notices if self.exit_notices is not None else self.contact_pref in ("call", "sms")


class StaffUser(Base):
    """Dashboard and platform users. Platform-level (no RLS): login looks up by email before
    any estate is known. estate_id binds everyone except Gatelog ops."""

    __tablename__ = "staff_users"
    __table_args__ = (_check("role", STAFF_ROLES, "ck_staff_role"),)
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("estates.id", ondelete="CASCADE"), index=True)
    # Set for association users (org_admin, org_viewer), who have no single estate.
    organisation_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("organisations.id", ondelete="CASCADE"), index=True)
    email: Mapped[str] = mapped_column(String(254), unique=True)
    name: Mapped[str] = mapped_column(String(120))
    role: Mapped[str] = mapped_column(String(20))
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = created()


class PhoneNumber(Base):
    """The only table holding full numbers. Owned by a resident (max 3 per home) or a staff
    member (the security head, who receives the rollup by SMS)."""

    __tablename__ = "phone_numbers"
    __table_args__ = (
        CheckConstraint("(resident_id IS NULL) <> (staff_id IS NULL)", name="ck_phone_one_owner"),
        CheckConstraint("(resident_id IS NULL) = (home_id IS NULL)", name="ck_phone_home_with_resident"),
        Index("ix_phone_numbers_index", "e164_index"),
    )
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    home_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("homes.id", ondelete="CASCADE"), index=True)
    resident_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("residents.id", ondelete="CASCADE"))
    staff_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("staff_users.id", ondelete="CASCADE"))
    e164_enc: Mapped[bytes] = mapped_column(LargeBinary)
    e164_index: Mapped[str] = mapped_column(String(64))
    last4: Mapped[str] = mapped_column(String(4))
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False)
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Set while a number the gate offered to add waits for a YES from the home (48 hours). A
    # pending number is invisible: no inbound messages, no callbacks, not on the gate phone.
    pending_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created()


class Gate(Base):
    __tablename__ = "gates"
    __table_args__ = (UniqueConstraint("estate_id", "name"),)
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    name: Mapped[str] = mapped_column(String(80))
    lat: Mapped[float | None] = mapped_column(Float)
    lng: Mapped[float | None] = mapped_column(Float)


class Place(Base):
    """A named spot on the estate map that is not a gate or a home: the clubhouse, a mosque,
    the market. Shuttle rides can start or end at one."""

    __tablename__ = "places"
    __table_args__ = (UniqueConstraint("estate_id", "name"), _check("kind", PLACE_KINDS, "ck_places_kind"))
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    name: Mapped[str] = mapped_column(String(80))
    kind: Mapped[str] = mapped_column(String(10), default="amenity")
    lat: Mapped[float] = mapped_column(Float)
    lng: Mapped[float] = mapped_column(Float)


class Guard(Base):
    """Everyone who works a Gatelog phone: guards, the CSO and shuttle riders. Their PIN opens
    a shift; the role decides whether the phone shows the guard, CSO or rider view."""

    __tablename__ = "guards"
    __table_args__ = (_check("role", GUARD_ROLES, "ck_guards_role"),)
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    name: Mapped[str] = mapped_column(String(120))
    role: Mapped[str] = mapped_column(String(8), default="guard", server_default="guard")
    # Set by the guard on a gate phone at their first shift; the server never sees the PIN.
    # "pbkdf2-sha256$<iterations>$<salt b64>$<hash b64>", verified offline on the phone.
    pin_hash: Mapped[str | None] = mapped_column(String(200))
    pin_set_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    pin_reset_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Written consent to shift selfies (NDPA), recorded by the admin before the first shift.
    consent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = created()


class Shift(Base):
    """A guard's or the CSO's time on a gate phone, opened with PIN and selfie. Every action
    in between carries this shift's id. The selfie is an audit record only: never compared
    automatically, encrypted, deleted after 30 days."""

    __tablename__ = "shifts"
    __table_args__ = (
        CheckConstraint("end_reason IS NULL OR end_reason IN ('handover', 'ended', 'auto')", name="ck_shifts_end_reason"),
        Index("ix_shifts_open", "estate_id", "ended_at"),
    )
    id: Mapped[uuid.UUID] = pk()  # client-generated
    estate_id: Mapped[uuid.UUID] = estate_fk()
    guard_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("guards.id"), index=True)
    device_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("devices.id"))
    gate_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("gates.id"))
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    end_reason: Mapped[str | None] = mapped_column(String(10))
    handed_to: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("guards.id"))
    # What was handed over: who was inside, records not yet sent, night list items open.
    handover: Mapped[dict | None] = mapped_column()
    selfie_taken: Mapped[bool] = mapped_column(Boolean, default=False)  # the phone says it has one to send
    selfie_ref: Mapped[str | None] = mapped_column(String(200))  # storage key, set once uploaded
    selfie_deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    shuttle_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shuttles.id"))  # rider shifts: the motorcycle
    synced_at: Mapped[datetime] = created()


class Vehicle(Base):
    """A resident's registered vehicle, so the guard sees a match on the plate."""

    __tablename__ = "vehicles"
    __table_args__ = (UniqueConstraint("home_id", "plate"),)
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    home_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("homes.id", ondelete="CASCADE"), index=True)
    plate: Mapped[str] = mapped_column(String(16))  # stored as entered, upper-cased, spaces removed
    description: Mapped[str | None] = mapped_column(String(80))


class Device(Base):
    """An estate-owned gate phone. Paired once with a short code, then holds a long-lived
    token. Revoking it bumps the estate key version so the lost phone's key stops working
    for every visit issued afterwards."""

    __tablename__ = "devices"
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    gate_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("gates.id"))
    label: Mapped[str] = mapped_column(String(80))
    pairing_code_hash: Mapped[str | None] = mapped_column(String(64))
    pairing_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    token_hash: Mapped[str | None] = mapped_column(String(64), unique=True)
    paired_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_sync_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    fcm_token: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = created()


# --- Visits and the gate log -------------------------------------------------------------


class Visit(Base):
    """One announced guest. Two windows, kept apart on purpose: window_start/end is when the
    guest may enter (the code's validity), expected_until is when they should have left."""

    __tablename__ = "visits"
    __table_args__ = (
        _check("source", VISIT_SOURCES, "ck_visits_source"),
        _check("stay_type", STAY_TYPES, "ck_visits_stay_type"),
        _check("state", VISIT_STATES, "ck_visits_state"),
        Index("ix_visits_open", "estate_id", "state", "expected_until"),
    )
    # Client-generated when the guard creates it from a phone announcement offline.
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    home_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("homes.id"), index=True)
    resident_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("residents.id", ondelete="SET NULL"))
    guest_name: Mapped[str] = mapped_column(String(120))
    window_start: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    window_end: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    source: Mapped[str] = mapped_column(String(20))
    code_issued: Mapped[bool] = mapped_column(Boolean, default=False)
    key_version: Mapped[int | None] = mapped_column(Integer)
    expected_until: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    stay_type: Mapped[str] = mapped_column(String(10))
    # Set for relative stays ("for 2 hours"): expected_until is re-anchored to the entry time.
    stay_minutes: Mapped[int | None] = mapped_column(Integer)
    stay_given: Mapped[bool] = mapped_column(Boolean, default=True)  # False: estate default applied
    state: Mapped[str] = mapped_column(String(16), default="expected")
    # verified: by message from a registered number, or confirmed on a callback; pin_verified:
    # a caller from any number gave the home PIN; unverified: the CSO's decision on a description.
    trust: Mapped[str] = mapped_column(String(12), default="verified", server_default="verified")
    name_clip_id: Mapped[uuid.UUID | None] = mapped_column()  # a phone-made visit whose name was spoken
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created()
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    home: Mapped[Home] = relationship(lazy="joined", innerjoin=True)


class Callback(Base):
    """The guard rang the resident's registered number back. The trust anchor for phone
    announcements: an outbound call to a number on file cannot be spoofed."""

    __tablename__ = "callbacks"
    __table_args__ = (_check("outcome", CALLBACK_OUTCOMES, "ck_callbacks_outcome"),)
    id: Mapped[uuid.UUID] = pk()  # client-generated
    estate_id: Mapped[uuid.UUID] = estate_fk()
    visit_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("visits.id"))
    home_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("homes.id"))
    guard_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("guards.id"))
    shift_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shifts.id"))
    device_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("devices.id"))
    number_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("phone_numbers.id", ondelete="SET NULL"))
    number_last4: Mapped[str] = mapped_column(String(4))
    outcome: Mapped[str] = mapped_column(String(12))
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    synced_at: Mapped[datetime] = created()


class Entry(Base):
    __tablename__ = "entries"
    __table_args__ = (
        _check("method", ENTRY_METHODS, "ck_entries_method"),
        Index("ix_entries_estate_at", "estate_id", "at"),
    )
    id: Mapped[uuid.UUID] = pk()  # client-generated; the primary key makes sync idempotent
    estate_id: Mapped[uuid.UUID] = estate_fk()
    visit_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("visits.id"), index=True)
    home_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("homes.id"))
    guest_name: Mapped[str] = mapped_column(String(120))
    guard_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("guards.id"))
    shift_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shifts.id"), index=True)
    device_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("devices.id"))
    gate_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("gates.id"))
    method: Mapped[str] = mapped_column(String(20))
    plate: Mapped[str | None] = mapped_column(String(16), index=True)
    # Walk-ins: who on the gate made the call (a guard or the CSO), and the reason they gave.
    decided_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("guards.id"))
    reason: Mapped[str | None] = mapped_column(String(280))
    note: Mapped[str | None] = mapped_column(String(280))
    # Set by the server for every admitted entry; null for refusals.
    trust: Mapped[str | None] = mapped_column(String(12))
    # The number the announcing call came from, masked ("0803•••1234"), when the phone saw it.
    caller_masked: Mapped[str | None] = mapped_column(String(16))
    # The guard said the visitor's name instead of typing it: the clip (see VoiceClip). The
    # admin can type the name in later; guest_name says "Voice clip" until then.
    name_clip_id: Mapped[uuid.UUID | None] = mapped_column()
    # Photos taken at the gate (see GatePhoto): the visitor, and the plate it read.
    visitor_photo_id: Mapped[uuid.UUID | None] = mapped_column()
    plate_photo_id: Mapped[uuid.UUID | None] = mapped_column()
    # Why there is no visitor photo when the estate asks for one: no_camera or refused.
    photo_skipped: Mapped[str | None] = mapped_column(String(10))
    # The home replied NO to the "Not you?" message: who and when.
    disputed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    disputed_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("residents.id", ondelete="SET NULL"))
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    synced_at: Mapped[datetime] = created()


class Exit(Base):
    __tablename__ = "exits"
    __table_args__ = (
        _check("method", EXIT_METHODS, "ck_exits_method"),
        Index("ix_exits_estate_at", "estate_id", "at"),
    )
    id: Mapped[uuid.UUID] = pk()  # client-generated for gate exits
    estate_id: Mapped[uuid.UUID] = estate_fk()
    entry_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("entries.id"), index=True)
    visit_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("visits.id"), index=True)
    guard_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("guards.id"))
    shift_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shifts.id"))
    device_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("devices.id"))
    gate_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("gates.id"))
    method: Mapped[str] = mapped_column(String(20))
    plate: Mapped[str | None] = mapped_column(String(16))
    # An exit with no matching entry is still logged, and flagged for the admin.
    unmatched: Mapped[bool] = mapped_column(Boolean, default=False)
    guest_name: Mapped[str | None] = mapped_column(String(120))
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    synced_at: Mapped[datetime] = created()


class OverstayNudge(Base):
    __tablename__ = "overstay_nudges"
    __table_args__ = (
        _check("reply", NUDGE_REPLIES, "ck_nudges_reply"),
        UniqueConstraint("visit_id", "for_until"),
    )
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    visit_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("visits.id"), index=True)
    # A visit is nudged once per expected_until; extending it allows a fresh nudge.
    for_until: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    sent_at: Mapped[datetime] = created()
    reply: Mapped[str] = mapped_column(String(8), default="none")
    replied_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    new_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Rollup(Base):
    __tablename__ = "rollups"
    __table_args__ = (UniqueConstraint("estate_id", "for_date"),)
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    for_date: Mapped[date] = mapped_column(Date)  # the estate-local evening it covers
    run_at: Mapped[datetime] = created()
    open_count: Mapped[int] = mapped_column(Integer)
    closed_by_morning: Mapped[int | None] = mapped_column(Integer)
    handover_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class RollupItem(Base):
    __tablename__ = "rollup_items"
    __table_args__ = (UniqueConstraint("rollup_id", "visit_id"),)
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    rollup_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("rollups.id", ondelete="CASCADE"), index=True)
    visit_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("visits.id"))
    checked_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("guards.id"))
    checked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    check_result: Mapped[str | None] = mapped_column(String(16))  # left | still_inside


# --- Emergency directory -----------------------------------------------------------------


class DirectoryEntry(Base):
    """Estate tier (estate_id set, owned by the estate admin) or state/LGA tier (estate_id
    null, curated by Gatelog ops and readable by every estate in that state)."""

    __tablename__ = "directory_entries"
    __table_args__ = (
        _check("scope", DIRECTORY_SCOPES, "ck_directory_scope"),
        _check("category", DIRECTORY_CATEGORIES, "ck_directory_category"),
        CheckConstraint("(scope = 'estate') = (estate_id IS NOT NULL)", name="ck_directory_scope_estate"),
        CheckConstraint("scope <> 'lga' OR lga IS NOT NULL", name="ck_directory_lga"),
        # No state or LGA number goes live until Gatelog ops has dialled it.
        CheckConstraint("scope = 'estate' OR NOT active OR verified_at IS NOT NULL", name="ck_directory_verified_to_go_live"),
    )
    id: Mapped[uuid.UUID] = pk()
    scope: Mapped[str] = mapped_column(String(8))
    estate_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("estates.id", ondelete="CASCADE"), index=True)
    state: Mapped[str | None] = mapped_column(String(60))
    lga: Mapped[str | None] = mapped_column(String(80))
    category: Mapped[str] = mapped_column(String(12))
    name: Mapped[str] = mapped_column(String(120))
    # Public service and estate desk numbers, not personal numbers: stored in clear so a gate
    # phone can dial them offline. Short codes (112) are allowed, so this is not E.164.
    number: Mapped[str] = mapped_column(String(20))
    rank: Mapped[int] = mapped_column(Integer, default=100)  # lower shows first; top five go out on "NUMBERS"
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    verified_by: Mapped[str | None] = mapped_column(String(120))
    verification_note: Mapped[str | None] = mapped_column(String(280))  # who answered
    reported_not_working_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = created()


class DirectoryReport(Base):
    __tablename__ = "directory_reports"
    id: Mapped[uuid.UUID] = pk()
    entry_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("directory_entries.id", ondelete="CASCADE"), index=True)
    estate_id: Mapped[uuid.UUID] = estate_fk()  # the reporter's estate
    reporter: Mapped[str] = mapped_column(String(60))  # guard:<id> | resident:<id> | staff:<id>
    at: Mapped[datetime] = created()
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


# --- Messaging, imports, audit -----------------------------------------------------------


class Conversation(Base):
    """What Gatelog is waiting for from a resident (a stay length, a nudge reply), so a bare
    '2' can be read in context."""

    __tablename__ = "conversations"
    __table_args__ = (UniqueConstraint("estate_id", "resident_id"),)
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    resident_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("residents.id", ondelete="CASCADE"))
    awaiting: Mapped[str | None] = mapped_column(String(20))  # stay | stay_date | nudge | nudge_until | ride
    visit_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("visits.id", ondelete="SET NULL"))
    pending: Mapped[dict | None] = mapped_column(default=None)  # what a half-made request already said (a ride's time)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class MessageLog(Base):
    """Outbox and log for every message in or out. Outbound rows are written as `queued` in
    the same transaction as the change that caused them and sent after commit, so a rolled
    back visit never texts anyone a code. The body is cleared once sent; the number is a
    reference to phone_numbers, never a copy."""

    __tablename__ = "message_log"
    __table_args__ = (Index("ix_message_log_queued", "status", "created_at"),)
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    direction: Mapped[str] = mapped_column(String(3))  # in | out
    channel: Mapped[str] = mapped_column(String(10))  # sms | whatsapp
    number_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("phone_numbers.id", ondelete="SET NULL"))
    to_last4: Mapped[str] = mapped_column(String(4))
    kind: Mapped[str] = mapped_column(String(40))
    body: Mapped[str | None] = mapped_column(Text)
    params: Mapped[dict | None] = mapped_column()  # WhatsApp template parameters
    # queued | sent | failed | received | held (over the estate's daily SMS budget, or the
    # per-number cap: kept for ops to release or drop, never silently sent later)
    status: Mapped[str] = mapped_column(String(10), default="queued")
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    provider_id: Mapped[str | None] = mapped_column(String(120))
    created_at: Mapped[datetime] = created()
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class ImportBatch(Base):
    """A CSV or Excel register upload, staged for review before anything is written."""

    __tablename__ = "import_batches"
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    filename: Mapped[str] = mapped_column(String(200))
    uploaded_by: Mapped[uuid.UUID] = mapped_column(ForeignKey("staff_users.id"))
    status: Mapped[str] = mapped_column(String(12), default="staged")  # staged | committed | discarded
    # Parsed rows with per-row errors. Phone numbers inside are encrypted (see imports.py).
    rows: Mapped[dict] = mapped_column(default=dict)
    created_at: Mapped[datetime] = created()
    committed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AuditEvent(Base):
    """Append-only: the migration revokes UPDATE and DELETE on this table from the app role."""

    __tablename__ = "audit_events"
    __table_args__ = (Index("ix_audit_estate_at", "estate_id", "at"),)
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    actor: Mapped[str] = mapped_column(String(60))  # staff:<id> | device:<id> | system
    entity: Mapped[str] = mapped_column(String(40))
    entity_id: Mapped[str] = mapped_column(String(40))
    action: Mapped[str] = mapped_column(String(20))
    before: Mapped[dict | None] = mapped_column()
    after: Mapped[dict | None] = mapped_column()
    at: Mapped[datetime] = created()


class LoginCode(Base):
    """Emailed one-time sign-in codes for dashboard staff. Platform-level."""

    __tablename__ = "login_codes"
    id: Mapped[uuid.UUID] = pk()
    staff_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("staff_users.id", ondelete="CASCADE"), index=True)
    code_hash: Mapped[str] = mapped_column(String(64))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class RateCounter(Base):
    """Fixed-window counters for abuse limits (see abuse.py). Platform-level."""

    __tablename__ = "rate_counters"
    key: Mapped[str] = mapped_column(String(200), primary_key=True)
    window_start: Mapped[datetime] = mapped_column(DateTime(timezone=True), primary_key=True)
    count: Mapped[int] = mapped_column(Integer, default=0)


class InboundSeen(Base):
    """Provider message IDs already processed, kept a week, so webhook retries and replays
    are handled once. Platform-level."""

    __tablename__ = "inbound_seen"
    id: Mapped[str] = mapped_column(String(200), primary_key=True)
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)


class PinCheck(Base):
    """Every time a gate or rider phone checked a home PIN, right or wrong. Append-only: a wrong
    try alerts the home, and the Exco sees how often PINs are tried."""

    __tablename__ = "pin_checks"
    __table_args__ = (_check("context", PIN_CHECK_CONTEXTS, "ck_pin_checks_context"), Index("ix_pin_checks_home", "home_id", "at"))
    id: Mapped[uuid.UUID] = pk()  # client-generated
    estate_id: Mapped[uuid.UUID] = estate_fk()
    home_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("homes.id", ondelete="CASCADE"))
    ok: Mapped[bool] = mapped_column(Boolean)
    context: Mapped[str] = mapped_column(String(8))
    caller_masked: Mapped[str | None] = mapped_column(String(16))
    guard_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("guards.id"))
    shift_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shifts.id"))
    device_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("devices.id"))
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    synced_at: Mapped[datetime] = created()


class NumberOffer(Base):
    """A resident called the gate from a new number and confirmed on the callback; the guard
    offered to register it. An existing number of the home must reply YES first. The number
    itself waits in phone_numbers (pending), the only table that holds full numbers."""

    __tablename__ = "number_offers"
    __table_args__ = (_check("state", NUMBER_OFFER_STATES, "ck_number_offers_state"),)
    id: Mapped[uuid.UUID] = pk()  # client-generated
    estate_id: Mapped[uuid.UUID] = estate_fk()
    home_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("homes.id", ondelete="CASCADE"))
    resident_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("residents.id", ondelete="CASCADE"))
    number_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("phone_numbers.id", ondelete="SET NULL"))
    asked_number_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("phone_numbers.id", ondelete="SET NULL"))
    last4: Mapped[str] = mapped_column(String(4))
    state: Mapped[str] = mapped_column(String(8), default="asked")
    guard_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("guards.id"))
    shift_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shifts.id"))
    device_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("devices.id"))
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class VoiceClip(Base):
    """A visitor's name, spoken by the guard instead of typed. Encrypted in storage like a
    selfie, played only by the admin and the CSO (each play audited), deleted after 7 days.
    Entries and visits point at it by id; it may arrive before or after them."""

    __tablename__ = "voice_clips"
    id: Mapped[uuid.UUID] = pk()  # client-generated
    estate_id: Mapped[uuid.UUID] = estate_fk()
    device_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("devices.id"))
    ref: Mapped[str | None] = mapped_column(String(200))  # storage key; null once deleted
    content_type: Mapped[str] = mapped_column(String(40))
    size: Mapped[int] = mapped_column(Integer)
    uploaded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class GatePhoto(Base):
    """A photo taken at the gate: the visitor, or the car's plate. Encrypted in storage like a
    selfie, seen only by the admin and the CSO (each view audited), deleted after 30 days.
    Entries point at it by id; it may arrive before or after them."""

    __tablename__ = "gate_photos"
    __table_args__ = (CheckConstraint("kind IN ('visitor', 'plate')", name="ck_gate_photos_kind"),)
    id: Mapped[uuid.UUID] = pk()  # client-generated
    estate_id: Mapped[uuid.UUID] = estate_fk()
    device_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("devices.id"))
    kind: Mapped[str] = mapped_column(String(8))
    ref: Mapped[str | None] = mapped_column(String(200))  # storage key; null once deleted
    size: Mapped[int] = mapped_column(Integer)
    uploaded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


# --- Estate shuttle ----------------------------------------------------------------------


class Shuttle(Base):
    """One of the estate's shuttle vehicles (the pilot's are electric motorcycles)."""

    __tablename__ = "shuttles"
    __table_args__ = (UniqueConstraint("estate_id", "label"),)
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    label: Mapped[str] = mapped_column(String(40))
    plate: Mapped[str | None] = mapped_column(String(16))
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = created()


class ResidentCard(Base):
    """An estate NFC tap card. uid_hash = sha256("gatelog-card-v1|<estate_id>|<UID hex, upper>"):
    a card's UID is broadcast to any reader, so it identifies a resident but proves nothing."""

    __tablename__ = "resident_cards"
    __table_args__ = (
        Index("ux_resident_cards_uid", "estate_id", "uid_hash", unique=True, postgresql_where="revoked_at IS NULL"),
    )
    id: Mapped[uuid.UUID] = pk()  # client-generated: cards are issued on a gate phone
    estate_id: Mapped[uuid.UUID] = estate_fk()
    resident_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("residents.id", ondelete="CASCADE"), index=True)
    home_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("homes.id", ondelete="CASCADE"))
    uid_hash: Mapped[str] = mapped_column(String(64))
    uid_last4: Mapped[str] = mapped_column(String(4))
    issued_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    issued_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("guards.id"))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Ride(Base):
    """One shuttle trip. Free to residents; recorded against the home it served. Each end is a
    home, a gate or a place (kind + ref), with the label as it read when booked."""

    __tablename__ = "rides"
    __table_args__ = (
        _check("kind", RIDE_KINDS, "ck_rides_kind"),
        _check("source", RIDE_SOURCES, "ck_rides_source"),
        _check("state", RIDE_STATES, "ck_rides_state"),
        _check("pickup_kind", STOP_KINDS, "ck_rides_pickup_kind"),
        _check("dropoff_kind", STOP_KINDS, "ck_rides_dropoff_kind"),
        CheckConstraint(
            "confirmed_by IS NULL OR confirmed_by IN ('card', 'house_code', 'guard', 'rider')", name="ck_rides_confirmed_by"
        ),
        Index("ix_rides_open", "estate_id", "state", "wanted_at"),
    )
    id: Mapped[uuid.UUID] = pk()  # client-generated when booked on a phone
    estate_id: Mapped[uuid.UUID] = estate_fk()
    home_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("homes.id", ondelete="CASCADE"), index=True)
    resident_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("residents.id", ondelete="SET NULL"))
    kind: Mapped[str] = mapped_column(String(10))
    source: Mapped[str] = mapped_column(String(10))
    state: Mapped[str] = mapped_column(String(10), default="requested")
    passenger: Mapped[str | None] = mapped_column(String(120))  # the guest's name, or what the parcel is
    pickup_kind: Mapped[str] = mapped_column(String(6))
    pickup_ref: Mapped[uuid.UUID | None] = mapped_column()
    pickup_label: Mapped[str] = mapped_column(String(160))
    dropoff_kind: Mapped[str] = mapped_column(String(6))
    dropoff_ref: Mapped[uuid.UUID | None] = mapped_column()
    dropoff_label: Mapped[str] = mapped_column(String(160))
    wanted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    note: Mapped[str | None] = mapped_column(String(200))
    booked_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("guards.id"))  # guard, CSO or rider; null by message
    booked_shift_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shifts.id"))
    rider_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("guards.id"))
    shuttle_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shuttles.id"))
    confirmed_by: Mapped[str | None] = mapped_column(String(10))
    confirmed_resident_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("residents.id", ondelete="SET NULL"))
    card_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("resident_cards.id", ondelete="SET NULL"))
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    picked_up_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    done_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))  # cancelled or no-show
    created_at: Mapped[datetime] = created()


class RideEvent(Base):
    """What happened to a ride, from a phone. Append-only: the ride row is the current state,
    these are how it got there and who did it."""

    __tablename__ = "ride_events"
    __table_args__ = (_check("event", RIDE_EVENTS, "ck_ride_events_event"),)
    id: Mapped[uuid.UUID] = pk()  # client-generated
    estate_id: Mapped[uuid.UUID] = estate_fk()
    ride_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("rides.id", ondelete="CASCADE"), index=True)
    event: Mapped[str] = mapped_column(String(10))
    guard_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("guards.id"))
    shift_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shifts.id"))
    device_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("devices.id"))
    applied: Mapped[bool] = mapped_column(Boolean, default=True)  # false: it came too late to change the ride
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    lat: Mapped[float | None] = mapped_column(Float)
    lng: Mapped[float | None] = mapped_column(Float)
    synced_at: Mapped[datetime] = created()


class Position(Base):
    """A rider phone's position during an open rider shift. Kept 7 days."""

    __tablename__ = "positions"
    __table_args__ = (Index("ix_positions_live", "estate_id", "at"), Index("ix_positions_shift", "shift_id", "at"))
    id: Mapped[uuid.UUID] = pk()
    estate_id: Mapped[uuid.UUID] = estate_fk()
    shift_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("shifts.id", ondelete="CASCADE"))
    guard_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("guards.id"))
    shuttle_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("shuttles.id"))
    lat: Mapped[float] = mapped_column(Float)
    lng: Mapped[float] = mapped_column(Float)
    accuracy_m: Mapped[float | None] = mapped_column(Float)
    heading: Mapped[float | None] = mapped_column(Float)
    speed: Mapped[float | None] = mapped_column(Float)  # m/s
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


TENANT_TABLES = [
    t.__tablename__
    for t in (
        Zone, Street, Home, Resident, PhoneNumber, Gate, Guard, Shift, Vehicle, Device, Visit, Callback, Entry, Exit,
        OverstayNudge, Rollup, RollupItem, DirectoryReport, Conversation, MessageLog, ImportBatch, AuditEvent,
        Place, Shuttle, ResidentCard, Ride, RideEvent, Position, PinCheck, NumberOffer, VoiceClip, GatePhoto,
    )
]
