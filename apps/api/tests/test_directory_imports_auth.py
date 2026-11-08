"""Emergency directory, register import, dashboard sign-in."""

import re

from app import email
from tests.helpers import P, client, make_estate, ops_headers, sms_in

PHONE = "08031234567"


def test_state_numbers_go_live_only_after_a_test_call(owner, outbox, at):
    lagos = make_estate(owner, state="Lagos", lga="Kosofe")
    abuja = make_estate(owner, name="Gwarinpa", state="FCT", lga="AMAC", phone="08039999999")
    ops = ops_headers(owner)
    n = client.post("/v1/ops/directory", headers=ops, json={"scope": "lga", "state": "Lagos", "lga": "Kosofe", "category": "crime",
                                                           "name": "Police, Ketu division", "number": "08012345678", "rank": 5}).json()
    assert n["active"] is False
    assert client.get("/v1/admin/directory", headers=lagos.admin).json() == []
    client.post(f"/v1/ops/directory/{n['id']}/test-call", headers=ops, json={"answered_by": "Desk sergeant answered, 21 Oct 10:02"})
    lagos_list = client.get("/v1/admin/directory", headers=lagos.admin).json()
    assert [e["name"] for e in lagos_list] == ["Police, Ketu division"] and lagos_list[0]["editable"] is False
    assert client.get("/v1/admin/directory", headers=abuja.admin).json() == []  # another state
    assert client.patch(f"/v1/admin/directory/{n['id']}", headers=lagos.admin, json={"number": "0800"}).status_code == 403


def test_numbers_keyword_and_dead_number_reports(owner, outbox, at):
    e = make_estate(owner)
    gate = client.post("/v1/admin/directory", headers=e.admin, json={"category": "estate", "name": "Gate line", "number": "0803 000 0001", "rank": 1}).json()
    client.post("/v1/admin/directory", headers=e.admin, json={"category": "medical", "name": "Estate clinic", "number": "08030000002", "rank": 2})
    sms_in(PHONE, "numbers")
    assert outbox.sent[-1].body == P + "Emergency numbers:\nGate line: 08030000001\nEstate clinic: 08030000002"

    assert client.post("/v1/device/directory/report", headers=e.dev, json={"entry_id": gate["id"], "guard_id": e.guard_id}).json() == {"flagged": False}
    assert client.post("/v1/device/directory/report", headers=e.dev, json={"entry_id": gate["id"]}).json() == {"flagged": True}
    listed = client.get("/v1/admin/directory", headers=e.admin).json()[0]
    assert listed["reported_not_working"] is True  # still shown, never hidden
    assert email.outbox[-1][1] == "Re-test within 48 hours: Gate line"
    sms_in(PHONE, "NUMBERS")
    assert "Gate line: 08030000001 (reported not working)" in outbox.sent[-1].body

    client.post(f"/v1/admin/directory/{gate['id']}/verify", headers=e.admin, json={"note": "Musa answered"})
    listed = client.get("/v1/admin/directory", headers=e.admin).json()[0]
    assert listed["reported_not_working"] is False and listed["overdue"] is False


def test_import_is_staged_then_committed(owner, outbox, at):
    e = make_estate(owner)
    csv = (
        "Block,Street,House No,Resident Name,Phone,Contact,Callback\n"
        "Block C,Adeniyi Close,14B,Mr Adeyemi,08051230000,sms,no\n"
        "Block C,Adeniyi Close,16,Chief Okoro,0805 999 1111 / 0805 999 2222,call,yes\n"
        "Block D,Bode Thomas Court,2,,,,\n"
        "Block D,,3,Nobody,123,,\n"
    )
    r = client.post("/v1/admin/imports", headers=e.admin, files={"file": ("register.csv", csv, "text/csv")})
    assert r.status_code == 201, r.text
    batch = r.json()
    assert batch["summary"] == {"rows": 4, "errors": 1, "new_zones": 1, "new_streets": 1, "new_homes": 2, "residents": 2, "numbers": 3}
    assert batch["rows"][1]["phones"] == ["***1111", "***2222"]
    assert "street is empty" in batch["rows"][3]["errors"]
    assert client.get("/v1/admin/register", headers=e.admin).json()[0]["streets"][0]["homes"][0]["residents"] == 1  # nothing written yet

    done = client.post(f"/v1/admin/imports/{batch['id']}/commit", headers=e.admin).json()
    assert done["status"] == "committed"
    assert done["result"]["created"] == {"zones": 1, "streets": 1, "homes": 2, "residents": 2, "numbers": 3}
    zones = {z["name"]: z for z in client.get("/v1/admin/register", headers=e.admin).json()}
    assert [h["label"] for h in zones["Block D"]["streets"][0]["homes"]] == ["2"]
    okoro = next(r for r in client.get("/v1/admin/residents?q=okoro", headers=e.admin).json())
    assert okoro["contact_pref"] == "call" and okoro["callback_required"] is True and okoro["exit_notices"] is True
    assert client.post(f"/v1/admin/imports/{batch['id']}/commit", headers=e.admin).status_code == 409


