"""Core gate flow: announce, code, verify offline, log, notify."""

import base64
import uuid
from datetime import datetime, timedelta, timezone
from uuid import UUID

from app import codes
from tests.helpers import P, bodies, client, last_code, make_estate, sms_in

PHONE = "08031234567"


def offline_verify(state: dict, entered: str) -> dict | None:
    """What the guard app does with no network: recompute each cached visit's code."""
    keys = {k["version"]: base64.b64decode(k["key_b64"]) for k in state["keys"]}
    for v in state["visits"]:
        if not v["code_issued"]:
            continue
        start = datetime.fromtimestamp(v["window_start"], timezone.utc)
        end = datetime.fromtimestamp(v["window_end"], timezone.utc)
        if codes.derive(keys[v["key_version"]], UUID(v["home_id"]), UUID(v["id"]), start, end) == entered:
            return v
    return None


def test_announce_verify_offline_admit_notify(owner, outbox, at):
    e = make_estate(owner, contact_pref="sms")
    sms_in(PHONE, "Tunde, today 4pm, for 2 hours")
    assert "Gate code" in outbox.sent[-1].body and "valid today until 6pm" in outbox.sent[-1].body
    code = last_code(outbox)

    state = client.get("/v1/device/state", headers=e.dev).json()
    visit = offline_verify(state, code)
    assert visit is not None and visit["guest_name"] == "Tunde"
    assert offline_verify(state, "000000" if code != "000000" else "111111") is None
    home = next(h for h in state["homes"] if h["id"] == visit["home_id"])
    assert home["address"] == "14B Adeniyi Close, Block C"

    at(21, 16, 6)
    entry_id = str(uuid.uuid4())
    entry = {"id": entry_id, "home_id": visit["home_id"], "visit_id": visit["id"], "guest_name": "Tunde", "method": "code",
             "guard_id": e.guard_id, "at": datetime(2026, 10, 21, 15, 6, tzinfo=timezone.utc).isoformat()}
    r = client.post("/v1/device/sync", json={"entries": [entry]}, headers=e.dev)
    assert r.json()["accepted"] == [entry_id]
    assert outbox.sent[-1].body == P + "Tunde is in. Main Gate, 16:06."
    assert outbox.sent[-1].channel == "sms"

    # The phone retries the same batch: nothing is duplicated, nobody is told twice.
    n = len(outbox.sent)
    r = client.post("/v1/device/sync", json={"entries": [entry]}, headers=e.dev)
    assert r.json()["duplicates"] == [entry_id] and len(outbox.sent) == n

    # "for 2 hours" counts from the real entry, not from when the resident messaged.
    state = client.get("/v1/device/state", headers=e.dev).json()
    v = next(v for v in state["visits"] if v["id"] == visit["id"])
    assert v["state"] == "inside" and v["expected_until"].startswith("2026-10-21T17:06")

    at(21, 18, 40)
    exit_ = {"id": str(uuid.uuid4()), "visit_id": visit["id"], "method": "code", "at": datetime(2026, 10, 21, 17, 40, tzinfo=timezone.utc).isoformat()}
    client.post("/v1/device/sync", json={"exits": [exit_]}, headers=e.dev)
    # SMS residents get exit notices by default.
    assert outbox.sent[-1].body == P + "Tunde has left. Main Gate, 18:40."
    entries = client.get("/v1/admin/entries", headers=e.admin).json()
    assert entries[0]["method"] == "code" and entries[0]["exit_method"] == "code"


def test_whatsapp_resident_gets_no_exit_notice_by_default(owner, outbox, at):
    e = make_estate(owner, contact_pref="whatsapp")
    sms_in(PHONE, "Ada at 2pm for an hour")
    state = client.get("/v1/device/state", headers=e.dev).json()
    visit = offline_verify(state, last_code(outbox))
    at(21, 14)
    entry_id = str(uuid.uuid4())
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [{"id": entry_id, "home_id": visit["home_id"], "visit_id": visit["id"], "guest_name": "Ada", "method": "code", "at": "2026-10-21T13:00:00Z"}]})
    n = len(outbox.sent)
    client.post("/v1/device/sync", headers=e.dev, json={"exits": [{"id": str(uuid.uuid4()), "entry_id": entry_id, "method": "list_tap", "at": "2026-10-21T13:50:00Z"}]})
    assert len(outbox.sent) == n


def test_exit_without_entry_is_logged_and_flagged(owner, outbox, at):
    e = make_estate(owner)
    r = client.post("/v1/device/sync", headers=e.dev, json={"exits": [{"id": str(uuid.uuid4()), "method": "list_tap", "guest_name": "Unknown man", "at": "2026-10-21T08:00:00Z"}]})
    assert len(r.json()["accepted"]) == 1
    assert client.get("/v1/admin/exits/unmatched", headers=e.admin).json()[0]["guest_name"] == "Unknown man"


