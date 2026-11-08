"""Abuse controls for the messaging channels and the public endpoints.

What we defend against, and how:

    SMS pumping       outbound messages only ever go to numbers an admin registered (the
                      outbox needs a phone_numbers row); unregistered SMS senders get no reply;
                      unregistered WhatsApp senders get one reply a day; a per-estate daily SMS
                      budget holds anything over it and alerts Gatelog ops.
    Spoofed floods    SMS sender IDs can be forged, so "Mrs Adeyemi" may not be her. Inbound
                      messages are capped per sender, and visits per home per day, so a forger
                      can cost little and the real resident's phone is not buried in codes.
    Replays           provider message IDs are remembered for a week; a retried or replayed
                      webhook is processed once.
    Brute force       sign-in codes and pairing codes are throttled per email and per IP.
    Directory griefing "didn't work" reports count once per reporter per number.

Counters live in Postgres, not memory: Cloud Run runs several instances, and an in-memory
limit would be per instance. Keys never contain a raw phone number (blind index only).
Platform-level tables, no RLS: limits apply before an estate is known.
"""

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import text
from sqlalchemy.orm import Session

from . import clock, db

log = logging.getLogger("gatelog.abuse")


@dataclass(frozen=True)
class Limit:
    name: str
    count: int
    window: timedelta


# Resident messages in, per sender (blind index). Generous for real use: an estate resident
# announcing guests for a party sends maybe a dozen messages in an evening.
INBOUND_BURST = Limit("in-burst", 20, timedelta(minutes=10))
INBOUND_DAILY = Limit("in-day", 100, timedelta(days=1))
# Replies to unregistered WhatsApp senders, per sender and in total per hour.
UNKNOWN_REPLY = Limit("unknown-reply", 1, timedelta(days=1))
UNKNOWN_REPLY_GLOBAL = Limit("unknown-reply-all", 200, timedelta(hours=1))
# Outbound to any one registered number per day. A security head gets one night list; a busy
# resident gets codes, arrivals and exits. Anything beyond this is a loop or an attack.
OUTBOUND_PER_NUMBER = Limit("out-number", 60, timedelta(days=1))
# Dashboard sign-in and gate phone pairing.
LOGIN_PER_EMAIL = Limit("login-email", 5, timedelta(hours=1))
LOGIN_PER_IP = Limit("login-ip", 30, timedelta(hours=1))
PAIR_PER_IP = Limit("pair-ip", 10, timedelta(hours=1))
VERIFY_PER_IP = Limit("verify-ip", 30, timedelta(hours=1))


def _window_start(limit: Limit, now: datetime) -> datetime:
    epoch = datetime(2020, 1, 1, tzinfo=timezone.utc)
    size = limit.window.total_seconds()
    return epoch + timedelta(seconds=((now - epoch).total_seconds() // size) * size)


def hit(s: Session, limit: Limit, key: str) -> bool:
    """Count one event. True if it is within the limit. Fixed windows: simple, and the worst
    case (2x the limit across a window edge) is acceptable for every limit above."""
    n = s.execute(
        text(
            "INSERT INTO rate_counters (key, window_start, count) VALUES (:k, :w, 1) "
            "ON CONFLICT (key, window_start) DO UPDATE SET count = rate_counters.count + 1 RETURNING count"
        ),
        {"k": f"{limit.name}:{key}", "w": _window_start(limit, clock.now())},
    ).scalar()
    if n == limit.count + 1:  # log the first refusal in a window, not every one
        log.warning("rate limit reached limit=%s key=%s", limit.name, key[:12])
    return n <= limit.count


def allow(limit: Limit, key: str) -> bool:
    """`hit` in its own transaction, for callers outside one."""
    with db.session() as s:
        return hit(s, limit, key)


def first_time(s: Session, provider: str, message_id: str | None) -> bool:
    """False if this provider message was already processed (a webhook retry or replay)."""
    if not message_id:
        return True
    row = s.execute(
        text("INSERT INTO inbound_seen (id, at) VALUES (:i, :a) ON CONFLICT (id) DO NOTHING RETURNING id"),
        {"i": f"{provider}:{message_id}"[:200], "a": clock.now()},
    ).first()
    return row is not None


def sweep() -> None:
    """Drop expired counters and old message IDs. Run from the scheduler tick."""
    with db.session() as s:
        # Keep counters longer than the longest window in use (31 days, the monthly usage alert).
        s.execute(text("DELETE FROM rate_counters WHERE window_start < :t"), {"t": clock.now() - timedelta(days=40)})
        s.execute(text("DELETE FROM inbound_seen WHERE at < :t"), {"t": clock.now() - timedelta(days=7)})
