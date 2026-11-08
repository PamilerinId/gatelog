"""Integration check helper: build an estate on a running dev API and print what the guard
app's integration test needs. Run from apps/api with its virtualenv:

    cd apps/api
    .venv/Scripts/python ../guard/tool/it_seed.py --reset        # once: (re)create the database
    # start the API against that database (see apps/guard/README.md), then:
    .venv/Scripts/python ../guard/tool/it_seed.py --base http://127.0.0.1:8799

Prints JSON: {"pairing_code", "code", "admin_token", ...}. Musa Ibrahim (guard) and Mr Bello (CSO)
both have consent recorded and no PIN yet; 14B has a registered vehicle, KJA456XY. `code` is the six-digit code of a guest
announced by SMS just now, computed server side, so the app's offline check is compared
against the API's own derivation. Uses the dev key store and a separate database
(gatelog_guard_it); never point it at anything real.
"""

import argparse
import json
import os
import sys
import uuid

DB = "gatelog_guard_it"
os.environ["DATABASE_URL"] = f"postgresql+psycopg://gatelog_app:gatelog_app@localhost:54329/{DB}"
os.environ["DATABASE_OWNER_URL"] = f"postgresql+psycopg://gatelog_owner:gatelog_owner@localhost:54329/{DB}"
os.environ["KEY_STORE"] = "dev"
sys.path.insert(0, os.getcwd())

from sqlalchemy import create_engine, text  # noqa: E402

from app import codes  # noqa: E402
from app.auth import staff_token  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.keys import key_store  # noqa: E402


def reset() -> None:
    from alembic import command
    from alembic.config import Config

    server = create_engine("postgresql+psycopg://gatelog_owner:gatelog_owner@localhost:54329/gatelog", isolation_level="AUTOCOMMIT")
    with server.connect() as c:
        if not c.execute(text("SELECT 1 FROM pg_database WHERE datname = :d"), {"d": DB}).first():
            c.execute(text(f"CREATE DATABASE {DB} OWNER gatelog_owner"))
    owner = create_engine(get_settings().database_owner_url)
    with owner.begin() as c:
        c.execute(text("DROP SCHEMA public CASCADE; CREATE SCHEMA public;"))
    cfg = Config("alembic.ini")
    cfg.set_main_option("script_location", "migrations")
    cfg.attributes["url"] = get_settings().database_owner_url
    command.upgrade(cfg, "head")
    print(f"{DB} migrated")


def seed(base: str) -> None:
    import httpx

    def bearer(t: str) -> dict:
        return {"Authorization": f"Bearer {t}"}

    owner = create_engine(get_settings().database_owner_url)
    with owner.begin() as c:
        ops_id = c.execute(
            text("INSERT INTO staff_users (id, email, name, role, active, created_at) VALUES (:i, 'ops@example.com', 'Ops', 'ops', true, now()) "
                 "ON CONFLICT (email) DO UPDATE SET name = 'Ops' RETURNING id"),
            {"i": uuid.uuid4()},
        ).scalar()
    ops = bearer(staff_token(ops_id, None, "ops"))
    email = f"admin-{uuid.uuid4().hex[:6]}@example.com"
    r = httpx.post(f"{base}/v1/ops/estates", json={"name": "Magodo Phase 2", "state": "Lagos", "lga": "Kosofe", "admin_email": email, "admin_name": "Mrs Facility"}, headers=ops)
    r.raise_for_status()
    estate_id = r.json()["id"]
    with owner.begin() as c:
        admin_id = c.execute(text("SELECT id FROM staff_users WHERE email = :e"), {"e": email}).scalar()
    admin = bearer(staff_token(admin_id, uuid.UUID(estate_id), "admin"))
    gate_id = httpx.get(f"{base}/v1/admin/gates", headers=admin).json()[0]["id"]
    zone = httpx.post(f"{base}/v1/admin/zones", json={"name": "Block C"}, headers=admin).json()
    street = httpx.post(f"{base}/v1/admin/streets", json={"zone_id": zone["id"], "name": "Adeniyi Close"}, headers=admin).json()
    home = httpx.post(f"{base}/v1/admin/homes", json={"street_id": street["id"], "label": "14b"}, headers=admin).json()
    phone = "080" + str(uuid.uuid4().int)[:8]  # a fresh fake number per run
    httpx.post(f"{base}/v1/admin/residents", json={"home_id": home["id"], "name": "Mrs Adeyemi", "contact_pref": "sms", "numbers": [phone]}, headers=admin).raise_for_status()
    guard = httpx.post(f"{base}/v1/admin/guards", json={"name": "Musa Ibrahim", "consent_recorded": True}, headers=admin).json()
    cso = httpx.post(f"{base}/v1/admin/guards", json={"name": "Mr Bello", "role": "cso", "consent_recorded": True}, headers=admin).json()
    httpx.post(f"{base}/v1/admin/homes/{home['id']}/vehicles", json={"plate": "kja 456 xy", "description": "Black Corolla"}, headers=admin).raise_for_status()
    device = httpx.post(f"{base}/v1/admin/devices", json={"gate_id": gate_id, "label": "Main gate phone"}, headers=admin).json()
    httpx.post(f"{base}/v1/webhooks/sms/test-sms-secret", json={"sender": phone, "message": "Tunde, for 2 hours"}).raise_for_status()
    with owner.begin() as c:
        v = c.execute(text("SELECT id, home_id, window_start, window_end, key_version FROM visits WHERE estate_id = :e AND code_issued"), {"e": estate_id}).first()
    code = codes.derive(key_store().get(uuid.UUID(estate_id), v.key_version), v.home_id, v.id, v.window_start, v.window_end) if v else None
    print(json.dumps({"pairing_code": device.get("pairing_code"), "code": code, "guard_id": guard["id"], "cso_id": cso["id"],
                      "estate_id": estate_id, "admin_token": admin["Authorization"].split(" ", 1)[1]}))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--reset", action="store_true")
    p.add_argument("--base", default="http://127.0.0.1:8799")
    a = p.parse_args()
    reset() if a.reset else seed(a.base)
