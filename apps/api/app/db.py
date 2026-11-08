"""Engine and sessions.

Every unit of work runs in one transaction that first sets `app.estate_id` (or `app.ops`)
with SET LOCAL semantics, so the Row-Level Security policies see the right tenant and the
setting cannot leak to the next request that reuses the pooled connection.
"""

from collections.abc import Iterator
from contextlib import contextmanager
from functools import lru_cache
from uuid import UUID

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from .config import get_settings


@lru_cache
def engine() -> Engine:
    return create_engine(get_settings().database_url, pool_pre_ping=True, pool_size=5, max_overflow=5)


@lru_cache
def _factory() -> sessionmaker[Session]:
    return sessionmaker(engine(), expire_on_commit=False)


def _scope(db: Session, estate_id: UUID | None, ops: bool) -> None:
    db.execute(
        text("SELECT set_config('app.estate_id', :e, true), set_config('app.ops', :o, true)"),
        {"e": str(estate_id) if estate_id else "", "o": "on" if ops else "off"},
    )


@contextmanager
def session(estate_id: UUID | None = None, *, ops: bool = False) -> Iterator[Session]:
    """A transaction scoped to one estate, to Gatelog ops (every estate), or to neither
    (platform tables only: tenant tables then read as empty)."""
    db = _factory()()
    try:
        with db.begin():
            _scope(db, estate_id, ops)
            yield db
    finally:
        db.close()


def rescope(db: Session, estate_id: UUID) -> None:
    """Narrow a platform-level transaction to one estate once it is known (an inbound
    message is matched to a resident before we know their estate)."""
    _scope(db, estate_id, False)
