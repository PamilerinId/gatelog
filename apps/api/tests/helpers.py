"""Build an estate through the API the way ops and an admin would."""

import re
import uuid
from dataclasses import dataclass, field

from fastapi.testclient import TestClient
from sqlalchemy import text

from app.auth import staff_token
from app.main import app

client = TestClient(app)


def bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def ops_headers(owner) -> dict:
    with owner.begin() as c:
        ops_id = c.execute(text("INSERT INTO staff_users (id, email, name, role, active, created_at) VALUES (:i, :e, 'Ops', 'ops', true, now()) "
                                "ON CONFLICT (email) DO UPDATE SET name = 'Ops' RETURNING id"),
                           {"i": uuid.uuid4(), "e": "ops@example.com"}).scalar()
    return bearer(staff_token(ops_id, None, "ops"))


@dataclass
class Estate:
    id: str
    admin: dict
    gate_id: str
    home_id: str = ""
    resident_id: str = ""
    number_ids: list[str] = field(default_factory=list)
    guard_id: str = ""
    device: dict = field(default_factory=dict)

    @property
    def dev(self) -> dict:
        return bearer(self.device["token"])


def make_estate(owner, name="Magodo Phase 2", state="Lagos", lga="Kosofe", contact_pref="whatsapp", phone="08031234567", admin_email=None) -> Estate:
    ops = ops_headers(owner)
    admin_email = admin_email or f"admin-{uuid.uuid4().hex[:6]}@example.com"
    r = client.post("/v1/ops/estates", json={"name": name, "state": state, "lga": lga, "admin_email": admin_email, "admin_name": "Mrs Facility"}, headers=ops)
    assert r.status_code == 201, r.text
    estate_id = r.json()["id"]
    with owner.begin() as c:
        admin_id = c.execute(text("SELECT id FROM staff_users WHERE email = :e"), {"e": admin_email}).scalar()
    admin = bearer(staff_token(admin_id, uuid.UUID(estate_id), "admin"))
    gate_id = client.get("/v1/admin/gates", headers=admin).json()[0]["id"]
    e = Estate(estate_id, admin, gate_id)

    zone = client.post("/v1/admin/zones", json={"name": "Block C"}, headers=admin).json()
    street = client.post("/v1/admin/streets", json={"zone_id": zone["id"], "name": "Adeniyi Close"}, headers=admin).json()
    home = client.post("/v1/admin/homes", json={"street_id": street["id"], "label": "14b"}, headers=admin).json()
    e.home_id = home["id"]
    res = client.post("/v1/admin/residents", json={"home_id": home["id"], "name": "Mrs Adeyemi", "contact_pref": contact_pref, "numbers": [phone]}, headers=admin)
    assert res.status_code == 201, res.text
    e.resident_id = res.json()["id"]
    e.number_ids = [n["id"] for n in res.json()["numbers"]]
    e.guard_id = client.post("/v1/admin/guards", json={"name": "Musa Ibrahim"}, headers=admin).json()["id"]
    dev = client.post("/v1/admin/devices", json={"gate_id": gate_id, "label": "Main gate phone"}, headers=admin).json()
    paired = client.post("/v1/device/pair", json={"code": dev["pairing_code"]})
    assert paired.status_code == 200, paired.text
    e.device = paired.json()
    return e


def sms_in(sender: str, body: str):
    r = client.post("/v1/webhooks/sms/test-sms-secret", json={"sender": sender, "message": body})
    assert r.status_code == 200, r.text
    return r


def last_code(outbox) -> str:
    for m in reversed(outbox.sent):
        if m.kind == "gate_code":
            return re.search(r"(\d{3} \d{3})", m.body).group(1).replace(" ", "")
    raise AssertionError("no code sent")


def bodies(outbox) -> list[str]:
    return [m.body for m in outbox.sent]

# Every outbound message starts with the estate's name (one WhatsApp number for all estates).
P = "Magodo Phase 2: "
