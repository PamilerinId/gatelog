"""Tenant isolation, tested, not assumed (non-negotiable 1 in CLAUDE.md).

Two estates are filled through the real API until estate B has rows in every tenant table.
Then, as estate A:

    catalogue  every table with an estate_id column has RLS and a tenant policy; any other
               table must be on the platform list below, so a new table cannot slip through.
    database   the app role scoped to A sees none of B's rows in any table, cannot update
               them, and sees nothing at all when no estate is set.
    HTTP       every GET route, called by every staff role of A, by an association user
               and by A's gate phone, returns nothing of B's; every route that takes an id
               answers 403 or 404 for B's ids; and afterwards B's data is byte for byte
               unchanged.

A new route or table is covered automatically, or the test fails and says what to add.
"""

import io
import re
import uuid

import pytest
from openpyxl import load_workbook
from sqlalchemy import create_engine, text

from app.auth import staff_token
from app.config import get_settings
from app.main import app
from app.models import TENANT_TABLES
from tests.helpers import bearer, client, last_code, make_estate, ops_headers, sms_in
from tests.test_shifts_cso import add_person, open_shift
from tests.test_shuttle import RING, rider_shift

# Tables with no estate_id, on purpose. estates and directory_entries have their own policies.
PLATFORM_TABLES = {"estates", "organisations", "staff_users", "login_codes", "rate_counters", "inbound_seen", "alembic_version"}
# Has estate_id but no RLS, on purpose: sign-in looks a person up by email before any estate is
# known. Every request re-reads the row and checks its estate (auth.current_staff), and the HTTP
# layer below checks every role, including /v1/admin/staff.
ESTATE_COLUMN_WITHOUT_RLS = {"staff_users"}
SCOPED_TABLES = sorted(set(TENANT_TABLES) | {"directory_entries"})
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 600


