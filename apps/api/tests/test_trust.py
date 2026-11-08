"""Trust levels on entries, the home PIN, and the second pair of eyes on weak admissions."""

import re
import uuid

from app.auth import staff_token
from tests.helpers import P, bearer, bodies, client, make_estate, sms_in
from tests.test_shifts_cso import add_person, open_shift

PHONE = "08031234567"


def kinds(outbox, kind):
    return [m for m in outbox.sent if m.kind == kind]


def entry(e, method, at="2026-10-21T07:30:00Z", **extra):  # before the frozen "now" (08:00Z)
    entry_id = str(uuid.uuid4())
    r = client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        {"id": entry_id, "home_id": e.home_id, "guest_name": extra.pop("guest_name", "Plumber"), "method": method, "at": at, **extra}]})
    assert r.status_code == 200, r.text
    assert entry_id in r.json()["accepted"], r.json()
    return entry_id


def logged(e, entry_id):
    return next(x for x in client.get("/v1/admin/entries", headers=e.admin).json() if x["id"] == entry_id)


def with_second_number(e):
    client.post(f"/v1/admin/residents/{e.resident_id}/numbers", headers=e.admin, json={"number": "08057654321"})


def test_unverified_entry_tells_every_number_of_the_home(owner, outbox, at):
    e = make_estate(owner)
    with_second_number(e)
    cso = add_person(e, "Mr Bello", role="cso")
    eid = entry(e, "walk_in_admitted", decided_by=cso, reason="Says he is the plumber", caller_masked="0803•••1234")
    alerts = kinds(outbox, "unverified_entry")
    assert len(alerts) == 2 and {m.channel for m in alerts} == {"sms"}
    assert alerts[0].body == P + "A guest (Plumber) for 14B was admitted at Main Gate, 08:30, after a call from 0803•••1234. Not you? Reply NO."
    row = logged(e, eid)
    assert row["trust"] == "unverified" and row["caller"] == "0803•••1234"

    # Not billed, so nobody weighs the cost of telling a home.
    usage = client.get("/v1/reports/messaging?month=2026-10", headers=e.admin).json()
    safety = next(p for p in usage["by_purpose"] if p["purpose"] == "Gate safety alerts")
    assert safety["sms"] == 2 and safety["billed"] is False


def test_no_reply_disputes_the_entry_and_tells_the_security_head(owner, outbox, at):
    e = make_estate(owner)
    head = client.post("/v1/admin/staff", headers=e.admin, json={"email": "head@example.com", "name": "Sgt Okon", "role": "security_head", "phone": "08051112222"})
    assert head.status_code == 201
    cso = add_person(e, "Mr Bello", role="cso")
    eid = entry(e, "walk_in_admitted", decided_by=cso, reason="Described the house well")

    sms_in(PHONE, "No")
    assert bodies(outbox)[-1] == P + "Thank you. The estate's security has been told that Plumber was not expected."
    told = kinds(outbox, "entry_disputed")
    assert len(told) == 1 and "14B Adeniyi Close, Block C says the guest admitted at Main Gate, 08:30 (Plumber) was NOT expected" in told[0].body
    assert logged(e, eid)["disputed_at"] is not None

    cso_shift = open_shift(e, cso, at="2026-10-21T08:05:00Z")
    view = client.get("/v1/device/cso", headers=e.dev | {"X-Shift-Id": cso_shift}).json()
    assert view["needs"]["disputed_today"][0]["guest_name"] == "Plumber"
    summary = client.get("/v1/reports/summary", headers=e.admin).json()
    assert summary["trust"]["disputes"][0]["entry_id"] == eid

    sms_in(PHONE, "no")  # nothing left to dispute
    assert "no unchecked guest" in bodies(outbox)[-1]


def test_verified_entries_do_not_alert(owner, outbox, at):
    e = make_estate(owner)
    entry(e, "callback_confirmed")
    assert kinds(outbox, "unverified_entry") == []
    sms_in(PHONE, "no")
    assert "no unchecked guest" in bodies(outbox)[-1]


