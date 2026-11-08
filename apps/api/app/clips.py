"""Visitors' names spoken at the gate instead of typed (guards may not write easily).

The clip is encrypted before storage, played only by the admin and the CSO (each play
audited), and deleted after 7 days, the same rule as the Phase 2 IVR name clips. Until
someone types the name in the dashboard, the log shows "Voice clip".
"""

from datetime import timedelta

from sqlalchemy import select

from . import clock, db, storage
from .models import VoiceClip

KEEP = timedelta(days=7)
MAX_BYTES = 300 * 1024  # about 30 seconds of speech at phone quality
TYPES = {"audio/mp4", "audio/aac", "audio/m4a", "audio/ogg", "audio/mpeg", "audio/webm", "audio/wav"}
PLACEHOLDER = "Voice clip"


def key(estate_id, clip_id) -> str:
    return f"clips/{estate_id}/{clip_id}.enc"


def housekeeping() -> dict[str, int]:
    n = 0
    with db.session(ops=True) as s:
        for c in s.scalars(select(VoiceClip).where(VoiceClip.deleted_at.is_(None), VoiceClip.uploaded_at < clock.now() - KEEP)):
            if c.ref:
                storage.store().delete(c.ref)
            c.ref, c.deleted_at = None, clock.now()
            n += 1
    return {"clips_deleted": n}
