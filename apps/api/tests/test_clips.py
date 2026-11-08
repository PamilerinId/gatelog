"""Visitors' names spoken at the gate: upload, audited playback, typing the name, 7-day deletion."""

import uuid

from sqlalchemy import text

from app import shifts
from app.auth import staff_token
from tests.helpers import bearer, client, make_estate

CLIP = b"\x00\x00\x00\x18ftypM4A " + b"\x01" * 2000


def upload(e, clip_id, data=CLIP, ctype="audio/mp4"):
    return client.put(f"/v1/device/clips/{clip_id}", headers=e.dev | {"Content-Type": ctype}, content=data)


def test_a_spoken_name_is_stored_encrypted_played_with_audit_and_named_later(owner, outbox, at, tmp_path, monkeypatch):
    monkeypatch.setattr(shifts.storage.get_settings(), "storage_dir", str(tmp_path))
    shifts.storage.store.cache_clear()
    e = make_estate(owner)
    clip_id = str(uuid.uuid4())
    assert upload(e, clip_id, ctype="text/plain").status_code == 415
    assert upload(e, clip_id, data=b"\x00" * (301 * 1024)).status_code == 413
    assert upload(e, clip_id).status_code == 204
    assert upload(e, clip_id).status_code == 204  # a retry is fine
    stored = next(tmp_path.rglob("*.enc")).read_bytes()
    assert CLIP not in stored

    entry_id = str(uuid.uuid4())
    client.post("/v1/device/sync", headers=e.dev, json={"entries": [
        {"id": entry_id, "home_id": e.home_id, "guest_name": "Voice clip", "name_clip_id": clip_id, "method": "callback_confirmed",
         "guard_id": e.guard_id, "at": "2026-10-21T07:30:00Z"}]})
    row = next(x for x in client.get("/v1/admin/entries", headers=e.admin).json() if x["id"] == entry_id)
    assert row["guest_name"] == "Voice clip" and row["name_clip_id"] == clip_id

    played = client.get(f"/v1/admin/clips/{clip_id}", headers=e.admin)
    assert played.status_code == 200 and played.content == CLIP and played.headers["cache-control"] == "no-store"
    committee = client.post("/v1/admin/staff", headers=e.admin, json={"email": "c@example.com", "name": "Chief Committee", "role": "committee"}).json()
    as_committee = bearer(staff_token(uuid.UUID(committee["id"]), uuid.UUID(e.id), "committee"))
    assert client.get(f"/v1/admin/clips/{clip_id}", headers=as_committee).status_code == 403

    assert client.patch(f"/v1/admin/entries/{entry_id}", headers=e.admin, json={"guest_name": "Tunde Bakare"}).status_code == 200
    visit = next(v for v in client.get("/v1/device/state", headers=e.dev).json()["visits"] if v["entry_id"] == entry_id)
    assert visit["guest_name"] == "Tunde Bakare"  # the gate's Leaving list shows the name now
    with owner.connect() as c:
        assert c.execute(text("SELECT count(*) FROM audit_events WHERE action IN ('play_clip', 'name_entry')")).scalar() == 2

    at(29, 9, 0)  # 8 days later
    client.post("/internal/jobs/tick")
    assert list(tmp_path.rglob("*.enc")) == []
    assert client.get(f"/v1/admin/clips/{clip_id}", headers=e.admin).status_code == 404
