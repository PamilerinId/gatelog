"""Shifts on the gate phone (PIN and selfie), the CSO view, walk-in decisions, plates."""

import base64
import hashlib
import os
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import text

from app import shifts
from app.auth import staff_token
from tests.helpers import P, bearer, client, make_estate, sms_in

PHONE = "08031234567"
# The smallest valid JPEG header is enough: the API checks the magic bytes, not the picture.
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 600


def pin_hash(pin: str, iterations: int = 60_000) -> str:
    salt = os.urandom(16)
    h = hashlib.pbkdf2_hmac("sha256", pin.encode(), salt, iterations)
    return f"pbkdf2-sha256${iterations}${base64.b64encode(salt).decode()}${base64.b64encode(h).decode()}"


def add_person(e, name: str, role: str = "guard", consent: bool = True) -> str:
    r = client.post("/v1/admin/guards", headers=e.admin, json={"name": name, "role": role, "consent_recorded": consent})
    assert r.status_code == 201, r.text
    return r.json()["id"]


def open_shift(e, guard_id: str, at: str = "2026-10-21T06:00:00Z", selfie: bool = True) -> str:
    shift_id = str(uuid.uuid4())
    r = client.post("/v1/device/sync", headers=e.dev, json={
        "pins": [{"guard_id": guard_id, "pin_hash": pin_hash("482913"), "set_at": at}],
        "shifts": [{"id": shift_id, "guard_id": guard_id, "started_at": at, "selfie_taken": selfie}],
    }).json()
    assert shift_id in r["accepted"], r
    return shift_id


def test_pin_hash_format_is_checked():
    assert shifts.valid_pin_hash(pin_hash("1234"))
    assert not shifts.valid_pin_hash(pin_hash("1234", iterations=1000))  # too weak
    assert not shifts.valid_pin_hash("1234")
    assert not shifts.valid_pin_hash("pbkdf2-sha256$60000$c2FsdA==$aGFzaA==")  # short salt and hash


def test_shift_opens_with_pin_and_selfie_and_records_carry_it(owner, outbox, at, tmp_path, monkeypatch):
    monkeypatch.setattr(shifts.storage.get_settings(), "storage_dir", str(tmp_path))
    shifts.storage.store.cache_clear()
    e = make_estate(owner)
    musa = add_person(e, "Musa Ibrahim")
    state = client.get("/v1/device/state", headers=e.dev).json()
    me = next(g for g in state["guards"] if g["id"] == musa)
    assert me["role"] == "guard" and me["consent"] is True and me["pin_hash"] is None

    shift_id = open_shift(e, musa)
    state = client.get("/v1/device/state", headers=e.dev).json()
    assert next(g for g in state["guards"] if g["id"] == musa)["pin_hash"].startswith("pbkdf2-sha256$60000$")

    assert client.put(f"/v1/device/shifts/{shift_id}/selfie", headers=e.dev, content=b"not a jpeg").status_code == 415
    assert client.put(f"/v1/device/shifts/{shift_id}/selfie", headers=e.dev, content=JPEG).status_code == 204
    stored = next(tmp_path.rglob("*.enc")).read_bytes()
    assert JPEG not in stored  # encrypted before it reaches storage

    entry_id = str(uuid.uuid4())
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        {"id": entry_id, "home_id": e.home_id, "guest_name": "Walk in", "method": "refused", "guard_id": musa,
         "shift_id": shift_id, "plate": "lnd 123-ab", "reason": "No answer from 14B", "at": "2026-10-21T07:00:00Z"}]})
    logged = client.get("/v1/admin/entries?plate=LND123", headers=e.admin).json()[0]
    assert logged["plate"] == "LND123AB" and logged["shift_id"] == shift_id and logged["reason"] == "No answer from 14B"

    # End with a handover; the end arrives later and is filled in once.
    sunday = add_person(e, "Sunday Etim")
    client.post("/v1/device/sync", headers=e.dev, json={"shifts": [
        {"id": shift_id, "guard_id": musa, "started_at": "2026-10-21T06:00:00Z", "ended_at": "2026-10-21T18:00:00Z",
         "end_reason": "handover", "handed_to": sunday, "handover": {"inside": 2, "unsynced": 0}}]})
    listed = client.get("/v1/admin/shifts", headers=e.admin).json()[0]
    assert listed["guard"] == "Musa Ibrahim" and listed["handed_to"] == "Sunday Etim" and listed["selfie"] == "available"

    pic = client.get(f"/v1/admin/shifts/{shift_id}/selfie", headers=e.admin)
    assert pic.status_code == 200 and pic.content == JPEG and pic.headers["cache-control"] == "no-store"
    with owner.connect() as c:
        assert c.execute(text("SELECT count(*) FROM audit_events WHERE action = 'view_selfie'")).scalar() == 1


