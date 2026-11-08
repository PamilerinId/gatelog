"""The estate shuttle (booking, riders, cards, house codes, positions) and the estate map."""

import base64
import hashlib
import re
import uuid

from sqlalchemy import text

from app import shuttle
from app.auth import staff_token
from tests.helpers import P, bearer, bodies, client, make_estate, sms_in
from tests.test_shifts_cso import add_person, open_shift

PHONE = "08031234567"
# Magodo, roughly: the estate's outline as [lng, lat].
RING = [[3.380, 6.600], [3.400, 6.600], [3.400, 6.620], [3.380, 6.620]]


def with_shuttle(owner):
    e = make_estate(owner)
    assert client.patch("/v1/admin/estate/settings", headers=e.admin, json={"shuttle_enabled": True}).status_code == 200
    e.bike = client.post("/v1/admin/shuttles", headers=e.admin, json={"label": "S1", "plate": "lnd 1 ev"}).json()["id"]
    return e


def rider_shift(e, name="Kunle Rider", at="2026-10-21T08:00:00Z"):
    rider = add_person(e, name, role="rider")
    shift_id = str(uuid.uuid4())
    r = client.post("/v1/device/sync", headers=e.dev, json={
        "shifts": [{"id": shift_id, "guard_id": rider, "started_at": at, "selfie_taken": False, "shuttle_id": e.bike}]}).json()
    assert shift_id in r["accepted"], r
    return rider, shift_id


def event(e, ride_id, ev, guard, shift, at="2026-10-21T08:10:00Z", **extra):
    ev_id = str(uuid.uuid4())
    r = client.post("/v1/device/sync", headers=e.dev, json={"ride_events": [
        {"id": ev_id, "ride_id": ride_id, "event": ev, "guard_id": guard, "shift_id": shift, "at": at, **extra}]}).json()
    return ev_id, r


def state(e):
    return client.get("/v1/device/state", headers=e.dev).json()


def test_off_unless_the_estate_runs_a_shuttle(owner, outbox, at):
    e = make_estate(owner)
    sms_in(PHONE, "ride to gate")
    assert bodies(outbox)[-1] == P + "Your estate does not run a shuttle on Gatelog."
    assert state(e)["shuttle"] is None


def test_book_by_sms_then_a_rider_takes_it_and_the_resident_is_told(owner, outbox, at):
    e = with_shuttle(owner)
    sms_in(PHONE, "ride")
    assert "Where should the shuttle take you?\n1 From your home to Main Gate" in bodies(outbox)[-1]
    sms_in(PHONE, "1")
    assert bodies(outbox)[-1].startswith(P + "Shuttle booked: 14B Adeniyi Close, Block C to Main Gate, now.")

    ride = state(e)["shuttle"]["rides"][0]
    assert ride["state"] == "requested" and ride["pickup"]["kind"] == "home" and ride["dropoff"]["label"] == "Main Gate"

    kunle, k_shift = rider_shift(e)
    ade, a_shift = rider_shift(e, "Ade Rider")
    ev, r = event(e, ride["id"], "accept", kunle, k_shift)
    assert r["accepted"] == [ev]
    assert bodies(outbox)[-1] == P + "Kunle Rider is on the way on S1 to take you from 14B Adeniyi Close, Block C."
    _, lost = event(e, ride["id"], "accept", ade, a_shift)
    assert lost["rejected"][0]["reason"] == "taken by Kunle Rider"

    event(e, ride["id"], "pick_up", kunle, k_shift, confirmed_by="house_code", resident_id=e.resident_id)
    event(e, ride["id"], "drop_off", kunle, k_shift, at="2026-10-21T08:16:00Z")
    assert state(e)["shuttle"]["rides"] == []

    logged = client.get("/v1/admin/rides", headers=e.admin).json()[0]
    assert logged["state"] == "done" and logged["rider"] == "Kunle Rider" and logged["shuttle"] == "S1"
    assert logged["confirmed_by"] == "house_code" and logged["confirmed_resident"] == "Mrs Adeyemi"
    detail = client.get(f"/v1/admin/rides/{logged['id']}", headers=e.admin).json()
    assert [(x["event"], x["by"], x["applied"]) for x in detail["events"]][:2] == [("accept", "Kunle Rider", True), ("accept", "Ade Rider", False)]

    report = client.get("/v1/reports/shuttle?month=2026-10", headers=e.admin).json()
    assert report["done"] == 1 and report["by_kind"] == {"resident": 1} and report["by_rider"] == [{"rider": "Kunle Rider", "rides": 1}]
    assert report["by_zone"][0]["zone"] == "Block C"


