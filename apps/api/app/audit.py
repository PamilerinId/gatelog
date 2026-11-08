"""Append-only audit log for the register, contacts, ladder and directory: who, what, when,
before, after. Encrypted columns are left out of snapshots; a number appears as last4."""

from datetime import date, datetime, time
from uuid import UUID

from sqlalchemy import inspect
from sqlalchemy.orm import Session

from .models import AuditEvent, Base

_SKIP = {"e164_enc", "e164_index", "token_hash", "pairing_code_hash", "fcm_token", "house_code_enc", "house_code_hash"}


def snapshot(obj: Base | None) -> dict | None:
    if obj is None:
        return None
    out = {}
    for attr in inspect(obj).mapper.column_attrs:
        if attr.key in _SKIP:
            continue
        v = getattr(obj, attr.key)
        if isinstance(v, (UUID, datetime, date, time)):
            v = v.isoformat() if not isinstance(v, UUID) else str(v)
        out[attr.key] = v
    return out


def record(db: Session, estate_id: UUID, actor: str, action: str, entity: Base, before: dict | None = None) -> None:
    db.flush()
    after = snapshot(entity) if action != "delete" else None
    db.add(
        AuditEvent(
            estate_id=estate_id,
            actor=actor,
            entity=entity.__tablename__,
            entity_id=str(getattr(entity, "id")),
            action=action,
            before=before,
            after=after,
        )
    )
