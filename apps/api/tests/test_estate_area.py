"""The estate admin corrects the estate's name and area; emergency numbers follow the area."""

import uuid

from sqlalchemy import text

from app.auth import staff_token
from tests.helpers import bearer, client, make_estate, ops_headers


def _police(ops, lga: str) -> dict:
    n = client.post("/v1/ops/directory", headers=ops, json={"scope": "lga", "state": "Lagos", "lga": lga, "category": "crime",
                                                           "name": f"Police, {lga}", "number": "08012345678", "rank": 5}).json()
    client.post(f"/v1/ops/directory/{n['id']}/test-call", headers=ops, json={"answered_by": "Desk sergeant answered"})
    return n


def test_admin_corrects_the_area_and_the_numbers_follow(owner, outbox, at):
    e = make_estate(owner, state="Lagos", lga="Eti-Osa")
    other = make_estate(owner, name="Other Estate", state="Lagos", lga="Eti-Osa", phone="08039999999")
    ops = ops_headers(owner)
    _police(ops, "Kosofe")
    assert client.get("/v1/admin/directory", headers=e.admin).json() == []

    r = client.patch("/v1/admin/estate", headers=e.admin, json={"name": "  Magodo   Phase 2 ", "state": "Lagos", "lga": "Kosofe"})
    assert r.status_code == 200, r.text
    assert (r.json()["name"], r.json()["state"], r.json()["lga"]) == ("Magodo Phase 2", "Lagos", "Kosofe")
    assert [d["name"] for d in client.get("/v1/admin/directory", headers=e.admin).json()] == ["Police, Kosofe"]

    # Only this estate changed, and the change is audited with who made it.
    assert client.get("/v1/admin/estate", headers=other.admin).json()["lga"] == "Eti-Osa"
    with owner.begin() as c:
        row = c.execute(text("SELECT action, before->>'lga', after->>'lga' FROM audit_events WHERE estate_id = :e AND entity = 'estates' "
                             "ORDER BY at DESC LIMIT 1"), {"e": e.id}).one()
    assert tuple(row) == ("update", "Eti-Osa", "Kosofe")


def test_area_rules(owner, outbox, at):
    e = make_estate(owner)
    # The state is one of the 36 and the FCT, spelled one way, so state numbers always match.
    assert client.patch("/v1/admin/estate", headers=e.admin, json={"state": "Lagos State"}).status_code == 422
    assert client.patch("/v1/admin/estate", headers=e.admin, json={"lga": "K"}).status_code == 422
    # Leaving a field out keeps it; a short-name change alone leaves the area alone.
    client.patch("/v1/admin/estate", headers=e.admin, json={"short_name": "MP2"})
    got = client.get("/v1/admin/estate", headers=e.admin).json()
    assert (got["state"], got["lga"], got["short_name"]) == ("Lagos", "Kosofe", "MP2")

    committee = client.post("/v1/admin/staff", headers=e.admin, json={"email": f"c-{uuid.uuid4().hex[:6]}@example.com", "name": "Mr Exco", "role": "committee"}).json()
    as_committee = bearer(staff_token(uuid.UUID(committee["id"]), uuid.UUID(e.id), "committee"))
    assert client.patch("/v1/admin/estate", headers=as_committee, json={"lga": "Ikeja"}).status_code == 403

    ops = ops_headers(owner)
    bad = client.post("/v1/ops/estates", headers=ops, json={"name": "Typo Estate", "state": "lagos", "lga": "Ikeja", "admin_email": "t@example.com", "admin_name": "T"})
    assert bad.status_code == 422