def fill(owner, e, tag: str, resident_phone: str, sender: str) -> dict:
    """Use every feature once for estate e, so each tenant table gets at least one row."""
    ids: dict[str, str] = {"estate": e.id, "home": e.home_id, "gate": e.gate_id, "guard": e.guard_id, "resident": e.resident_id}
    a = e.admin
    client.patch("/v1/admin/estate/settings", headers=a, json={"shuttle_enabled": True})
    # Register import (import_batches), a vehicle, a directory number and a report against it.
    csv = f"Block,Street,House No,Resident Name,Phone,Contact,Callback\nZone {tag},Road {tag},1,Resident {tag},{resident_phone},sms,no\n"
    batch = client.post("/v1/admin/imports", headers=a, files={"file": ("r.csv", csv, "text/csv")}).json()
    client.post(f"/v1/admin/imports/{batch['id']}/commit", headers=a)
    ids["batch"] = batch["id"]
    ids["vehicle"] = client.post(f"/v1/admin/homes/{e.home_id}/vehicles", headers=a, json={"plate": f"{tag}123AB"}).json()["id"]
    ids["directory"] = client.post("/v1/admin/directory", headers=a, json={"category": "estate", "name": f"Gate line {tag}", "number": "08030000001"}).json()["id"]
    reg = client.get("/v1/admin/register", headers=a).json()
    ids["zone"], ids["street"] = reg[0]["id"], reg[0]["streets"][0]["id"]
    ids["number"] = client.get(f"/v1/admin/homes/{e.home_id}", headers=a).json()["residents"][0]["numbers"][0]["id"]
    ids["device"] = client.get("/v1/admin/devices", headers=a).json()[0]["id"]
    ids["staff"] = client.post("/v1/admin/staff", headers=a, json={"email": f"head-{tag.lower()}@example.com", "name": f"Head {tag}", "role": "security_head"}).json()["id"]

    # A shift with a selfie, a visit by SMS (conversation, message log), a callback, an entry and an exit.
    shift = open_shift(e, e.guard_id)
    client.put(f"/v1/device/shifts/{shift}/selfie", headers=e.dev, content=JPEG)
    client.post("/v1/device/directory/report", headers=e.dev, json={"entry_id": ids["directory"], "guard_id": e.guard_id})
    ids["shift"] = shift
    sms_in(sender, f"Late {tag} today 9am for an hour")
    sms_in(sender, f"Ade {tag} today 9am")  # no stay given: Gatelog asks, so a conversation row exists
    visits = {v["guest_name"].lower(): v for v in client.get("/v1/device/state", headers=e.dev).json()["visits"]}
    who = {"guard_id": e.guard_id, "shift_id": shift}
    entry_1, entry_2 = str(uuid.uuid4()), str(uuid.uuid4())
    client.post("/v1/device/sync", headers=e.dev, json={
        "callbacks": [{"id": str(uuid.uuid4()), "home_id": e.home_id, "number_id": ids["number"], "outcome": "confirmed", "at": "2026-10-21T08:01:00Z", **who}],
        "entries": [
            {"id": entry_1, "home_id": e.home_id, "visit_id": visits[f"ade {tag.lower()}"]["id"], "guest_name": f"Ade {tag}", "method": "code", "at": "2026-10-21T08:02:00Z", **who},
            {"id": entry_2, "home_id": e.home_id, "visit_id": visits[f"late {tag.lower()}"]["id"], "guest_name": f"Late {tag}", "method": "code", "at": "2026-10-21T08:03:00Z", **who}],
        "exits": [{"id": str(uuid.uuid4()), "method": "list_tap", "entry_id": entry_1, "at": "2026-10-21T08:04:00Z", **who}],
    })
    ids["visit"] = visits[f"late {tag.lower()}"]["id"]
    client.post("/v1/device/sync", headers=e.dev, json={
        "pin_checks": [{"id": str(uuid.uuid4()), "home_id": e.home_id, "ok": False, "at": "2026-10-21T08:04:30Z", **who}],
        "number_offers": [{"id": str(uuid.uuid4()), "resident_id": e.resident_id, "number": resident_phone[:-1] + "9", "at": "2026-10-21T08:04:40Z", **who}],
    })

    # Shuttle and map: boundary, a place, a motorcycle, a card, a ride with an event, positions.
    client.put("/v1/admin/map/boundary", headers=a, json={"ring": RING})
    ids["place"] = client.post("/v1/admin/places", headers=a, json={"name": f"Clubhouse {tag}", "lat": 6.61, "lng": 3.39}).json()["id"]
    e.bike = client.post("/v1/admin/shuttles", headers=a, json={"label": f"S-{tag}"}).json()["id"]
    ids["shuttle"] = e.bike
    cso = add_person(e, f"CSO {tag}", role="cso")
    cso_shift = open_shift(e, cso, at="2026-10-21T07:00:00Z")
    ids["cso_shift"], ids["cso"] = cso_shift, cso
    card = str(uuid.uuid4())
    client.post("/v1/device/sync", headers=e.dev, json={"cards": [
        {"id": card, "resident_id": e.resident_id, "uid_hash": uuid.uuid4().hex * 2, "uid_last4": "AB12", "guard_id": cso, "at": "2026-10-21T08:00:00Z"}]})
    ids["card"] = card
    rider, r_shift = rider_shift(e, f"Rider {tag}")
    ride = str(uuid.uuid4())
    client.post("/v1/device/sync", headers=e.dev, json={
        "rides": [{"id": ride, "kind": "guest", "source": "gate", "home_id": e.home_id, "passenger": f"Guest {tag}",
                   "pickup": {"kind": "gate", "ref": e.gate_id}, "dropoff": {"kind": "home", "ref": e.home_id}, "at": "2026-10-21T08:05:00Z", **who}],
        "ride_events": [{"id": str(uuid.uuid4()), "ride_id": ride, "event": "accept", "guard_id": rider, "shift_id": r_shift, "at": "2026-10-21T08:06:00Z"}]})
    ids["ride"] = ride
    client.post("/v1/device/positions", headers=e.dev, json={"shift_id": r_shift, "points": [{"lat": 6.61, "lng": 3.39, "at": "2026-10-21T08:00:00Z"}]})
    return ids