def test_selfies_are_deleted_after_30_days_and_stale_shifts_close(owner, outbox, at, tmp_path, monkeypatch):
    monkeypatch.setattr(shifts.storage.get_settings(), "storage_dir", str(tmp_path))
    shifts.storage.store.cache_clear()
    e = make_estate(owner)
    musa = add_person(e, "Musa Ibrahim")
    shift_id = open_shift(e, musa, at="2026-10-21T06:00:00Z")
    client.put(f"/v1/device/shifts/{shift_id}/selfie", headers=e.dev, content=JPEG)

    at(21, 22, 0)  # 15 hours later, never ended
    client.post("/internal/jobs/tick")
    listed = client.get("/v1/admin/shifts", headers=e.admin).json()[0]
    assert listed["end_reason"] == "auto" and listed["ended_at"].startswith("2026-10-21T20:00")

    at(21, 9, 0, month=11)  # 31 days later
    client.post("/internal/jobs/tick")
    assert client.get("/v1/admin/shifts", headers=e.admin).json()[0]["selfie"] == "deleted"
    assert list(tmp_path.rglob("*.enc")) == []
    assert client.get(f"/v1/admin/shifts/{shift_id}/selfie", headers=e.admin).status_code == 404


def test_pin_reset_wins_over_an_older_pin(owner, outbox, at):
    e = make_estate(owner)
    musa = add_person(e, "Musa Ibrahim")
    open_shift(e, musa, at="2026-10-21T06:00:00Z")
    assert client.post(f"/v1/admin/guards/{musa}/reset-pin", headers=e.admin).json()["pin_set"] is False
    stale = client.post("/v1/device/sync", headers=e.dev, json={"pins": [
        {"guard_id": musa, "pin_hash": pin_hash("111111"), "set_at": "2026-10-21T06:30:00Z"}]}).json()
    assert "reset this PIN" in stale["rejected"][0]["reason"]
    fresh = client.post("/v1/device/sync", headers=e.dev, json={"pins": [
        {"guard_id": musa, "pin_hash": pin_hash("222222"), "set_at": "2026-10-21T08:02:00Z"}]}).json()
    assert fresh["accepted"] == [musa]


def test_security_head_can_reset_a_pin_and_it_is_audited(owner, outbox, at):
    e = make_estate(owner)
    musa = add_person(e, "Musa Ibrahim")
    head = client.post("/v1/admin/staff", headers=e.admin, json={"email": "head@example.com", "name": "Sgt Okon", "role": "security_head"}).json()
    committee = client.post("/v1/admin/staff", headers=e.admin, json={"email": "exco@example.com", "name": "Mr Ade", "role": "committee"}).json()
    as_head = bearer(staff_token(uuid.UUID(head["id"]), uuid.UUID(e.id), "security_head"))
    as_committee = bearer(staff_token(uuid.UUID(committee["id"]), uuid.UUID(e.id), "committee"))
    assert client.post(f"/v1/admin/guards/{musa}/reset-pin", headers=as_head).json()["pin_set"] is False
    # Only the estate admin and the security head: the Exco reads, it does not reset.
    assert client.post(f"/v1/admin/guards/{musa}/reset-pin", headers=as_committee).status_code == 403
    with owner.connect() as c:
        actors = c.execute(text("SELECT actor FROM audit_events WHERE action = 'reset_pin'")).scalars().all()
    assert len(actors) == 1 and head["id"] in actors[0]


