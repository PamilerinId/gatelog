"""Dashboard sign-in: an emailed six-digit code, then a signed token. The same answer is
given whether or not the email belongs to anyone, so the endpoint cannot be used to find
out who works for which estate."""

import hmac
import logging
import secrets
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select

from .. import abuse, clock, db, email
from ..auth import Staff, current_staff, sha256, staff_token
from ..models import Estate, LoginCode, StaffUser

log = logging.getLogger("gatelog.auth")
router = APIRouter(prefix="/v1/auth", tags=["auth"])

CODE_TTL = timedelta(minutes=10)
MAX_ATTEMPTS = 5


class EmailIn(BaseModel):
    email: EmailStr


class VerifyIn(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=7)


def _ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


@router.post("/email-code", status_code=202)
def email_code(body: EmailIn, request: Request) -> dict:
    with db.session() as s:
        # Throttled silently: the answer must not reveal whether the email exists.
        if not (abuse.hit(s, abuse.LOGIN_PER_IP, _ip(request)) and abuse.hit(s, abuse.LOGIN_PER_EMAIL, body.email.lower())):
            return {"ok": True}
        u = s.scalars(select(StaffUser).where(StaffUser.email == body.email.lower(), StaffUser.active.is_(True))).first()
        if u is None:
            return {"ok": True}
        # Only the newest code works.
        for old in s.scalars(select(LoginCode).where(LoginCode.staff_id == u.id, LoginCode.used_at.is_(None))):
            old.used_at = clock.now()
        code = f"{secrets.randbelow(10**6):06d}"
        s.add(LoginCode(staff_id=u.id, code_hash=sha256(f"{u.id}:{code}"), expires_at=clock.now() + CODE_TTL))
        to = u.email
    try:
        email.send(to, f"Your Gatelog sign-in code: {code}", f"Your Gatelog sign-in code is {code}. It works for 10 minutes.\n\nIf you did not ask for it, ignore this email.")
    except Exception as exc:
        log.error("sign-in email failed domain=%s err=%s", to.split("@")[-1], type(exc).__name__)
    return {"ok": True}


@router.post("/verify")
def verify(body: VerifyIn, request: Request) -> dict:
    if not abuse.allow(abuse.VERIFY_PER_IP, _ip(request)):
        raise HTTPException(429, "Too many attempts. Try again in an hour.")
    with db.session() as s:
        u = s.scalars(select(StaffUser).where(StaffUser.email == body.email.lower(), StaffUser.active.is_(True))).first()
        lc = None
        if u:
            lc = s.scalars(
                select(LoginCode).where(LoginCode.staff_id == u.id, LoginCode.used_at.is_(None), LoginCode.expires_at > clock.now())
                .order_by(LoginCode.expires_at.desc()).with_for_update()
            ).first()
        if lc is None:
            raise HTTPException(400, "That code is wrong or has expired. Ask for a new one.")
        lc.attempts += 1
        if lc.attempts > MAX_ATTEMPTS:
            lc.used_at = clock.now()
            raise_after = True
        else:
            raise_after = not hmac.compare_digest(lc.code_hash, sha256(f"{u.id}:{body.code.strip()}"))
        if not raise_after:
            lc.used_at = clock.now()
            token = staff_token(u.id, u.estate_id, u.role)
            return {"token": token, "staff": {"id": u.id, "name": u.name, "email": u.email, "role": u.role, "estate_id": u.estate_id}}
    # Outside the transaction so the attempt count is saved.
    raise HTTPException(400, "That code is wrong or has expired. Ask for a new one.")


@router.get("/me")
def me(staff: Staff = Depends(current_staff)) -> dict:
    with db.session(staff.estate_id, ops=staff.role == "ops" and staff.estate_id is None) as s:
        u = s.get(StaffUser, staff.id)
        if u is None or not u.active:
            raise HTTPException(401, "unauthorised")
        estate = s.get(Estate, staff.estate_id) if staff.estate_id else None
        return {"id": u.id, "name": u.name, "email": u.email, "role": u.role, "estate": {"id": estate.id, "name": estate.name, "timezone": estate.timezone} if estate else None}
