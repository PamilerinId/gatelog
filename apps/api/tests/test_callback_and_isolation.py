"""Call-the-gate (callback flows A and B), tenant isolation, and losing a gate phone."""

import base64
import uuid

import pytest
from sqlalchemy import create_engine, text

from app.config import get_settings
from tests.helpers import P, client, last_code, make_estate, sms_in
from tests.test_gate_flow import offline_verify

PHONE = "08031234567"


def test_flow_a_resident_calls_ahead(owner, outbox, at):
    """Mama in 14B rings the gate. The guard calls her registered number back, she confirms,
    the guest arrives and is admitted. She prefers calls, so the notice comes by SMS."""
    e = make_estate(owner, contact_pref="call")
    state = client.get("/v1/device/state", headers=e.dev).json()
    home = next(h for h in state["homes"] if h["id"] == e.home_id)
    resident = home["residents"][0]
    number = resident["numbers"][0]
    assert number["e164"] == "+2348031234567"  # the phone must be able to dial it offline

    visit_id, callback_id, entry_id = (str(uuid.uuid4()) for _ in range(3))
    batch = {
        "visits": [{"id": visit_id, "home_id": e.home_id, "resident_id": resident["id"], "guest_name": "Pastor Femi",
                    "window_start": "2026-10-21T08:00:00Z", "window_end": "2026-10-21T22:59:00Z",
                    "expected_until": "2026-10-21T20:00:00Z", "stay_type": "hours", "stay_minutes": 120}],
        "callbacks": [{"id": callback_id, "home_id": e.home_id, "number_id": number["id"], "outcome": "confirmed",
                       "visit_id": visit_id, "guard_id": e.guard_id, "at": "2026-10-21T08:05:00Z"}],
    }
    r = client.post("/v1/device/sync", headers=e.dev, json=batch).json()
    assert set(r["accepted"]) == {visit_id, callback_id} and not r["rejected"]

    at(21, 11, 1)
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        {"id": entry_id, "home_id": e.home_id, "visit_id": visit_id, "guest_name": "Pastor Femi", "method": "callback_confirmed",
         "guard_id": e.guard_id, "at": "2026-10-21T10:00:00Z"}]})
    assert outbox.sent[-1].body == P + "Pastor Femi is in. Main Gate, 11:00." and outbox.sent[-1].channel == "sms"
    summary = client.get("/v1/reports/summary", headers=e.admin).json()
    assert summary["entries"]["by_method"]["callback_confirmed"] == 1 and summary["phone_share"] == 1.0


def test_flow_b_failed_callback_is_refused_and_logged(owner, outbox, at):
    e = make_estate(owner)
    number_id = e.number_ids[0]
    batch = {
        "callbacks": [{"id": str(uuid.uuid4()), "home_id": e.home_id, "number_id": number_id, "outcome": "no_answer", "at": "2026-10-21T08:00:00Z"},
                      {"id": str(uuid.uuid4()), "home_id": e.home_id, "number_id": number_id, "outcome": "no_answer", "at": "2026-10-21T08:03:00Z"}],
        "entries": [{"id": str(uuid.uuid4()), "home_id": e.home_id, "guest_name": "Man with no code", "method": "refused", "at": "2026-10-21T08:04:00Z"}],
    }
    assert len(client.post("/v1/device/sync", headers=e.dev, json=batch).json()["accepted"]) == 3
    with owner.connect() as c:
        assert c.execute(text("SELECT number_last4 FROM callbacks")).scalars().all() == ["4567", "4567"]
    assert client.get("/v1/admin/entries", headers=e.admin).json()[0]["method"] == "refused"


def test_callback_only_to_a_number_registered_to_that_home(owner, outbox, at):
    e = make_estate(owner)
    other = client.post("/v1/admin/homes", headers=e.admin, json={"street_id": client.get("/v1/admin/register", headers=e.admin).json()[0]["streets"][0]["id"], "label": "15"}).json()
    r = client.post("/v1/device/sync", headers=e.dev, json={"callbacks": [
        {"id": str(uuid.uuid4()), "home_id": other["id"], "number_id": e.number_ids[0], "outcome": "confirmed", "at": "2026-10-21T08:00:00Z"}]}).json()
    assert r["rejected"][0]["reason"] == "number is not registered to that home"


def test_a_device_cannot_write_into_another_estate(owner, outbox, at):
    a = make_estate(owner, name="Estate A")
    b = make_estate(owner, name="Estate B", phone="08039999999")
    r = client.post("/v1/device/sync", headers=a.dev, json={"entries": [
        {"id": str(uuid.uuid4()), "home_id": b.home_id, "guest_name": "Intruder", "method": "refused", "at": "2026-10-21T08:00:00Z"}]}).json()
    assert r["rejected"][0]["reason"] == "unknown home, guard or gate"
    assert client.get(f"/v1/admin/homes/{b.home_id}", headers=a.admin).status_code == 404
    names = {h["id"] for h in client.get("/v1/device/state", headers=a.dev).json()["homes"]}
    assert names == {a.home_id}


def test_rls_holds_at_the_database(owner, outbox, at):
    """Even raw SQL as the app role sees only the scoped estate, and nothing when unscoped."""
    a = make_estate(owner, name="Estate A")
    b = make_estate(owner, name="Estate B", phone="08039999999")
    app_engine = create_engine(get_settings().database_url)
    with app_engine.begin() as c:
        assert c.execute(text("SELECT count(*) FROM homes")).scalar() == 0
        c.execute(text("SELECT set_config('app.estate_id', :e, true)"), {"e": a.id})
        assert {str(r) for r in c.execute(text("SELECT id FROM homes")).scalars()} == {a.home_id}
        with pytest.raises(Exception):
            c.execute(text("INSERT INTO zones (id, estate_id, name) VALUES (gen_random_uuid(), :b, 'Sneaky')"), {"b": b.id})
    with app_engine.begin() as c:
        c.execute(text("SELECT set_config('app.estate_id', :e, true)"), {"e": a.id})
        with pytest.raises(Exception):
            c.execute(text("UPDATE audit_events SET action = 'nothing'"))


