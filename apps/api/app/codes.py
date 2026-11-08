"""Six-digit gate codes, signed per visit.

    code = truncate(HMAC-SHA256(estate_key, "gatelog-code-v1|<home_id>|<visit_id>|<start>|<end>"))

home_id and visit_id are lowercase hyphenated UUIDs; start and end are Unix seconds (UTC)
of the validity window. Truncation is RFC 4226 dynamic truncation, mod 10^6, zero-padded.

The guard app runs the same function against the expected visits it has cached, so it can
verify with no network. `docs/code-test-vectors.json` at the repo root pins the output, and
both this module and the Flutter app test against it: change one without the other and a
gate stops admitting guests.
"""

import hashlib
import hmac
from datetime import datetime
from uuid import UUID

PREFIX = "gatelog-code-v1"
DIGITS = 6


def message(home_id: UUID, visit_id: UUID, window_start: datetime, window_end: datetime) -> bytes:
    if not isinstance(home_id, UUID) or not isinstance(visit_id, UUID):
        raise TypeError("home_id and visit_id must be UUIDs")
    return f"{PREFIX}|{home_id}|{visit_id}|{int(window_start.timestamp())}|{int(window_end.timestamp())}".encode()


def derive(key: bytes, home_id: UUID, visit_id: UUID, window_start: datetime, window_end: datetime) -> str:
    digest = hmac.new(key, message(home_id, visit_id, window_start, window_end), hashlib.sha256).digest()
    offset = digest[-1] & 0x0F
    value = int.from_bytes(digest[offset : offset + 4], "big") & 0x7FFFFFFF
    return str(value % 10**DIGITS).zfill(DIGITS)


def display(code: str) -> str:
    """'482917' -> '482 917', the way residents read it out to a guest."""
    return f"{code[:3]} {code[3:]}"


def clean(entered: str) -> str | None:
    digits = "".join(ch for ch in entered if ch.isdigit())
    return digits if len(digits) == DIGITS else None