def test_state_lists_who_is_on_shift(owner, outbox, at):
    e = make_estate(owner)
    musa = add_person(e, "Musa Ibrahim")
    bello = add_person(e, "Mr Bello", role="cso")
    assert client.get("/v1/device/state", headers=e.dev).json()["on_duty"] == []
    open_shift(e, bello, at="2026-10-21T06:00:00Z")
    on = client.get("/v1/device/state", headers=e.dev).json()["on_duty"]
    assert on == [{"guard_id": bello, "gate_id": e.gate_id, "since": "2026-10-21T06:00:00+00:00"}]
    assert musa not in {x["guard_id"] for x in on}


def test_a_shift_belongs_to_the_phone_that_opened_it(owner, outbox, at):
    e = make_estate(owner)
    musa = add_person(e, "Musa Ibrahim")
    shift_id = open_shift(e, musa)
    other = client.post("/v1/admin/devices", headers=e.admin, json={"gate_id": e.gate_id, "label": "Back gate"}).json()
    token = client.post("/v1/device/pair", json={"code": other["pairing_code"]}).json()["token"]
    r = client.post("/v1/device/sync", headers={"Authorization": f"Bearer {token}"}, json={"shifts": [
        {"id": shift_id, "guard_id": musa, "started_at": "2026-10-21T06:00:00Z", "ended_at": "2026-10-21T07:00:00Z"}]}).json()
    assert r["rejected"][0]["reason"] == "that shift belongs to another phone"


def test_walk_in_needs_who_decided_and_why(owner, outbox, at):
    e = make_estate(owner)
    cso = add_person(e, "Mr Bello", role="cso")
    base = {"home_id": e.home_id, "guest_name": "Electrician", "method": "walk_in_admitted", "at": "2026-10-21T07:00:00Z"}
    bad = client.post("/v1/device/sync", headers=e.dev, json={"entries": [{**base, "id": str(uuid.uuid4())}]}).json()
    assert bad["rejected"][0]["reason"] == "a walk-in needs who decided and the reason"
    ok_id = str(uuid.uuid4())
    good = client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        {**base, "id": ok_id, "decided_by": cso, "reason": "Estate electrician, known to the CSO"}]}).json()
    assert good["accepted"] == [ok_id]
    row = client.get("/v1/admin/entries?method=walk_in_admitted", headers=e.admin).json()[0]
    assert row["decided_by"] == "Mr Bello" and row["reason"] == "Estate electrician, known to the CSO"


def test_export_neutralises_formulas_and_counts_walk_ins(owner, outbox, at):
    import io

    from openpyxl import load_workbook

    e = make_estate(owner)
    cso = add_person(e, "Mr Bello", role="cso")
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        {"id": str(uuid.uuid4()), "home_id": e.home_id, "guest_name": "=HYPERLINK(\"http://x\",\"Tunde\")",
         "method": "walk_in_admitted", "decided_by": cso, "reason": "+known plumber", "plate": "kja 456 xy",
         "at": "2026-10-21T07:00:00Z"}]})

    summary = client.get("/v1/reports/summary", headers=e.admin).json()
    assert summary["entries"]["by_method"]["walk_in_admitted"] == 1
    assert summary["entries_by_day"][0]["walk_in_admitted"] == 1

    r = client.get("/v1/reports/export.xlsx", headers=e.admin)
    ws = load_workbook(io.BytesIO(r.content)).active
    header = [c.value for c in ws[1]]
    row = dict(zip(header, (c.value for c in ws[2])))
    assert row["Guest"].startswith("'=") and row["Reason"] == "'+known plumber"
    assert row["Decided by"] == "Mr Bello" and row["Plate"] == "KJA456XY"
    assert ws.cell(2, header.index("Guest") + 1).data_type == "s"  # stored as text, not a formula