def test_ride_to_a_place_at_a_time_and_cancel(owner, outbox, at):
    e = with_shuttle(owner)
    client.put("/v1/admin/map/boundary", headers=e.admin, json={"ring": RING})
    client.post("/v1/admin/places", headers=e.admin, json={"name": "Clubhouse", "lat": 6.61, "lng": 3.39})
    sms_in(PHONE, "ride to the market")
    assert 'The shuttle does not know "market". Send RIDE TO and one of: Main Gate, Clubhouse.' in bodies(outbox)[-1]
    sms_in(PHONE, "ride to clubhouse at 4pm")
    assert "Shuttle booked: 14B Adeniyi Close, Block C to Clubhouse, today 4pm." in bodies(outbox)[-1]
    ride = state(e)["shuttle"]["rides"][0]
    assert ride["wanted_at"].startswith("2026-10-21T15:00")  # 4pm in Lagos and ride["dropoff"]["lat"] == 6.61
    sms_in(PHONE, "cancel ride")
    assert bodies(outbox)[-1] == P + "Cancelled your ride from 14B Adeniyi Close, Block C to Clubhouse."
    assert state(e)["shuttle"]["rides"] == []
    sms_in(PHONE, "ride home")  # from the main gate to their home
    assert "Shuttle booked: Main Gate to 14B Adeniyi Close, Block C, now." in bodies(outbox)[-1]


def test_gate_delivery_and_flag_down(owner, outbox, at):
    e = with_shuttle(owner)
    guard_shift = open_shift(e, e.guard_id)
    kunle, k_shift = rider_shift(e)
    delivery = str(uuid.uuid4())
    r = client.post("/v1/device/sync", headers=e.dev, json={"rides": [
        {"id": delivery, "kind": "delivery", "source": "gate", "home_id": e.home_id, "passenger": "Jumia parcel",
         "pickup": {"kind": "gate", "ref": e.gate_id}, "dropoff": {"kind": "home", "ref": e.home_id},
         "guard_id": e.guard_id, "shift_id": guard_shift, "at": "2026-10-21T08:05:00Z"}]}).json()
    assert r["accepted"] == [delivery]
    event(e, delivery, "pick_up", kunle, k_shift, at="2026-10-21T08:07:00Z")
    assert bodies(outbox)[-1] == P + "Jumia parcel is on its way to you from Main Gate on the estate shuttle."

    # Flagged down on the street: the ride and its pickup arrive together.
    flag = str(uuid.uuid4())
    r = client.post("/v1/device/sync", headers=e.dev, json={
        "rides": [{"id": flag, "kind": "resident", "source": "flag", "home_id": e.home_id, "pickup": {"kind": "home", "ref": e.home_id},
                   "dropoff": {"kind": "gate", "ref": e.gate_id}, "guard_id": kunle, "shift_id": k_shift, "at": "2026-10-21T09:00:00Z"}],
        "ride_events": [{"id": str(uuid.uuid4()), "ride_id": flag, "event": "pick_up", "guard_id": kunle, "shift_id": k_shift,
                         "confirmed_by": "rider", "at": "2026-10-21T09:00:30Z"}]}).json()
    assert flag in r["accepted"] and not r["rejected"]
    assert client.get(f"/v1/admin/rides/{flag}", headers=e.admin).json()["state"] == "picked_up"

    # Only riders take rides.
    open_ride = str(uuid.uuid4())
    client.post("/v1/device/sync", headers=e.dev, json={"rides": [
        {"id": open_ride, "kind": "guest", "source": "gate", "home_id": e.home_id, "passenger": "Tunde",
         "pickup": {"kind": "gate", "ref": e.gate_id}, "dropoff": {"kind": "home", "ref": e.home_id},
         "guard_id": e.guard_id, "shift_id": guard_shift, "at": "2026-10-21T09:05:00Z"}]})
    _, r = event(e, open_ride, "accept", e.guard_id, guard_shift)
    assert "only a rider" in r["rejected"][0]["reason"]


def test_cards_are_issued_by_the_cso_and_revoked_in_the_dashboard(owner, outbox, at):
    e = with_shuttle(owner)
    cso = add_person(e, "Mr Bello", role="cso")
    uid = "04:A2:1B:7C:55:80"
    h = shuttle.card_hash(uuid.UUID(e.id), uid)
    assert h == hashlib.sha256(f"gatelog-card-v1|{e.id}|04A21B7C5580".encode()).hexdigest()
    card = {"id": str(uuid.uuid4()), "resident_id": e.resident_id, "uid_hash": h, "uid_last4": "5580", "at": "2026-10-21T08:00:00Z"}
    bad = client.post("/v1/device/sync", headers=e.dev, json={"cards": [card | {"guard_id": e.guard_id}]}).json()
    assert bad["rejected"][0]["reason"] == "only the CSO issues estate cards"
    ok = client.post("/v1/device/sync", headers=e.dev, json={"cards": [card | {"id": str(uuid.uuid4()), "guard_id": cso}]}).json()
    assert len(ok["accepted"]) == 1
    again = client.post("/v1/device/sync", headers=e.dev, json={"cards": [card | {"id": str(uuid.uuid4()), "guard_id": cso}]}).json()
    assert "already Mrs Adeyemi's" in again["rejected"][0]["reason"]
    assert state(e)["shuttle"]["cards"][0]["uid_hash"] == h

    listed = client.get(f"/v1/admin/cards?home_id={e.home_id}", headers=e.admin).json()[0]
    assert listed["resident"] == "Mrs Adeyemi" and listed["issued_by"] == "Mr Bello"
    client.post(f"/v1/admin/cards/{listed['id']}/revoke", headers=e.admin)
    assert state(e)["shuttle"]["cards"] == []


