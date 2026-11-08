"""Shifts on the gate phone: PIN and selfie at the start, handover at the end.

The PIN identifies the person; the selfie is an audit record of who was holding the phone.
Neither is checked by the server: the phone verifies the PIN offline against the hash it
synced, and the selfie is only ever looked at by a person, after the fact.
"""

import base64
import re
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import clock, db, storage
from .models import Estate, Shift

PIN_HASH = re.compile(r"^pbkdf2-sha256\$(\d{4,7})\$([A-Za-z0-9+/=]{16,64})\$([A-Za-z0-9+/=]{40,64})$")
MIN_ITERATIONS = 20_000
MAX_SHIFT = timedelta(hours=14)
SELFIE_KEEP = timedelta(days=30)
MAX_SELFIE_BYTES = 400 * 1024


def valid_pin_hash(value: str) -> bool:
    """The phone sends 'pbkdf2-sha256$<iterations>$<salt b64>$<sha256 b64>'. Reject anything
    weaker or malformed, so a bad client cannot store a hash that is trivial to reverse."""
    m = PIN_HASH.match(value or "")
    if not m or int(m.group(1)) < MIN_ITERATIONS:
        return False
    try:
        return len(base64.b64decode(m.group(2))) >= 16 and len(base64.b64decode(m.group(3))) == 32
    except ValueError:
        return False


def is_jpeg(data: bytes) -> bool:
    return data[:3] == b"\xff\xd8\xff"


def selfie_key(estate_id, shift_id) -> str:
    return f"selfies/{estate_id}/{shift_id}.jpg.enc"


def close_stale(s: Session) -> int:
    """A shift nobody ended closes itself 14 hours after it started."""
    n = 0
    for sh in s.scalars(select(Shift).where(Shift.ended_at.is_(None), Shift.started_at < clock.now() - MAX_SHIFT)):
        sh.ended_at, sh.end_reason = sh.started_at + MAX_SHIFT, "auto"
        n += 1
    return n


def delete_old_selfies(s: Session) -> int:
    n = 0
    old = s.scalars(select(Shift).where(Shift.selfie_ref.is_not(None), Shift.selfie_deleted_at.is_(None), Shift.started_at < clock.now() - SELFIE_KEEP))
    for sh in old:
        storage.store().delete(sh.selfie_ref)
        sh.selfie_ref, sh.selfie_deleted_at = None, clock.now()
        n += 1
    return n


def housekeeping() -> dict[str, int]:
    out = {"shifts_auto_ended": 0, "selfies_deleted": 0}
    with db.session(ops=True) as s:
        estate_ids = list(s.scalars(select(Estate.id)))
    for estate_id in estate_ids:
        with db.session(estate_id) as s:
            out["shifts_auto_ended"] += close_stale(s)
            out["selfies_deleted"] += delete_old_selfies(s)
    return out