@pytest.fixture
def estates(owner, outbox, at):
    a = make_estate(owner, name="Estate Alpha", phone="08031234567")
    b = make_estate(owner, name="Estate Zulu", phone="08039999999")
    ida = fill(owner, a, "ALPHA", "08051230001", "08031234567")
    idb = fill(owner, b, "ZULU", "08051230002", "08039999999")
    # Past the hour (nudges), then the night list (rollups, rollup items).
    at(21, 10, 30)
    client.post("/internal/jobs/tick")
    at(21, 22, 5)
    client.post("/internal/jobs/tick")
    return a, b, ida, idb


def _snapshot(owner, estate_id: str) -> dict[str, str]:
    out = {}
    with owner.connect() as c:
        for t in SCOPED_TABLES:
            out[t] = c.execute(text(f"SELECT md5(coalesce(string_agg(x::text, ',' ORDER BY x::text), '')) FROM {t} x WHERE estate_id = :e"), {"e": estate_id}).scalar()
        out["estates"] = c.execute(text("SELECT md5(x::text) FROM estates x WHERE id = :e"), {"e": estate_id}).scalar()
    return out


def test_catalogue_every_estate_table_has_rls_and_a_policy(owner):
    with owner.connect() as c:
        tables = set(c.execute(text("SELECT tablename FROM pg_tables WHERE schemaname = 'public'")).scalars())
        with_estate = set(c.execute(text(
            "SELECT table_name FROM information_schema.columns WHERE table_schema = 'public' AND column_name = 'estate_id'")).scalars())
        rls = dict(c.execute(text("SELECT relname, relrowsecurity FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind = 'r'")).all())
        policies = set(c.execute(text("SELECT tablename FROM pg_policies WHERE schemaname = 'public'")).scalars())
        bypass = c.execute(text("SELECT rolbypassrls OR rolsuper FROM pg_roles WHERE rolname = 'gatelog_app'")).scalar()
        owners = set(c.execute(text("SELECT DISTINCT tableowner FROM pg_tables WHERE schemaname = 'public'")).scalars())
    assert bypass is False, "the app role must not bypass RLS"
    assert "gatelog_app" not in owners, "the app role must not own tables (owners bypass RLS)"
    assert with_estate - ESTATE_COLUMN_WITHOUT_RLS == set(SCOPED_TABLES), f"tables with estate_id vs TENANT_TABLES: {(with_estate - ESTATE_COLUMN_WITHOUT_RLS) ^ set(SCOPED_TABLES)}"
    unprotected = sorted(t for t in (with_estate - ESTATE_COLUMN_WITHOUT_RLS) | {"estates"} if not rls.get(t) or t not in policies)
    assert not unprotected, f"no RLS or no policy: {unprotected}"
    unknown = sorted(tables - with_estate - PLATFORM_TABLES)
    assert not unknown, f"new table with no estate_id: add estate_id and RLS, or list it in PLATFORM_TABLES: {unknown}"


def test_database_estate_a_sees_nothing_of_estate_b(owner, estates):
    a, b, ida, idb = estates
    with owner.connect() as c:
        empty = [t for t in SCOPED_TABLES if not c.execute(text(f"SELECT count(*) FROM {t} WHERE estate_id = :b"), {"b": b.id}).scalar()]
    assert not empty, f"estate B has no rows in {empty}: extend fill() so the test proves something"

    app_engine = create_engine(get_settings().database_url)
    for t in SCOPED_TABLES + ["estates"]:
        col = "id" if t == "estates" else "estate_id"
        with app_engine.connect() as c:
            assert c.execute(text(f"SELECT count(*) FROM {t}")).scalar() == 0, f"{t}: rows visible with no estate set"
            c.rollback()
            c.execute(text("SELECT set_config('app.estate_id', :e, false)"), {"e": a.id})
            assert c.execute(text(f"SELECT count(*) FROM {t} WHERE {col} = :b"), {"b": b.id}).scalar() == 0, f"{t}: A sees B's rows"
            if t != "estates":
                assert c.execute(text(f"SELECT count(*) FROM {t} WHERE {col} = :a"), {"a": a.id}).scalar() > 0, f"{t}: A sees none of its own rows"
            try:
                n = c.execute(text(f"UPDATE {t} SET {col} = {col} WHERE {col} = :b"), {"b": b.id}).rowcount
                assert n == 0, f"{t}: A updated B's rows"
            except Exception as exc:  # append-only tables refuse UPDATE outright: also isolation
                assert "permission denied" in str(exc), exc
            c.rollback()


