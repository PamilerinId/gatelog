"""Abuse controls on WhatsApp, SMS and the public endpoints."""

import hashlib
import hmac
import json

from app import email
from app.config import get_settings
from tests.helpers import client, make_estate, sms_in

PHONE = "08031234567"


def visits(e):
    return client.get("/v1/admin/visits", headers=e.admin).json()


def test_inbound_flood_from_one_sender_is_dropped_silently(owner, outbox, at):
    e = make_estate(owner)
    for i in range(25):
        sms_in(PHONE, "hi")
    # 20 help replies, then nothing: answering a flood would turn it into outbound traffic.
    assert len(outbox.sent) == 20
    at(21, 9, 11)
    sms_in(PHONE, "Tunde today")
    assert [m.kind for m in outbox.sent[20:]] == ["gate_code", "stay_question"]
    assert len(visits(e)) == 1


def test_replayed_webhook_is_processed_once(owner, outbox, at):
    e = make_estate(owner)
    for _ in range(3):
        client.post("/v1/webhooks/sms/test-sms-secret", json={"sender": PHONE, "message": "Tunde today", "id": "termii-123"})
    assert len(visits(e)) == 1 and [m.kind for m in outbox.sent].count("gate_code") == 1


def test_whatsapp_signature_and_unknown_sender_reply_once(owner, outbox, at, monkeypatch):
    make_estate(owner)
    monkeypatch.setattr(get_settings(), "whatsapp_app_secret", "meta-secret")

    def post(msg_id: str, sender: str = "2348090000000", sig: str | None = None):
        raw = json.dumps({"entry": [{"changes": [{"value": {"messages": [
            {"id": msg_id, "from": sender, "type": "text", "text": {"body": "Tunde today"}}]}}]}]}).encode()
        good = "sha256=" + hmac.new(b"meta-secret", raw, hashlib.sha256).hexdigest()
        return client.post("/v1/webhooks/whatsapp", content=raw, headers={"X-Hub-Signature-256": sig or good, "Content-Type": "application/json"})

    assert post("wamid.1", sig="sha256=forged").status_code == 401
    for i in range(3):
        assert post(f"wamid.{i + 2}").status_code == 200
    unknown = [m for m in outbox.sent if m.kind == "not_registered"]
    assert len(unknown) == 1  # once a day per unregistered sender


def test_unregistered_sms_sender_never_gets_a_reply(owner, outbox, at):
    make_estate(owner)
    for _ in range(5):
        sms_in("08099999999", "Tunde today")
    assert outbox.sent == []


def test_visits_per_home_per_day_are_capped(owner, outbox, at):
    e = make_estate(owner)
    client.patch("/v1/admin/estate/settings", headers=e.admin, json={"max_visits_per_home_per_day": 5})
    names = ["Tunde", "Ada", "Chidi", "Ngozi", "Bayo", "Kemi", "Femi"]
    for name in names:
        sms_in(PHONE, f"{name} today")
    assert len(visits(e)) == 5
    caps = [m for m in outbox.sent if m.kind == "visit_cap"]
    assert len(caps) == 1 and "please call the gate" in caps[0].body  # told once, not per message


def test_estate_sms_budget_holds_messages_and_alerts_ops(owner, outbox, at, monkeypatch):
    e = make_estate(owner)
    monkeypatch.setattr(get_settings(), "ops_email", "ops@example.com")
    client.patch("/v1/admin/estate/settings", headers=e.admin, json={"daily_sms_budget": 10})
    for i in range(12):
        sms_in(PHONE, "hi")
    assert len(outbox.sent) == 10
    assert [m for m in email.outbox if m[1].startswith("SMS budget reached")]
    ops = __import__("tests.helpers", fromlist=["ops_headers"]).ops_headers(owner)
    held = client.get("/v1/ops/messages/held", headers=ops).json()
    assert len(held) == 2 and held[0]["to"] == "***4567"
    client.post("/v1/ops/messages/held", headers=ops, json={"ids": [held[0]["id"]], "action": "release"})
    client.post("/v1/ops/messages/held", headers=ops, json={"ids": [held[1]["id"]], "action": "drop"})
    assert len(outbox.sent) == 11
    assert client.get("/v1/ops/messages/held", headers=ops).json() == []


def test_one_person_cannot_flag_a_number_alone(owner, outbox, at):
    e = make_estate(owner)
    gate = client.post("/v1/admin/directory", headers=e.admin, json={"category": "estate", "name": "Gate line", "number": "08030000001"}).json()
    for _ in range(3):
        r = client.post("/v1/device/directory/report", headers=e.dev, json={"entry_id": gate["id"], "guard_id": e.guard_id})
    assert r.json() == {"flagged": False}


def test_sign_in_and_pairing_are_throttled(owner, outbox, at):
    make_estate(owner, admin_email="fm@example.com")
    for _ in range(7):
        assert client.post("/v1/auth/email-code", json={"email": "fm@example.com"}).json() == {"ok": True}
    assert len(email.outbox) == 5  # same answer, but no more emails
    # make_estate paired one phone from this address already: 9 more tries, then refused.
    codes = [client.post("/v1/device/pair", json={"code": "ABCD2345"}).status_code for _ in range(10)]
    assert codes[:9] == [400] * 9 and codes[9] == 429
