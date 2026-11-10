"""Photos taken at the gate: the visitor, and the car's plate.

Visitors are third parties who never signed anything, so the estate shows a notice at the
gate (NDPA), photos are encrypted before storage, only the admin and the CSO can see them
(each view audited), and they are deleted after 30 days, the same rule as shift selfies.
They are never sent to residents or shown on the gate phone after capture.
"""

from datetime import timedelta

from sqlalchemy import select

from . import clock, db, storage
from .models import GatePhoto

KEEP = timedelta(days=30)
MAX_BYTES = 400 * 1024


def key(estate_id, photo_id) -> str:
    return f"photos/{estate_id}/{photo_id}.jpg.enc"


def housekeeping() -> dict[str, int]:
    n = 0
    with db.session(ops=True) as s:
        for p in s.scalars(select(GatePhoto).where(GatePhoto.deleted_at.is_(None), GatePhoto.uploaded_at < clock.now() - KEEP)):
            if p.ref:
                storage.store().delete(p.ref)
            p.ref, p.deleted_at = None, clock.now()
            n += 1
    return {"photos_deleted": n}