def _routes() -> dict[str, set[str]]:
    paths = app.openapi()["paths"]
    return {p: {m.upper() for m in ops} for p, ops in paths.items() if p.startswith(("/v1/admin", "/v1/reports", "/v1/device"))}


def _text(r) -> str:
    if r.headers.get("content-type", "").startswith("application/vnd.openxmlformats"):
        wb = load_workbook(io.BytesIO(r.content))
        return " ".join(str(c.value) for ws in wb for row in ws.iter_rows() for c in row if c.value is not None)
    return r.text


# Bodies that pass validation, so a write with B's id reaches the handler and its estate check.
WRITE_BODIES = {
    "/v1/admin/directory/{entry_id}": {"name": "Hijack"},
    "/v1/admin/gates/{gate_id}": {"name": "Hijack"},
    "/v1/admin/guards/{guard_id}": {"name": "Hijack"},
    "/v1/admin/homes/{home_id}": {"label": "Z9"},
    "/v1/admin/homes/{home_id}/vehicles": {"plate": "HIJ123"},
    "/v1/admin/map/gates/{gate_id}": {"lat": None, "lng": None},
    "/v1/admin/map/homes/{home_id}": {"lat": None, "lng": None},
    "/v1/admin/places/{place_id}": {"name": "Hijack"},
    "/v1/admin/residents/{resident_id}": {"name": "Hijack"},
    "/v1/admin/residents/{resident_id}/numbers": {"number": "08051239999"},
    "/v1/admin/shuttles/{shuttle_id}": {"label": "Hijack"},
    "/v1/admin/streets/{street_id}": {"name": "Hijack"},
    "/v1/admin/zones/{zone_id}": {"name": "Hijack"},
}
PARAM_IDS = {
    "card_id": "card", "device_id": "device", "entry_id": "directory", "gate_id": "gate", "guard_id": "guard", "home_id": "home",
    "batch_id": "batch", "number_id": "number", "place_id": "place", "resident_id": "resident", "ride_id": "ride",
    "shift_id": "shift", "shuttle_id": "shuttle", "staff_id": "staff", "street_id": "street", "vehicle_id": "vehicle", "zone_id": "zone",
}