def test_cso_view_is_for_the_cso(owner, outbox, at):
    e = make_estate(owner)
    musa = add_person(e, "Musa Ibrahim")
    bello = add_person(e, "Mr Bello", role="cso")
    guard_shift = open_shift(e, musa)
    assert client.get("/v1/device/cso", headers=e.dev | {"X-Shift-Id": guard_shift}).status_code == 403
    assert client.get("/v1/device/cso", headers=e.dev).status_code == 403

    cso_shift = open_shift(e, bello, at="2026-10-21T07:00:00Z")
    sms_in(PHONE, "Tunde today 9am for an hour")
    state = client.get("/v1/device/state", headers=e.dev).json()
    visit = state["visits"][0]
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        {"id": str(uuid.uuid4()), "home_id": visit["home_id"], "visit_id": visit["id"], "guest_name": "Tunde", "method": "code",
         "guard_id": musa, "shift_id": guard_shift, "at": "2026-10-21T08:00:00Z"},
        {"id": str(uuid.uuid4()), "home_id": e.home_id, "guest_name": "Hawker", "method": "refused", "guard_id": musa,
         "shift_id": guard_shift, "reason": "No answer twice", "at": "2026-10-21T08:05:00Z"}]})
    at(21, 11, 0)  # Tunde is past his hour
    view = client.get("/v1/device/cso", headers=e.dev | {"X-Shift-Id": cso_shift}).json()
    assert [o["guest_name"] for o in view["needs"]["overdue"]] == ["Tunde"]
    assert view["needs"]["refused_today"][0]["reason"] == "No answer twice" and view["needs"]["refused_today"][0]["by"] == "Musa Ibrahim"
    assert {d["guard"] for d in view["on_duty"]} == {"Musa Ibrahim", "Mr Bello"}


def test_consent_and_roles_reach_the_phone(owner, outbox, at):
    e = make_estate(owner)
    new = add_person(e, "New Guard", consent=False)
    assert next(g for g in client.get("/v1/device/state", headers=e.dev).json()["guards"] if g["id"] == new)["consent"] is False
    client.patch(f"/v1/admin/guards/{new}", headers=e.admin, json={"consent_recorded": True, "role": "cso"})
    g = next(g for g in client.get("/v1/device/state", headers=e.dev).json()["guards"] if g["id"] == new)
    assert g["consent"] is True and g["role"] == "cso"


def test_registered_vehicles_reach_the_gate(owner, outbox, at):
    e = make_estate(owner)
    client.post(f"/v1/admin/homes/{e.home_id}/vehicles", headers=e.admin, json={"plate": "kja 456 xy", "description": "Black Corolla"})
    assert client.post(f"/v1/admin/homes/{e.home_id}/vehicles", headers=e.admin, json={"plate": "KJA456XY"}).status_code == 409
    home = next(h for h in client.get("/v1/device/state", headers=e.dev).json()["homes"] if h["id"] == e.home_id)
    assert home["vehicles"] == [{"plate": "KJA456XY", "description": "Black Corolla"}]


