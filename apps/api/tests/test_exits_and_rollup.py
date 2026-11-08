"""Visit length, overstay nudges, the nightly rollup and the morning handover."""

import uuid

from sqlalchemy import text

from app.auth import staff_token
from tests.helpers import P, bearer, client, make_estate, sms_in
from tests.test_gate_flow import offline_verify, last_code

PHONE = "08031234567"


def admit(e, outbox, guest: str, at_utc: str) -> dict:
    visit = offline_verify(client.get("/v1/device/state", headers=e.dev).json(), last_code(outbox))
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        {"id": str(uuid.uuid4()), "home_id": visit["home_id"], "visit_id": visit["id"], "guest_name": guest, "method": "code", "at": at_utc}]})
    return visit


def tick() -> dict:
    return client.post("/internal/jobs/tick").json()


def visit_state(e, visit_id: str) -> str:
    return next(v["state"] for v in client.get("/v1/admin/visits", headers=e.admin).json() if v["id"] == visit_id)


def test_no_stay_given_offers_quick_options(owner, outbox, at):
    e = make_estate(owner)
    sms_in(PHONE, "Tunde today 4pm")
    assert "1 about an hour" in outbox.sent[-1].body
    sms_in(PHONE, "3")
    assert outbox.sent[-1].body == P + "Noted. We expect Tunde to leave tomorrow until 10am."
    v = client.get("/v1/admin/visits", headers=e.admin).json()[0]
    assert v["stay_type"] == "overnight"


def test_longer_asks_for_a_date(owner, outbox, at):
    make_estate(owner)
    sms_in(PHONE, "Aunty Bisi today")
    sms_in(PHONE, "4")
    assert outbox.sent[-1].body.startswith(P + "Until what date?")
    sms_in(PHONE, "Sunday")
    assert "Sun 25 Oct, 6pm" in outbox.sent[-1].body


def test_nudge_then_resident_says_left(owner, outbox, at):
    e = make_estate(owner)
    sms_in(PHONE, "Tunde today 2pm for 2 hours")
    at(21, 14)
    visit = admit(e, outbox, "Tunde", "2026-10-21T13:00:00Z")
    at(21, 16, 30)
    assert tick()["nudges"] == 1
    assert outbox.sent[-1].body == P + "Is Tunde still with you? Reply 1 staying (until when?), 2 already left."
    assert tick()["nudges"] == 0  # once per expected_until
    sms_in(PHONE, "2")
    assert "marked Tunde as gone" in outbox.sent[-1].body
    assert visit_state(e, visit["id"]) == "left"


def test_nudge_then_staying_until(owner, outbox, at):
    e = make_estate(owner)
    sms_in(PHONE, "Tunde today 2pm for 2 hours")
    at(21, 14)
    visit = admit(e, outbox, "Tunde", "2026-10-21T13:00:00Z")
    at(21, 16, 30)
    tick()
    sms_in(PHONE, "1")
    assert outbox.sent[-1].body.startswith(P + "Until when?")
    sms_in(PHONE, "till 9pm")
    assert outbox.sent[-1].body == P + "Noted. Tunde is expected to leave today until 9pm."
    assert visit_state(e, visit["id"]) == "inside"
    # The extension has passed too, before quiet hours begin: a fresh nudge for the new time.
    at(21, 21, 30)
    assert tick()["nudges"] == 1


def test_rollup_handover_and_guard_check(owner, outbox, at):
    e = make_estate(owner)
    # The security head receives the night list by SMS.
    with owner.begin() as c:
        head_id = c.execute(text("SELECT id FROM staff_users WHERE estate_id = :e"), {"e": e.id}).scalar()
    r = client.post("/v1/admin/staff", headers=e.admin, json={"email": "head@example.com", "name": "Sgt Okon", "role": "security_head", "phone": "08051112222"})
    assert r.status_code == 201, r.text
    assert head_id

    sms_in(PHONE, "Tunde today 2pm for 2 hours")
    at(21, 14)
    tunde = admit(e, outbox, "Tunde", "2026-10-21T13:00:00Z")
    sms_in(PHONE, "Ada today 3pm for an hour")
    at(21, 15)
    ada = admit(e, outbox, "Ada", "2026-10-21T14:00:00Z")

    at(21, 22, 5)
    result = tick()
    assert result["rollups"] == 1 and result["nudges"] == 0  # 22:05 is quiet hours
    night = next(m for m in outbox.sent if m.kind == "rollup")
    assert night.to == "+2348051112222"
    assert "2 guests still inside past their time" in night.body
    assert "14B Adeniyi Close, Block C: Tunde, in 14:00, due 16:00, resident: not asked" in night.body
    assert "resident" in night.body and "080" not in night.body  # nothing else about the resident
    assert tick()["rollups"] == 0  # once a night

    # The guard checks Ada's house: she has gone.
    state = client.get("/v1/device/state", headers=e.dev).json()
    item = next(i for i in state["rollup"]["items"] if i["visit_id"] == ada["id"])
    client.post("/v1/device/sync", headers=e.dev, json={"rollup_checks": [{"item_id": item["id"], "result": "left", "guard_id": e.guard_id, "at": "2026-10-21T21:30:00Z"}]})
    assert visit_state(e, ada["id"]) == "left"

    at(22, 7, 5)
    assert tick()["missed_exits"] == 1
    assert visit_state(e, tunde["id"]) == "rollup_closed"
    summary = client.get("/v1/reports/summary", headers=e.admin).json()
    assert summary["overstays_by_night"] == [{"date": "2026-10-21", "open_at_rollup": 2, "closed_by_morning": 1, "missed": 1}]
    assert summary["exits"]["missed"] == 1 and summary["exits"]["capture_rate"] == 0.5
    assert client.get("/v1/device/state", headers=e.dev).json()["rollup"] is None
    member = client.post("/v1/admin/staff", headers=e.admin, json={"email": "chair@example.com", "name": "Chief Bello", "role": "committee"}).json()
    committee = bearer(staff_token(uuid.UUID(member["id"]), uuid.UUID(e.id), "committee"))
    assert client.get("/v1/reports/summary", headers=committee).status_code == 200
    assert client.post("/v1/admin/zones", headers=committee, json={"name": "X"}).status_code == 403