def test_http_every_role_of_estate_a_gets_nothing_of_estate_b(owner, estates):
    a, b, ida, idb = estates
    before = _snapshot(owner, b.id)
    markers = ["ZULU", "Zulu"] + [v for k, v in idb.items() if k != "estate"] + [b.id]

    # Every dashboard role of estate A, plus an association user whose organisation has only A.
    people = {"admin": a.admin}
    for role in ("committee", "security_head", "treasurer"):
        r = client.post("/v1/admin/staff", headers=a.admin, json={"email": f"{role}-alpha@example.com", "name": f"{role} alpha", "role": role}).json()
        people[role] = bearer(staff_token(uuid.UUID(r["id"]), uuid.UUID(a.id), role))
    ops = ops_headers(owner)
    org = client.post("/v1/ops/organisations", headers=ops, json={"name": "Alpha Association", "kind": "association"}).json()
    assert client.put(f"/v1/ops/organisations/{org['id']}/estates/{a.id}", headers=ops).status_code == 204
    for role in ("org_admin", "org_viewer"):
        u = client.post(f"/v1/ops/organisations/{org['id']}/users", headers=ops, json={"email": f"{role}@example.com", "name": f"{role} user", "role": role}).json()
        token = bearer(staff_token(uuid.UUID(u["id"]), None, role))
        people[role] = token | {"X-Estate-Id": a.id}
        assert client.get("/v1/admin/register", headers=token | {"X-Estate-Id": b.id}).status_code == 403

    routes = _routes()
    unmapped = sorted({p for pr in re.findall(r"{(\w+)}", " ".join(routes)) for p in [pr] if p not in PARAM_IDS})
    assert not unmapped, f"new path parameters: add them to PARAM_IDS: {unmapped}"

    checked = {"reads": 0, "ids": 0}
    for path, methods in sorted(routes.items()):
        params = re.findall(r"{(\w+)}", path)
        if path.startswith("/v1/device"):
            continue  # below, with the gate phone's token
        if not params and "GET" in methods:
            for role, headers in people.items():
                r = client.get(path, headers=headers)
                assert r.status_code in (200, 403), f"{role} GET {path}: {r.status_code} {r.text[:200]}"
                body = _text(r)
                leaked = [m for m in markers if m in body]
                assert not leaked, f"{role} GET {path} shows estate B: {leaked[:3]}"
            checked["reads"] += 1
        if params:
            url = path
            for p in params:
                url = url.replace("{" + p + "}", idb[PARAM_IDS[p]])
            for method in sorted(methods):
                kwargs = {"json": WRITE_BODIES.get(path, {})} if method in ("PATCH", "PUT", "POST") else {}
                if path == "/v1/admin/staff/{staff_id}":
                    url_m, kwargs = url + "?active=false", {}
                else:
                    url_m = url
                r = client.request(method, url_m, headers=a.admin, **kwargs)
                assert r.status_code in (403, 404), f"admin {method} {path} with estate B's id: {r.status_code} {r.text[:200]}"
                checked["ids"] += 1
    assert checked["reads"] >= 20 and checked["ids"] >= 30, checked  # the route list really was walked

    # Ids in request bodies: a home, street, zone or gate of estate B.
    for path, body in [
        ("/v1/admin/residents", {"home_id": idb["home"], "name": "Hijack"}),
        ("/v1/admin/streets", {"zone_id": idb["zone"], "name": "Hijack"}),
        ("/v1/admin/homes", {"street_id": idb["street"], "label": "Z9"}),
        ("/v1/admin/devices", {"gate_id": idb["gate"], "label": "Hijack"}),
    ]:
        r = client.post(path, headers=a.admin, json=body)
        assert r.status_code in (403, 404, 409, 422) and r.status_code != 201, f"POST {path} with B's id: {r.status_code} {r.text[:200]}"

    # Estate A's gate phone.
    state = client.get("/v1/device/state", headers=a.dev).text
    assert not [m for m in markers if m in state], "A's gate phone state shows estate B"
    fresh = open_shift(a, ida["cso"], at="2026-10-21T21:00:00Z")  # the earlier one closed itself after 14 hours
    cso = client.get("/v1/device/cso", headers=a.dev | {"X-Shift-Id": fresh})
    assert cso.status_code == 200 and not [m for m in markers if m in cso.text]
    assert client.get("/v1/device/cso", headers=a.dev | {"X-Shift-Id": idb["cso_shift"]}).status_code == 403
    assert client.put(f"/v1/device/shifts/{idb['shift']}/selfie", headers=a.dev, content=JPEG).status_code == 404
    assert client.post("/v1/device/positions", headers=a.dev, json={"shift_id": idb["shift"], "points": []}).status_code == 409
    r = client.post("/v1/device/sync", headers=a.dev, json={"ride_events": [
        {"id": str(uuid.uuid4()), "ride_id": idb["ride"], "event": "cancel", "at": "2026-10-21T21:00:00Z"}]}).json()
    assert r["rejected"], "A's phone changed B's ride"
    r = client.post("/v1/device/directory/report", headers=a.dev, json={"entry_id": idb["directory"]})
    assert r.status_code == 404

    assert _snapshot(owner, b.id) == before, "estate B's data changed while estate A was poking at it"