def test_levy_payer_is_for_the_exco_and_entries_filter_by_several_methods(owner, outbox, at):
    e = make_estate(owner)
    client.patch(f"/v1/admin/homes/{e.home_id}", headers=e.admin, json={"levy_payer": "landlord"})

    def as_role(role: str) -> dict:
        r = client.post("/v1/admin/staff", headers=e.admin, json={"email": f"{role}@example.com", "name": role, "role": role})
        assert r.status_code == 201, r.text
        return bearer(staff_token(uuid.UUID(r.json()["id"]), uuid.UUID(e.id), role))

    assert client.get(f"/v1/admin/homes/{e.home_id}", headers=as_role("treasurer")).json()["levy_payer"] == "landlord"
    assert client.get(f"/v1/admin/homes/{e.home_id}", headers=as_role("security_head")).json()["levy_payer"] is None

    cso = add_person(e, "Mr Bello", role="cso")
    base = {"home_id": e.home_id, "at": "2026-10-21T07:00:00Z"}
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        {**base, "id": str(uuid.uuid4()), "guest_name": "Plumber", "method": "walk_in_admitted", "decided_by": cso, "reason": "Known"},
        {**base, "id": str(uuid.uuid4()), "guest_name": "Hawker", "method": "refused"},
        {**base, "id": str(uuid.uuid4()), "guest_name": "Guest", "method": "callback_confirmed"}]})
    both = client.get("/v1/admin/entries?method=walk_in_admitted,refused", headers=e.admin).json()
    assert {r["guest_name"] for r in both} == {"Plumber", "Hawker"}
    assert client.get("/v1/admin/entries?method=walk_in", headers=e.admin).status_code == 422


def test_walk_ins_show_at_every_gate_and_on_the_night_list(owner, outbox, at):
    e = make_estate(owner)
    cso = add_person(e, "Mr Bello", role="cso")
    entry_id = str(uuid.uuid4())
    sent = len(outbox.sent)
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        {"id": entry_id, "home_id": e.home_id, "guest_name": "Plumber", "method": "walk_in_admitted",
         "decided_by": cso, "reason": "Known to the CSO", "at": "2026-10-21T07:00:00Z"}]})
    visit = next(v for v in client.get("/v1/device/state", headers=e.dev).json()["visits"] if v["entry_id"] == entry_id)
    assert visit["state"] == "inside" and visit["resident_id"] is None
    alerts = [m for m in outbox.sent[sent:] if m.kind == "unverified_entry"]
    assert len(alerts) == 1 and alerts[0].channel == "sms"  # nobody confirmed, so the home is told: a second pair of eyes

    at(21, 22, 5)
    client.post("/internal/jobs/tick")
    rollup = client.get("/v1/device/state", headers=e.dev).json()["rollup"]
    assert [i["guest_name"] for i in rollup["items"]] == ["Plumber"]


def test_a_confirmed_call_is_linked_to_its_visit_later(owner, outbox, at):
    e = make_estate(owner)
    musa = add_person(e, "Musa Ibrahim")
    home = next(h for h in client.get("/v1/device/state", headers=e.dev).json()["homes"] if h["id"] == e.home_id)
    number_id = home["residents"][0]["numbers"][0]["id"]
    call = {"id": str(uuid.uuid4()), "home_id": e.home_id, "number_id": number_id, "outcome": "confirmed",
            "guard_id": musa, "at": "2026-10-21T07:00:00Z"}
    assert client.post("/v1/device/sync", headers=e.dev, json={"callbacks": [call]}).json()["accepted"] == [call["id"]]

    visit = {"id": str(uuid.uuid4()), "home_id": e.home_id, "resident_id": home["residents"][0]["id"], "guest_name": "Tunde",
             "window_start": "2026-10-21T07:00:00Z", "window_end": "2026-10-21T22:59:00Z", "expected_until": "2026-10-21T10:00:00Z",
             "stay_type": "hours", "stay_minutes": 180, "stay_given": True}
    r = client.post("/v1/device/sync", headers=e.dev, json={"visits": [visit], "callbacks": [{**call, "visit_id": visit["id"]}]}).json()
    assert call["id"] in r["duplicates"]
    with owner.connect() as c:
        assert str(c.execute(text("SELECT visit_id FROM callbacks WHERE id = :i"), {"i": call["id"]}).scalar()) == visit["id"]

    # An existing link is never moved.
    other = {**visit, "id": str(uuid.uuid4())}
    client.post("/v1/device/sync", headers=e.dev, json={"visits": [other], "callbacks": [{**call, "visit_id": other["id"]}]})
    with owner.connect() as c:
        assert str(c.execute(text("SELECT visit_id FROM callbacks WHERE id = :i"), {"i": call["id"]}).scalar()) == visit["id"]
