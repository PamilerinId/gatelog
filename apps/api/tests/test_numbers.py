"""Registering a resident's new number from the gate: only with a YES from the home."""

import uuid

from sqlalchemy import text

from tests.helpers import P, bodies, client, make_estate, sms_in

PHONE = "08031234567"
NEW = "08099998888"


def offer(e, number=NEW, at="2026-10-21T07:30:00Z"):
    offer_id = str(uuid.uuid4())
    r = client.post("/v1/device/sync", headers=e.dev, json={"number_offers": [
        {"id": offer_id, "resident_id": e.resident_id, "number": number, "guard_id": e.guard_id, "at": at}]}).json()
    return offer_id, r


def numbers_on_phone(e):
    home = next(h for h in client.get("/v1/device/state", headers=e.dev).json()["homes"] if h["id"] == e.home_id)
    return [n["last4"] for r in home["residents"] for n in r["numbers"]]


def test_a_new_number_waits_for_the_homes_yes(owner, outbox, at):
    e = make_estate(owner)
    offer_id, r = offer(e)
    assert r["accepted"] == [offer_id]
    asked = [m for m in outbox.sent if m.kind == "number_offer"]
    assert len(asked) == 1 and asked[0].to == "+2348031234567" and asked[0].channel == "sms"
    assert asked[0].body == P + ("The gate was asked to add a new number ending 8888 for Mrs Adeyemi at 14B. "
                                 "Reply YES to add it, or NO if you do not know this number.")

    # Pending: invisible to the gate, to callbacks and to inbound messages.
    assert numbers_on_phone(e) == ["4567"]
    pending = next(n for n in client.get(f"/v1/admin/homes/{e.home_id}", headers=e.admin).json()["residents"][0]["numbers"] if n["last4"] == "8888")
    assert pending["pending"] is True
    r = client.post("/v1/device/sync", headers=e.dev, json={"callbacks": [
        {"id": str(uuid.uuid4()), "home_id": e.home_id, "number_id": pending["id"], "outcome": "confirmed", "at": "2026-10-21T07:40:00Z"}]}).json()
    assert r["rejected"][0]["reason"] == "number is not registered to that home"
    sent = len(outbox.sent)
    sms_in(NEW, "Tunde today 4pm")
    assert len(outbox.sent) == sent  # an unknown SMS sender gets nothing

    sms_in(PHONE, "YES")
    assert bodies(outbox)[-1] == P + "Added. The number ending 8888 is now registered for Mrs Adeyemi."
    welcome = outbox.sent[-2]
    assert welcome.to == "+2348099998888" and "now registered to Mrs Adeyemi at 14B Adeniyi Close, Block C" in welcome.body
    assert sorted(numbers_on_phone(e)) == ["4567", "8888"]
    sms_in(NEW, "Tunde today 4pm for an hour")
    assert "Gate code" in bodies(outbox)[-1]
    with owner.connect() as c:
        assert c.execute(text("SELECT count(*) FROM audit_events WHERE action IN ('offer_number', 'confirm_number')")).scalar() == 2
        assert c.execute(text("SELECT state FROM number_offers WHERE id = :i"), {"i": offer_id}).scalar() == "added"


def test_no_removes_it_and_silence_expires(owner, outbox, at):
    e = make_estate(owner)
    offer(e)
    sms_in(PHONE, "No")
    assert bodies(outbox)[-1] == P + "Not added. The number ending 8888 was not registered."
    assert numbers_on_phone(e) == ["4567"]
    with owner.connect() as c:
        assert c.execute(text("SELECT count(*) FROM phone_numbers")).scalar() == 1

    offer(e, "08077776666")
    at(23, 10, 0)  # past 48 hours, never answered
    client.post("/internal/jobs/tick")
    with owner.connect() as c:
        assert c.execute(text("SELECT count(*) FROM phone_numbers WHERE pending_until IS NOT NULL")).scalar() == 0
        assert sorted(c.execute(text("SELECT state FROM number_offers")).scalars()) == ["declined", "expired"]
    sms_in(PHONE, "yes")  # too late: nothing is waiting any more
    assert "Gate code" not in bodies(outbox)[-1]


def test_offers_respect_the_three_number_limit_and_duplicates(owner, outbox, at):
    e = make_estate(owner)
    assert "already registered to this home" in offer(e, PHONE)[1]["rejected"][0]["reason"]
    client.post(f"/v1/admin/residents/{e.resident_id}/numbers", headers=e.admin, json={"number": "08050000001"})
    offer(e)  # the third, pending
    _, r = offer(e, "08050000002")
    assert "at most 3 numbers" in r["rejected"][0]["reason"]