def _pbkdf2_matches(stored: str, code: str) -> bool:
    _, iterations, salt, digest = stored.split("$")
    return hashlib.pbkdf2_hmac("sha256", code.encode(), base64.b64decode(salt), int(iterations)) == base64.b64decode(digest)


def test_house_code_by_message_and_from_the_dashboard(owner, outbox, at):
    e = with_shuttle(owner)
    sms_in(PHONE, "HOUSE CODE")
    code = re.search(r"home PIN is (\d{4})", bodies(outbox)[-1]).group(1)
    home = next(h for h in state(e)["homes"] if h["id"] == e.home_id)
    assert _pbkdf2_matches(home["house_code_hash"], code)
    sms_in(PHONE, "house code")
    assert f"home PIN is {code}" in bodies(outbox)[-1]  # the same code until it is changed

    fresh = client.post(f"/v1/admin/homes/{e.home_id}/house-code", headers=e.admin).json()["code"]
    home = next(h for h in state(e)["homes"] if h["id"] == e.home_id)
    assert _pbkdf2_matches(home["house_code_hash"], fresh)
    with owner.connect() as c:
        logged = c.execute(text("SELECT after::text FROM audit_events WHERE action = 'new_house_code'")).scalar()
    assert f'"{fresh}"' not in logged and "house_code_hash" not in logged and "house_code_enc" not in logged


def test_positions_only_from_rider_shifts_and_live_map_by_role(owner, outbox, at):
    e = with_shuttle(owner)
    assert client.put("/v1/admin/map/boundary", headers=e.admin, json={"ring": RING}).status_code == 200
    assert client.put(f"/v1/admin/map/gates/{e.gate_id}", headers=e.admin, json={"lat": 7.5, "lng": 3.39}).status_code == 422
    assert client.put(f"/v1/admin/map/gates/{e.gate_id}", headers=e.admin, json={"lat": 6.6005, "lng": 3.39}).status_code == 200

    guard_shift = open_shift(e, e.guard_id)
    point = {"lat": 6.61, "lng": 3.39, "accuracy_m": 8, "at": "2026-10-21T08:00:30Z"}
    assert client.post("/v1/device/positions", headers=e.dev, json={"shift_id": guard_shift, "points": [point]}).status_code == 403
    kunle, k_shift = rider_shift(e)
    r = client.post("/v1/device/positions", headers=e.dev, json={"shift_id": k_shift, "points": [point, point | {"at": "2026-10-21T08:00:45Z"}]})
    assert r.json() == {"stored": 2}

    live = client.get("/v1/admin/live", headers=e.admin).json()
    bike = live["shuttles"][0]
    assert bike["rider"] == "Kunle Rider" and bike["shuttle"] == "S1" and bike["lat"] == 6.61 and bike["stale"] is False
    gate = live["gates"][0]
    assert gate["lat"] == 6.6005 and gate["on_duty"][0]["guard"] == "Musa Ibrahim"
    assert live["sun"]["is_night"] is False  # 09:00 in Lagos

    treasurer = client.post("/v1/admin/staff", headers=e.admin, json={"email": "t@example.com", "name": "Mrs Treasurer", "role": "treasurer"}).json()
    as_treasurer = bearer(staff_token(uuid.UUID(treasurer["id"]), uuid.UUID(e.id), "treasurer"))
    assert client.get("/v1/admin/live", headers=as_treasurer).json()["shuttles"] is None

    at(21, 21, 0)
    assert client.get("/v1/admin/live", headers=e.admin).json()["sun"]["is_night"] is True
    at(29, 9, 0)  # 8 days later: positions are gone
    client.post("/internal/jobs/tick")
    with owner.connect() as c:
        assert c.execute(text("SELECT count(*) FROM positions")).scalar() == 0


def test_ending_a_rider_shift_hands_rides_back_and_stale_rides_close(owner, outbox, at):
    e = with_shuttle(owner)
    sms_in(PHONE, "ride to gate")
    ride = state(e)["shuttle"]["rides"][0]
    kunle, k_shift = rider_shift(e)
    event(e, ride["id"], "accept", kunle, k_shift)
    client.post("/v1/device/sync", headers=e.dev, json={"shifts": [
        {"id": k_shift, "guard_id": kunle, "started_at": "2026-10-21T08:00:00Z", "shuttle_id": e.bike,
         "ended_at": "2026-10-21T08:30:00Z", "end_reason": "ended"}]})
    assert state(e)["shuttle"]["rides"][0]["state"] == "requested"

    at(21, 16, 0)  # 7 hours after it was wanted, never picked up
    client.post("/internal/jobs/tick")
    assert client.get("/v1/admin/rides", headers=e.admin).json()[0]["state"] == "cancelled"


def test_sun_times_in_lagos():
    from datetime import date

    from app import sun

    rise, set_ = sun.times(date(2026, 10, 21), 6.6, 3.39)
    # Lagos in late October: sunrise about 06:50 and sunset about 18:45 local (UTC+1).
    assert (rise.hour, set_.hour) == (5, 17)
