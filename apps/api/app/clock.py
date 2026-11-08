"""The one place the API asks what time it is, so tests can move it."""

from datetime import datetime, timezone

_frozen: datetime | None = None


def now() -> datetime:
    return _frozen or datetime.now(timezone.utc)


def freeze(at: datetime | None) -> None:
    global _frozen
    _frozen = at
