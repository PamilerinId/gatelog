"""Visitor and plate photos at the gate, and walk-ins the CSO decided alone."""

import uuid

from sqlalchemy import text

from app import shifts
from app.auth import staff_token
from tests.helpers import bearer, client, make_estate
from tests.test_shifts_cso import add_person

JPEG = b"\xff\xd8\xff\xe0" + b"\x02" * 800


def test_photos_are_encrypted_viewed_with_audit_and_deleted_after_30_days(owner, outbox, at, tmp_path, monkeypatch):
    monkeypatch.setattr(shifts.storage.get_settings(), "storage_dir", str(tmp_path))
    shifts.storage.store.cache_clear()
    e = make_estate(owner)
    assert client.get("/v1/device/state", headers=e.dev).json()["estate"]["visitor_photos"] == "phone_entries"
    client.patch("/v1/admin/estate/settings", headers=e.admin, json={"visitor_photos": "all"})
    assert client.get("/v1/device/state", headers=e.dev).json()["estate"]["visitor_photos"] == "all"

    face, plate = str(uuid.uuid4()), str(uuid.uuid4())
    assert client.put(f"/v1/device/photos/{face}", headers=e.dev, content=b"not a jpeg").status_code == 415
    assert client.put(f"/v1/device/photos/{face}?kind=visitor", headers=e.dev, content=JPEG).status_code == 204
    assert client.put(f"/v1/device/photos/{plate}?kind=plate", headers=e.dev, content=JPEG).status_code == 204
    assert client.put(f"/v1/device/photos/{plate}?kind=plate", headers=e.dev, content=JPEG).status_code == 204  # retry
    assert all(JPEG not in f.read_bytes() for f in tmp_path.rglob("*.enc"))

    entry_id = str(uuid.uuid4())
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        {"id": entry_id, "home_id": e.home_id, "guest_name": "Tunde", "method": "callback_confirmed", "plate": "KJA 456 XY",
         "visitor_photo_id": face, "plate_photo_id": plate, "guard_id": e.guard_id, "at": "2026-10-21T07:30:00Z"}]})
    row = next(x for x in client.get("/v1/admin/entries", headers=e.admin).json() if x["id"] == entry_id)
    assert row["visitor_photo_id"] == face and row["plate_photo_id"] == plate and row["plate"] == "KJA456XY"

    seen = client.get(f"/v1/admin/photos/{face}", headers=e.admin)
    assert seen.status_code == 200 and seen.content == JPEG and seen.headers["cache-control"] == "no-store"
    committee = client.post("/v1/admin/staff", headers=e.admin, json={"email": "c@example.com", "name": "Chief Committee", "role": "committee"}).json()
    assert client.get(f"/v1/admin/photos/{face}", headers=bearer(staff_token(uuid.UUID(committee["id"]), uuid.UUID(e.id), "committee"))).status_code == 403
    with owner.connect() as c:
        assert c.execute(text("SELECT count(*) FROM audit_events WHERE action = 'view_photo'")).scalar() == 1

    at(21, 9, 0, month=11)  # 31 days later
    client.post("/internal/jobs/tick")
    assert list(tmp_path.rglob("*.enc")) == []
    assert client.get(f"/v1/admin/photos/{face}", headers=e.admin).status_code == 404


def test_skipped_photo_is_recorded_and_a_cso_on_the_gate_deciding_alone_is_flagged(owner, outbox, at):
    e = make_estate(owner)
    cso = add_person(e, "Mr Bello", role="cso")
    other = add_person(e, "Musa Two")
    alone, checked = str(uuid.uuid4()), str(uuid.uuid4())
    base = {"home_id": e.home_id, "guest_name": "Electrician", "method": "walk_in_admitted", "decided_by": cso, "reason": "Known to the CSO",
            "at": "2026-10-21T07:30:00Z"}
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        base | {"id": alone, "guard_id": cso, "photo_skipped": "refused"},
        base | {"id": checked, "guard_id": other}]})
    rows = {x["id"]: x for x in client.get("/v1/admin/entries", headers=e.admin).json()}
    assert rows[alone]["decided_alone"] is True and rows[alone]["photo_skipped"] == "refused"
    assert rows[checked]["decided_alone"] is False
