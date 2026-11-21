"""Staging and production safety: real secrets and the internal token outside development, and
staging sends only to its allowlist, failing closed."""

import pytest
from sqlalchemy import text

from app import email, messaging
from app.config import Settings, get_settings
from tests.helpers import make_estate, sms_in

PHONE = "08031234567"  # the test estate's resident
REAL = {
    "TOKEN_SECRET": "x" * 40, "PHONE_ENCRYPTION_KEY": "s2a7Dq0bXyq4p1VQ4m3rLx8u6Z9cJt2wH5nK0fEoYgB=",
    "PHONE_INDEX_KEY": "real-index", "SELFIE_ENCRYPTION_KEY": "d3YxX2Rldi1vbmx5LXNlbGZpZS1rZXktY2hhbmdlLW1=",
    "KEY_STORE": "gcp", "API_INTERNAL_TOKEN": "t" * 32, "STORAGE_BACKEND": "gcs", "GCS_BUCKET": "b",
}


@pytest.fixture
def fresh_settings(monkeypatch):
    get_settings.cache_clear()
    yield monkeypatch
    get_settings.cache_clear()


def settings_with(mp, **env):
    for k, v in env.items():
        mp.setenv(k, v)
    get_settings.cache_clear()
    return get_settings()


def test_staging_refuses_dev_secrets_and_a_missing_internal_token(fresh_settings):
    with pytest.raises(RuntimeError, match="TOKEN_SECRET"):
        settings_with(fresh_settings, ENV="staging")
    with pytest.raises(RuntimeError, match="API_INTERNAL_TOKEN"):
        settings_with(fresh_settings, **{**REAL, "API_INTERNAL_TOKEN": ""}, ENV="staging")


def test_staging_refuses_to_start_without_both_allowlists(fresh_settings):
    with pytest.raises(RuntimeError, match="ALLOWED_PHONES and ALLOWED_EMAILS"):
        settings_with(fresh_settings, **REAL, ENV="staging", ALLOWED_PHONES="08031234567")
    s = settings_with(fresh_settings, **REAL, ENV="staging", ALLOWED_PHONES="0803 123 4567, +2348051112222", ALLOWED_EMAILS="Me@Example.com")
    # Both sides normalised: a local number on the list matches the E.164 the sender sees.
    assert s.send_allowlist == (frozenset({"+2348031234567", "+2348051112222"}), frozenset({"me@example.com"}))


def test_development_and_production_have_no_allowlist():
    assert Settings(env="development").send_allowlist is None
    assert Settings(env="production", allowed_phones="08031234567").send_allowlist is None


def status_of(owner, kind):
    with owner.connect() as c:
        return c.execute(text("SELECT status, body IS NOT NULL FROM message_log WHERE kind = :k"), {"k": kind}).all()


def test_off_the_list_is_withheld_not_sent_and_not_retried(owner, outbox, at):
    make_estate(owner)
    messaging.use_sender(messaging.AllowlistSender(outbox, frozenset({"+2348099999999"})))
    sms_in(PHONE, "Tunde today 4pm for an hour")
    assert outbox.sent == []
    rows = status_of(owner, "gate_code")
    assert rows == [("withheld", True)]  # its own status, and the text kept to read on staging
    messaging.dispatch()  # the scheduler tick does not pick it up again
    assert outbox.sent == [] and status_of(owner, "gate_code") == [("withheld", True)]


def test_on_the_list_is_sent(owner, outbox, at):
    make_estate(owner)
    messaging.use_sender(messaging.AllowlistSender(outbox, frozenset({"+2348031234567"})))
    sms_in(PHONE, "Tunde today 4pm for an hour")
    assert [m.kind for m in outbox.sent] == ["gate_code"] and status_of(owner, "gate_code")[0][0] == "sent"


def test_email_off_the_list_is_withheld(fresh_settings, monkeypatch):
    sent = []
    monkeypatch.setattr(email.httpx, "post", lambda *a, **k: sent.append(k["json"]["To"]))
    settings_with(fresh_settings, **REAL, ENV="staging", ALLOWED_PHONES="08031234567", ALLOWED_EMAILS="me@example.com",
                  POSTMARK_SERVER_TOKEN="pm")
    email.send("stranger@example.com", "Your code", "123456")
    assert sent == []