def test_email_sign_in(owner, outbox, at):
    e = make_estate(owner, admin_email="fm@example.com")
    assert client.post("/v1/auth/email-code", json={"email": "nobody@example.com"}).json() == {"ok": True}
    assert email.outbox == []
    client.post("/v1/auth/email-code", json={"email": "FM@example.com"})
    code = re.search(r"(\d{6})", email.outbox[-1][1]).group(1)
    wrong = "000000" if code != "000000" else "111111"
    assert client.post("/v1/auth/verify", json={"email": "fm@example.com", "code": wrong}).status_code == 400
    r = client.post("/v1/auth/verify", json={"email": "fm@example.com", "code": code})
    assert r.status_code == 200
    token = r.json()["token"]
    me = client.get("/v1/auth/me", headers={"Authorization": f"Bearer {token}"}).json()
    assert me["estate"]["id"] == e.id and me["role"] == "admin"
    assert client.post("/v1/auth/verify", json={"email": "fm@example.com", "code": code}).status_code == 400  # used


def test_deactivated_staff_lose_access_at_once(owner, outbox, at):
    import uuid as _uuid

    from app.auth import staff_token
    from tests.helpers import bearer

    e = make_estate(owner)
    member = client.post("/v1/admin/staff", headers=e.admin, json={"email": "sec@example.com", "name": "Mr Secretary", "role": "admin"}).json()
    token = bearer(staff_token(_uuid.UUID(member["id"]), _uuid.UUID(e.id), "admin"))
    assert client.get("/v1/admin/register", headers=token).status_code == 200
    client.patch(f"/v1/admin/staff/{member['id']}?active=false", headers=e.admin)
    assert client.get("/v1/admin/register", headers=token).status_code == 401
    # A token claiming a role the account does not have is refused too.
    forged_role = bearer(staff_token(_uuid.UUID(member["id"]), _uuid.UUID(e.id), "committee"))
    assert client.get("/v1/admin/register", headers=forged_role).status_code == 401


def test_settings_are_validated(owner, outbox, at):
    e = make_estate(owner)
    assert client.patch("/v1/admin/estate/settings", headers=e.admin, json={"daily_sms_budget": 5}).status_code == 422
    assert client.patch("/v1/admin/estate/settings", headers=e.admin, json={"surprise": 1}).status_code == 422
    assert client.patch("/v1/admin/estate/settings", headers=e.admin, json={"handover_time": "23:00"}).status_code == 422
    ok = client.patch("/v1/admin/estate/settings", headers=e.admin, json={"rollup_time": "21:30"})
    assert ok.status_code == 200 and ok.json()["rollup_time"] == "21:30:00"


def test_deleting_never_takes_residents_with_it(owner, outbox, at):
    e = make_estate(owner)
    zone = client.get("/v1/admin/register", headers=e.admin).json()[0]
    street = zone["streets"][0]
    assert client.delete(f"/v1/admin/zones/{zone['id']}", headers=e.admin).status_code == 409
    assert client.delete(f"/v1/admin/streets/{street['id']}", headers=e.admin).status_code == 409
    assert client.delete(f"/v1/admin/homes/{e.home_id}", headers=e.admin).status_code == 409
    assert client.get(f"/v1/admin/homes/{e.home_id}", headers=e.admin).json()["residents"]


def test_failed_sign_in_email_still_answers_the_same(owner, outbox, at, monkeypatch):
    make_estate(owner, admin_email="fm@example.com")

    def broken(*a, **k):
        raise RuntimeError("postmark down")

    monkeypatch.setattr(email, "send", broken)
    r = client.post("/v1/auth/email-code", json={"email": "fm@example.com"})
    assert r.status_code == 202 and r.json() == {"ok": True}