def test_phone_numbers_are_encrypted_and_never_logged(owner, outbox, at, caplog):
    e = make_estate(owner)
    with owner.connect() as c:
        raw = c.execute(text("SELECT e164_enc FROM phone_numbers")).scalar()
    assert b"8031234567" not in bytes(raw)
    caplog.set_level("INFO")
    sms_in(PHONE, "Tunde today")
    assert "8031234567" not in caplog.text and "***4567" in caplog.text
    resident = client.get(f"/v1/admin/homes/{e.home_id}", headers=e.admin).json()["residents"][0]
    assert resident["numbers"][0]["masked"] == "***4567" and "e164" not in resident["numbers"][0]


def test_max_three_numbers_per_home(owner, outbox, at):
    e = make_estate(owner)
    for n in ("08031111111", "08032222222"):
        assert client.post(f"/v1/admin/residents/{e.resident_id}/numbers", headers=e.admin, json={"number": n}).status_code == 201
    r = client.post(f"/v1/admin/residents/{e.resident_id}/numbers", headers=e.admin, json={"number": "08033333333"})
    assert r.status_code == 409 and "at most 3" in r.json()["detail"]


def test_revoking_a_lost_phone(owner, outbox, at):
    e = make_estate(owner)
    sms_in(PHONE, "Tunde today")
    old_code = last_code(outbox)
    second = client.post("/v1/admin/devices", headers=e.admin, json={"gate_id": e.gate_id, "label": "Pedestrian gate"}).json()
    other = client.post("/v1/device/pair", json={"code": second["pairing_code"]}).json()
    lost = client.get("/v1/admin/devices", headers=e.admin).json()[0]
    r = client.post(f"/v1/admin/devices/{lost['id']}/revoke", headers=e.admin)
    assert r.json()["status"] == "revoked"
    assert client.get("/v1/device/state", headers=e.dev).status_code == 401

    other_headers = {"Authorization": f"Bearer {other['token']}"}
    state = client.get("/v1/device/state", headers=other_headers).json()
    assert state["estate"]["key_version"] == 2 and [k["version"] for k in state["keys"]] == [1, 2]
    assert offline_verify(state, old_code) is not None  # codes already issued keep working
    sms_in(PHONE, "Ada today")
    state = client.get("/v1/device/state", headers=other_headers).json()
    new_visit = offline_verify(state, last_code(outbox))
    assert new_visit["key_version"] == 2
    old_key = base64.b64decode(next(k for k in state["keys"] if k["version"] == 1)["key_b64"])
    assert old_key  # the lost phone held only version 1, which signs nothing new
    with owner.connect() as c:
        audit = [r[0] for r in c.execute(text("SELECT action FROM audit_events ORDER BY at"))]
    assert "revoke" in audit and "rotate_key" in audit


def test_pairing_code_works_once(owner, outbox, at):
    e = make_estate(owner)
    d = client.post("/v1/admin/devices", headers=e.admin, json={"gate_id": e.gate_id, "label": "Spare"}).json()
    assert client.post("/v1/device/pair", json={"code": d["pairing_code"].lower()}).status_code == 200
    assert client.post("/v1/device/pair", json={"code": d["pairing_code"]}).status_code == 400


def test_flow_b_guest_is_visible_to_every_gate_and_the_night_list(owner, outbox, at):
    """No code, callback confirmed, admitted: the server makes the visit so other gates, the
    nudge and the night list all see the guest, and tells the resident who confirmed."""
    e = make_estate(owner, contact_pref="sms")
    entry_id = str(uuid.uuid4())
    batch = {
        "callbacks": [{"id": str(uuid.uuid4()), "home_id": e.home_id, "number_id": e.number_ids[0], "outcome": "confirmed", "at": "2026-10-21T08:00:00Z"}],
        "entries": [{"id": entry_id, "home_id": e.home_id, "guest_name": "Plumber Sule", "method": "callback_confirmed",
                     "guard_id": e.guard_id, "at": "2026-10-21T08:01:00Z"}],
    }
    assert len(client.post("/v1/device/sync", headers=e.dev, json=batch).json()["accepted"]) == 2
    client.post("/v1/device/sync", headers=e.dev, json=batch)  # a retry makes no second visit
    assert outbox.sent[-1].body == P + "Plumber Sule is in. Main Gate, 09:01."

    second = client.post("/v1/admin/devices", headers=e.admin, json={"gate_id": e.gate_id, "label": "Back gate"}).json()
    other = {"Authorization": f"Bearer {client.post('/v1/device/pair', json={'code': second['pairing_code']}).json()['token']}"}
    inside = [v for v in client.get("/v1/device/state", headers=other).json()["visits"] if v["state"] == "inside"]
    assert len(inside) == 1 and inside[0]["guest_name"] == "Plumber Sule" and inside[0]["entry_id"] == entry_id

    at(21, 22, 5)  # still inside past the default stay (9pm): on the night list, by name
    client.post("/internal/jobs/tick")
    item = client.get("/v1/device/state", headers=other).json()["rollup"]["items"][0]
    assert item["guest_name"] == "Plumber Sule" and item["address"] == "14B Adeniyi Close, Block C"
