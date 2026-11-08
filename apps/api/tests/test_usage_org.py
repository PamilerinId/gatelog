"""Messaging usage for the Exco and treasurer, the estate's name in messages, associations."""

import uuid

from sqlalchemy import text

from app import email
from app.auth import staff_token
from tests.helpers import P, bearer, client, make_estate, ops_headers, sms_in

PHONE = "08031234567"


def test_messages_carry_the_estates_short_name(owner, outbox, at):
    e = make_estate(owner)
    client.patch("/v1/admin/estate", headers=e.admin, json={"short_name": "SKA Exco"})
    sms_in(PHONE, "Tunde today 4pm")
    code = next(m for m in outbox.sent if m.kind == "gate_code")
    assert code.body.startswith("SKA Exco: Gate code ")


def test_usage_counts_but_never_bills_sos(owner, outbox, at):
    e = make_estate(owner, contact_pref="sms")
    ops = ops_headers(owner)
    client.patch(f"/v1/ops/estates/{e.id}/contract", headers=ops, json={"sms_allowance_per_home": 2, "sms_overage_naira": 4})
    sms_in(PHONE, "Tunde today 4pm")  # code + stay question
    sms_in(PHONE, "SOS")
    sms_in(PHONE, "NUMBERS")
    u = client.get("/v1/reports/messaging", headers=e.admin).json()
    rows = {r["purpose"]: r for r in u["by_purpose"]}
    assert rows["Guest codes"]["sms"] == 2 and rows["SOS"]["sms"] == 1 and rows["SOS"]["billed"] is False
    assert rows["Emergency numbers"]["sms"] == 1
    assert u["sms_counted"] == 2  # SOS and NUMBERS are shown, not counted
    assert u["sms_allowance"] == 2  # 2 per home, 1 home
    assert u["sms_projected"] >= 2 and u["projected_overage_naira"] >= 0
    # Estate admins cannot change their own contract terms.
    assert client.patch("/v1/admin/estate/settings", headers=e.admin, json={"sms_allowance_per_home": 500}).status_code == 422


def test_treasurer_hears_at_80_percent_once(owner, outbox, at):
    e = make_estate(owner, contact_pref="sms")
    client.post("/v1/admin/staff", headers=e.admin, json={"email": "treasurer@example.com", "name": "Mrs Treasurer", "role": "treasurer"})
    client.patch(f"/v1/ops/estates/{e.id}/contract", headers=ops_headers(owner), json={"sms_allowance_per_home": 1})
    sms_in(PHONE, "Tunde today 4pm")
    email.outbox.clear()
    client.post("/internal/jobs/tick")
    client.post("/internal/jobs/tick")
    alerts = [m for m in email.outbox if m[1].startswith("SMS use at")]
    assert {m[0] for m in alerts} >= {"treasurer@example.com"} and len([m for m in alerts if m[0] == "treasurer@example.com"]) == 1


def test_association_sees_its_estates_and_no_others(owner, outbox, at):
    a = make_estate(owner, name="Estate A")
    b = make_estate(owner, name="Estate B", phone="08039999999")
    ops = ops_headers(owner)
    org = client.post("/v1/ops/organisations", headers=ops, json={"name": "SKA Association", "kind": "association"}).json()
    client.put(f"/v1/ops/organisations/{org['id']}/estates/{a.id}", headers=ops)
    user = client.post(f"/v1/ops/organisations/{org['id']}/users", headers=ops, json={"email": "chair@ska.example.com", "name": "Chair", "role": "org_viewer"}).json()
    token = bearer(staff_token(uuid.UUID(user["id"]), None, "org_viewer"))
    assert client.get("/v1/reports/summary", headers=token | {"X-Estate-Id": a.id}).status_code == 200
    assert client.get("/v1/reports/summary", headers=token | {"X-Estate-Id": b.id}).status_code == 403
    assert client.post("/v1/admin/zones", headers=token | {"X-Estate-Id": a.id}, json={"name": "X"}).status_code == 403


def test_landlord_occupant_and_levy_payer(owner, outbox, at):
    e = make_estate(owner)
    r = client.post("/v1/admin/residents", headers=e.admin, json={"home_id": e.home_id, "name": "Chief Landlord", "relation": "landlord"}).json()
    assert r["relation"] == "landlord"
    client.patch(f"/v1/admin/homes/{e.home_id}", headers=e.admin, json={"levy_payer": "landlord"})
    home = client.get(f"/v1/admin/homes/{e.home_id}", headers=e.admin).json()
    assert home["levy_payer"] == "landlord" and {x["relation"] for x in home["residents"]} == {"landlord", "occupant"}
    with owner.connect() as c:
        assert c.execute(text("SELECT count(*) FROM audit_events WHERE entity = 'homes' AND action = 'update'")).scalar() == 1