def test_pin_confirmed_entries_and_pin_announced_visits(owner, outbox, at):
    e = make_estate(owner)
    eid = entry(e, "pin_confirmed", guest_name="Ngozi")
    assert logged(e, eid)["trust"] == "pin_verified"
    visit = next(v for v in client.get("/v1/device/state", headers=e.dev).json()["visits"] if v["entry_id"] == eid)
    assert visit["state"] == "inside"
    assert kinds(outbox, "unverified_entry") == []

    # Announced with the PIN, coming later; let in from the confirmed list: still PIN-verified.
    later = str(uuid.uuid4())
    client.post("/v1/device/sync", headers=e.dev, json={"visits": [
        {"id": later, "home_id": e.home_id, "guest_name": "Kemi", "window_start": "2026-10-21T07:00:00Z", "window_end": "2026-10-21T22:59:00Z",
         "expected_until": "2026-10-21T12:00:00Z", "stay_type": "hours", "stay_minutes": 180, "trust": "pin_verified"}]})
    eid2 = entry(e, "callback_confirmed", guest_name="Kemi", visit_id=later, at="2026-10-21T07:45:00Z")
    assert logged(e, eid2)["trust"] == "pin_verified"

    summary = client.get("/v1/reports/summary", headers=e.admin).json()["trust"]
    assert summary["phone_entries"] == {"verified": 0, "pin_verified": 2, "unverified": 0}
    assert summary["phone_by_gate"] == [{"gate": "Main Gate", "verified": 0, "pin_verified": 2, "unverified": 0}]


def test_a_full_number_is_never_accepted_as_the_caller(owner, outbox, at):
    e = make_estate(owner)
    r = client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        {"id": str(uuid.uuid4()), "home_id": e.home_id, "guest_name": "X", "method": "refused", "caller_masked": "08031234567", "at": "2026-10-21T08:00:00Z"}]})
    assert r.status_code == 422


def test_wrong_home_pin_tells_the_home_right_one_does_not(owner, outbox, at):
    e = make_estate(owner)
    with_second_number(e)

    def check(ok, **extra):
        return client.post("/v1/device/sync", headers=e.dev, json={"pin_checks": [
            {"id": str(uuid.uuid4()), "home_id": e.home_id, "ok": ok, "guard_id": e.guard_id, "at": "2026-10-21T08:00:00Z", **extra}]}).json()

    assert check(True)["accepted"] and kinds(outbox, "wrong_pin") == []
    check(False, caller_masked="0809•••7777")
    alerts = kinds(outbox, "wrong_pin")
    assert len(alerts) == 2
    assert alerts[0].body == P + ("Someone gave a wrong home PIN for 14B at the gate, 09:00, on a call from 0809•••7777. "
                                  "If it was not someone from your home, tell the estate office.")
    check(False, context="shuttle")
    assert "to the shuttle rider" in kinds(outbox, "wrong_pin")[-1].body
    for _ in range(5):
        check(False)
    assert len(kinds(outbox, "wrong_pin")) == 10  # 5 alerts an hour per home, each to both numbers; every try is still recorded
    from sqlalchemy import text
    with owner.connect() as c:
        assert c.execute(text("SELECT count(*) FROM pin_checks WHERE ok = false")).scalar() == 7


def test_home_pin_by_message_works_without_a_shuttle_and_new_pin_goes_to_everyone(owner, outbox, at):
    e = make_estate(owner)  # no shuttle
    with_second_number(e)
    sms_in(PHONE, "PIN")
    pin = re.search(r"home PIN is (\d{4})", bodies(outbox)[-1]).group(1)
    assert "shuttle" not in bodies(outbox)[-1]
    home = next(h for h in client.get("/v1/device/state", headers=e.dev).json()["homes"] if h["id"] == e.home_id)
    assert home["house_code_hash"].startswith("pbkdf2-sha256$60000$")

    sms_in(PHONE, "new pin")
    fresh = [m for m in outbox.sent if m.kind == "house_code" and "asked for a new home PIN" in m.body]
    assert len(fresh) == 2 and {m.to for m in fresh} == {"+2348031234567", "+2348057654321"}
    new_pin = re.search(r"home PIN is (\d{4})", fresh[0].body).group(1)
    home2 = next(h for h in client.get("/v1/device/state", headers=e.dev).json()["homes"] if h["id"] == e.home_id)
    assert home2["house_code_hash"] != home["house_code_hash"]
    assert new_pin.isdigit() and "The old PIN no longer works." in fresh[0].body

    # The admin can set one for an elderly resident's printed card, shuttle or not.
    r = client.post(f"/v1/admin/homes/{e.home_id}/house-code", headers=e.admin)
    assert r.status_code == 200 and re.fullmatch(r"\d{4}", r.json()["code"])
