"""Who is calling.

    staff    dashboard users. Emailed one-time code -> signed token (12h). Role decides access;
             Gatelog ops have no estate and pick one per request with X-Estate-Id.
    device   a gate phone. Paired once with a short code from the dashboard, then holds an
             opaque token "gld.<device_id>.<estate_id>.<secret>"; only its hash is stored.
             The estate in the token scopes the lookup, so no cross-tenant query is needed.
    internal Cloud Scheduler and the web app, with the shared API_INTERNAL_TOKEN.
"""

import hashlib
import hmac
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import UUID

import jwt
from fastapi import Depends, Header, HTTPException, status

from . import clock, db
from .config import get_settings
from .models import Device, Estate, StaffUser

PAIRING_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # no 0/O, 1/I/L


@dataclass(frozen=True)
class Staff:
    id: UUID
    estate_id: UUID | None
    role: str

    @property
    def actor(self) -> str:
        return f"staff:{self.id}"


@dataclass(frozen=True)
class DeviceAuth:
    id: UUID
    estate_id: UUID
    gate_id: UUID

    @property
    def actor(self) -> str:
        return f"device:{self.id}"


def sha256(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def unauthorised(detail: str = "unauthorised") -> HTTPException:
    return HTTPException(status.HTTP_401_UNAUTHORIZED, detail)


def _bearer(authorization: str | None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise unauthorised()
    return authorization[7:]


# --- staff ---------------------------------------------------------------------------------


def staff_token(staff_id: UUID, estate_id: UUID | None, role: str) -> str:
    s = get_settings()
    now = datetime.now(timezone.utc)  # real time: PyJWT checks expiry against the real clock
    claims = {"sub": str(staff_id), "est": str(estate_id) if estate_id else None, "role": role, "iat": now, "exp": now + timedelta(minutes=s.staff_token_minutes)}
    return jwt.encode(claims, s.token_secret, algorithm="HS256")


def current_staff(authorization: str | None = Header(default=None), x_estate_id: str | None = Header(default=None)) -> Staff:
    try:
        claims = jwt.decode(_bearer(authorization), get_settings().token_secret, algorithms=["HS256"])
    except jwt.PyJWTError:
        raise unauthorised()
    role = claims["role"]
    estate = UUID(claims["est"]) if claims.get("est") else None
    # A token outlives a change to the account. Check it on every request, so deactivating
    # someone or changing their role or estate takes effect at once, not when the token expires.
    with db.session() as s:  # staff_users is platform-level: no estate scope needed
        u = s.get(StaffUser, UUID(claims["sub"]))
        if u is None or not u.active or u.role != role or u.estate_id != estate:
            raise unauthorised()
    if role in ("org_admin", "org_viewer"):
        # An association user picks a member estate per request; it must belong to their organisation.
        if not x_estate_id:
            return Staff(UUID(claims["sub"]), None, role)
        try:
            wanted = UUID(x_estate_id)
        except ValueError:
            raise HTTPException(400, "bad X-Estate-Id")
        with db.session(ops=True) as s:
            org = s.get(StaffUser, UUID(claims["sub"])).organisation_id
            est = s.get(Estate, wanted)
            if est is None or est.organisation_id is None or est.organisation_id != org:
                raise HTTPException(403, "that estate is not in your organisation")
        return Staff(UUID(claims["sub"]), wanted, role)
    if role == "ops" and x_estate_id:
        try:
            estate = UUID(x_estate_id)
        except ValueError:
            raise HTTPException(400, "bad X-Estate-Id")
    return Staff(UUID(claims["sub"]), estate, role)


def require(*roles: str):
    """Dependency: a staff member with one of these roles, scoped to an estate. Ops pass."""

    def dep(staff: Staff = Depends(current_staff)) -> Staff:
        if staff.role != "ops" and staff.role not in roles:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "not allowed for your role")
        if staff.estate_id is None:
            raise HTTPException(400, "choose an estate (X-Estate-Id)")
        return staff

    return dep


def require_ops(staff: Staff = Depends(current_staff)) -> Staff:
    if staff.role != "ops":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Gatelog ops only")
    return staff


# --- devices -------------------------------------------------------------------------------


def new_pairing_code() -> str:
    return "".join(secrets.choice(PAIRING_ALPHABET) for _ in range(8))


def new_device_token(device_id: UUID, estate_id: UUID) -> str:
    return f"gld.{device_id}.{estate_id}.{secrets.token_urlsafe(32)}"


def current_device(authorization: str | None = Header(default=None)) -> DeviceAuth:
    token = _bearer(authorization)
    parts = token.split(".")
    if len(parts) != 4 or parts[0] != "gld":
        raise unauthorised()
    try:
        device_id, estate_id = UUID(parts[1]), UUID(parts[2])
    except ValueError:
        raise unauthorised()
    with db.session(estate_id) as s:
        d = s.get(Device, device_id)
        if d is None or d.token_hash is None or not hmac.compare_digest(d.token_hash, sha256(token)):
            raise unauthorised()
        if d.revoked_at is not None:
            raise unauthorised("device revoked")
        return DeviceAuth(d.id, d.estate_id, d.gate_id)


# --- internal ------------------------------------------------------------------------------


def require_internal(authorization: str | None = Header(default=None)) -> None:
    expected = get_settings().api_internal_token
    if not expected:
        if get_settings().is_production:
            raise unauthorised()
        return
    if not hmac.compare_digest(authorization or "", f"Bearer {expected}"):
        raise unauthorised()
