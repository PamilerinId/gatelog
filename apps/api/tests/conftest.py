"""Integration tests run against real Postgres (docker compose up -d), as the same non-owner
role the API uses in production, so Row-Level Security is exercised, not mocked.

Tests that need the database are skipped if it is not reachable.
"""

import os
from datetime import datetime
from zoneinfo import ZoneInfo

os.environ.setdefault("DATABASE_URL", "postgresql+psycopg://gatelog_app:gatelog_app@localhost:54329/gatelog_test")
os.environ.setdefault("DATABASE_OWNER_URL", "postgresql+psycopg://gatelog_owner:gatelog_owner@localhost:54329/gatelog_test")
os.environ.setdefault("API_INTERNAL_TOKEN", "")
os.environ.setdefault("SMS_WEBHOOK_SECRET", "test-sms-secret")
# Never reach a real provider from tests, whatever the developer's shell has set.
for name in ("POSTMARK_SERVER_TOKEN", "TERMII_API_KEY", "WHATSAPP_TOKEN", "WHATSAPP_APP_SECRET", "FCM_PROJECT", "OPS_EMAIL"):
    os.environ[name] = ""
os.environ["MESSAGING_PROVIDER"] = "console"
os.environ["KEY_STORE"] = "dev"

import pytest
from sqlalchemy import create_engine, text

from app import clock, email, messaging, push
from app.config import get_settings

LAGOS = ZoneInfo("Africa/Lagos")


def _db_available() -> bool:
    try:
        with create_engine(get_settings().database_owner_url).connect():
            return True
    except Exception:
        return False


DB = _db_available()


@pytest.fixture(scope="session")
def migrated():
    if not DB:
        pytest.skip("Postgres not running: docker compose up -d")
    from alembic import command
    from alembic.config import Config

    owner = create_engine(get_settings().database_owner_url)
    with owner.begin() as c:
        c.execute(text("DROP SCHEMA public CASCADE; CREATE SCHEMA public;"))
    cfg = Config(os.path.join(os.path.dirname(__file__), "..", "alembic.ini"))
    cfg.set_main_option("script_location", os.path.join(os.path.dirname(__file__), "..", "migrations"))
    cfg.attributes["url"] = get_settings().database_owner_url
    command.upgrade(cfg, "head")
    return owner


@pytest.fixture
def owner(migrated):
    """A connection as the table owner (RLS does not apply): for setup and inspection only."""
    with migrated.begin() as c:
        tables = c.execute(text("SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename <> 'alembic_version'")).scalars().all()
        # Fail fast instead of hanging if a test left a connection holding a lock.
        c.execute(text("SET LOCAL lock_timeout = '5s'"))
        c.execute(text(f"TRUNCATE {', '.join(tables)} CASCADE"))
    return migrated


@pytest.fixture
def outbox():
    sender = messaging.ConsoleSender()
    messaging.use_sender(sender)
    email.outbox.clear()
    push.sent.clear()
    return sender


@pytest.fixture
def at():
    """Move the clock: at(21, 16, 5) is 21 Oct 2026, 16:05 in Lagos."""

    def move(day: int, hour: int, minute: int = 0, month: int = 10) -> datetime:
        t = datetime(2026, month, day, hour, minute, tzinfo=LAGOS)
        clock.freeze(t)
        return t

    move(21, 9)
    yield move
    clock.freeze(None)