def test_exit_synced_before_entry_is_matched_later(owner, outbox, at):
    """Two gates: the pedestrian gate's phone syncs the exit before the main gate's entry."""
    e = make_estate(owner)
    sms_in(PHONE, "Kemi today")
    visit = offline_verify(client.get("/v1/device/state", headers=e.dev).json(), last_code(outbox))
    at(21, 12)
    client.post("/v1/device/sync", headers=e.dev, json={"exits": [{"id": str(uuid.uuid4()), "visit_id": visit["id"], "method": "code", "at": "2026-10-21T11:00:00Z"}]})
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [{"id": str(uuid.uuid4()), "home_id": visit["home_id"], "visit_id": visit["id"], "guest_name": "Kemi", "method": "code", "at": "2026-10-21T10:00:00Z"}]})
    assert client.get("/v1/admin/exits/unmatched", headers=e.admin).json() == []
    assert client.get("/v1/admin/visits?state=left", headers=e.admin).json()[0]["guest_name"] == "Kemi"


def test_cancel_and_unknown_and_help(owner, outbox, at):
    e = make_estate(owner)
    sms_in(PHONE, "Bayo tomorrow 10am")
    code = last_code(outbox)
    sms_in(PHONE, "CANCEL")
    assert f"{code[:3]} {code[3:]}" in outbox.sent[-1].body and "no longer works" in outbox.sent[-1].body
    assert offline_verify(client.get("/v1/device/state", headers=e.dev).json(), code) is None
    sms_in(PHONE, "hello, are you there?")
    assert "send their name and when they are coming" in outbox.sent[-1].body
    n = len(outbox.sent)
    sms_in("08099999999", "Tunde today")  # not registered, by SMS: no reply (costs money, invites abuse)
    assert len(outbox.sent) == n


def test_sos_in_phase_1_says_nobody_was_alerted(owner, outbox, at):
    e = make_estate(owner)
    client.post("/v1/admin/directory", headers=e.admin, json={"category": "estate", "name": "Gate line", "number": "08030000001", "rank": 1})
    sms_in(PHONE, "SOS")
    body = outbox.sent[-1].body
    assert "has NOT alerted anyone" in body and "Gate line: 08030000001" in body
    assert "—" not in body  # no em dashes in user-facing copy
    assert client.get("/v1/admin/visits", headers=e.admin).json() == []


def test_codes_are_unique_among_open_visits(owner, outbox, at):
    e = make_estate(owner)
    names = [f"{a} {b}" for a in ("Tunde", "Ada", "Chidi", "Ngozi", "Bayo", "Kemi") for b in ("Okafor", "Bello", "Eze", "Adeyemi", "Musa")]
    for i, name in enumerate(names):
        at(21, 9 + i // 10, 0)  # stay under the inbound burst limit (20 per 10 minutes)
        sms_in(PHONE, f"{name} today")
    state = client.get("/v1/device/state", headers=e.dev).json()
    keys = {k["version"]: base64.b64decode(k["key_b64"]) for k in state["keys"]}
    issued = [
        codes.derive(keys[v["key_version"]], UUID(v["home_id"]), UUID(v["id"]),
                     datetime.fromtimestamp(v["window_start"], timezone.utc), datetime.fromtimestamp(v["window_end"], timezone.utc))
        for v in state["visits"]
    ]
    assert len(issued) == 30 and len(set(issued)) == 30


def test_device_clock_in_the_future_is_clamped(owner, outbox, at):
    e = make_estate(owner)
    future = (datetime(2026, 10, 21, 8, 0, tzinfo=timezone.utc) + timedelta(days=2)).isoformat()
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [{"id": str(uuid.uuid4()), "home_id": e.home_id, "guest_name": "Walk in", "method": "refused", "at": future}]})
    assert client.get("/v1/admin/entries", headers=e.admin).json()[0]["at"].startswith("2026-10-21T08:00")


def test_state_etag(owner, outbox, at):
    e = make_estate(owner)
    r = client.get("/v1/device/state", headers=e.dev)
    again = client.get("/v1/device/state", headers=e.dev | {"If-None-Match": r.headers["ETag"]})
    assert again.status_code == 304
    sms_in(PHONE, "Tunde today")
    changed = client.get("/v1/device/state", headers=e.dev | {"If-None-Match": r.headers["ETag"]})
    assert changed.status_code == 200
    assert bodies(outbox)
