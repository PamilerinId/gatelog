"""Bulk import of the estate's existing register (CSV or Excel), staged for review.

Upload -> every row is parsed and checked, nothing is written -> the admin reviews errors and
what will be created -> commit. Phone numbers in staged rows are encrypted like everywhere
else and shown as last four digits.

Columns (headers are matched loosely, order does not matter):
    zone / block       street / close / court   house / home / flat
    resident / name    phone (up to 3, separated by / or ;)
    contact (whatsapp, sms or call)              callback (yes / no)
"""

import csv
import io
import re
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, UploadFile
from sqlalchemy import select

from .. import audit, clock, db, phones, push
from ..auth import Staff, require
from ..models import Home, ImportBatch, Resident, Street, Zone
from .admin import MAX_NUMBERS_PER_HOME, add_number

router = APIRouter(prefix="/v1/admin/imports", tags=["estate admin"])
admin = require("admin")

MAX_BYTES = 2 * 1024 * 1024
MAX_ROWS = 5000

ALIASES = {
    "zone": ("zone", "block", "phase", "block/zone", "zone/block"),
    "street": ("street", "close", "court", "road", "avenue", "crescent", "street/court"),
    "house": ("house", "home", "flat", "unit", "house number", "house no", "house no.", "plot"),
    "resident": ("resident", "name", "resident name", "occupant", "owner"),
    "phone": ("phone", "phones", "phone number", "phone numbers", "number", "numbers", "mobile", "gsm"),
    "contact": ("contact", "contact pref", "contact_pref", "prefers", "preference"),
    "callback": ("callback", "callback required", "callback_required", "call back"),
}


def _header_map(headers: list[str]) -> dict[str, int]:
    found = {}
    for i, h in enumerate(headers):
        key = re.sub(r"\s+", " ", (h or "").strip().lower())
        for field, names in ALIASES.items():
            if key in names and field not in found:
                found[field] = i
    return found


def _read(file: UploadFile, raw: bytes) -> list[list[str]]:
    name = (file.filename or "").lower()
    if name.endswith((".xlsx", ".xlsm")):
        from openpyxl import load_workbook

        ws = load_workbook(io.BytesIO(raw), read_only=True, data_only=True).active
        return [["" if c is None else str(c).strip() for c in row] for row in ws.iter_rows(values_only=True)]
    text = raw.decode("utf-8-sig", errors="replace")
    return [[c.strip() for c in row] for row in csv.reader(io.StringIO(text))]


def _parse_rows(table: list[list[str]]) -> list[dict]:
    if not table:
        raise HTTPException(422, "The file is empty.")
    cols = _header_map(table[0])
    missing = [f for f in ("zone", "street", "house") if f not in cols]
    if missing:
        raise HTTPException(422, f"Missing columns: {', '.join(missing)}. The first row must be headers.")
    rows = []
    for line, raw in enumerate(table[1 : MAX_ROWS + 1], start=2):
        if not any(raw):
            continue
        cell = lambda f: raw[cols[f]].strip() if f in cols and cols[f] < len(raw) else ""  # noqa: E731
        row = {"line": line, "zone": cell("zone"), "street": cell("street"), "house": cell("house").upper(),
               "resident": cell("resident"), "phones": [], "contact_pref": "whatsapp", "callback_required": False,
               "errors": [], "warnings": []}
        for f in ("zone", "street", "house"):
            if not row[f]:
                row["errors"].append(f"{f} is empty")
        for part in [p for p in re.split(r"[/;|]|,(?=\s*(?:\+|0))", cell("phone")) if p.strip()]:
            try:
                e164 = phones.normalise(part)
                row["phones"].append({"enc": phones.encrypt(e164).decode(), "last4": phones.last4(e164)})
            except phones.InvalidPhone:
                row["errors"].append(f"'{part.strip()[:4]}...' is not a phone number")
        if len(row["phones"]) > MAX_NUMBERS_PER_HOME:
            row["errors"].append(f"more than {MAX_NUMBERS_PER_HOME} numbers")
        if row["phones"] and not row["resident"]:
            row["errors"].append("numbers given but no resident name")
        pref = cell("contact").lower()
        if pref:
            if pref in ("whatsapp", "wa", "sms", "text", "call", "phone", "voice"):
                row["contact_pref"] = {"wa": "whatsapp", "text": "sms", "phone": "call", "voice": "call"}.get(pref, pref)
            else:
                row["warnings"].append(f"contact '{pref}' not understood, using whatsapp")
        row["callback_required"] = cell("callback").lower() in ("yes", "y", "true", "1")
        rows.append(row)
    if len(table) - 1 > MAX_ROWS:
        raise HTTPException(422, f"At most {MAX_ROWS} rows per upload. Split the file.")
    return rows


def _public(batch: ImportBatch) -> dict:
    rows = batch.rows.get("rows", [])
    return {
        "id": batch.id, "filename": batch.filename, "status": batch.status, "created_at": batch.created_at,
        "summary": batch.rows.get("summary", {}), "result": batch.rows.get("result"),
        "rows": [
            {k: v for k, v in r.items() if k != "phones"} | {"phones": [f"***{p['last4']}" for p in r["phones"]]}
            for r in rows
        ],
    }


@router.post("", status_code=201)
async def upload(file: UploadFile, staff: Staff = Depends(admin)) -> dict:
    raw = await file.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise HTTPException(413, "File is larger than 2 MB.")
    rows = _parse_rows(_read(file, raw))
    with db.session(staff.estate_id) as s:
        zones = {z.name.lower(): z for z in s.scalars(select(Zone))}
        streets = {(st.zone.name.lower(), st.name.lower()) for st in s.scalars(select(Street))}
        homes = {(h.street.zone.name.lower(), h.street.name.lower(), h.label.lower()) for h in s.scalars(select(Home))}
        ok = [r for r in rows if not r["errors"]]
        summary = {
            "rows": len(rows), "errors": len(rows) - len(ok),
            "new_zones": len({r["zone"].lower() for r in ok} - set(zones)),
            "new_streets": len({(r["zone"].lower(), r["street"].lower()) for r in ok} - streets),
            "new_homes": len({(r["zone"].lower(), r["street"].lower(), r["house"].lower()) for r in ok} - homes),
            "residents": sum(1 for r in ok if r["resident"]),
            "numbers": sum(len(r["phones"]) for r in ok),
        }
        batch = ImportBatch(estate_id=staff.estate_id, filename=(file.filename or "upload")[:200], uploaded_by=staff.id,
                            rows={"rows": rows, "summary": summary})
        s.add(batch)
        s.flush()
        return _public(batch)


@router.get("/{batch_id}")
def get_batch(batch_id: UUID, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        b = s.get(ImportBatch, batch_id)
        if b is None:
            raise HTTPException(404, "no such import")
        return _public(b)


@router.post("/{batch_id}/discard")
def discard(batch_id: UUID, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        b = s.get(ImportBatch, batch_id)
        if b is None:
            raise HTTPException(404, "no such import")
        if b.status != "staged":
            raise HTTPException(409, "only a staged import can be discarded")
        b.status = "discarded"
        b.rows = {"summary": b.rows.get("summary", {})}  # drop the staged numbers
        return _public(b)


@router.post("/{batch_id}/commit")
def commit(batch_id: UUID, bg: BackgroundTasks, staff: Staff = Depends(admin)) -> dict:
    with db.session(staff.estate_id) as s:
        b = s.get(ImportBatch, batch_id, with_for_update=True)
        if b is None:
            raise HTTPException(404, "no such import")
        if b.status != "staged":
            raise HTTPException(409, "only a staged import can be committed")
        zones = {z.name.lower(): z for z in s.scalars(select(Zone))}
        streets = {(st.zone_id, st.name.lower()): st for st in s.scalars(select(Street))}
        homes = {(h.street_id, h.label.lower()): h for h in s.scalars(select(Home))}
        result = {"created": {"zones": 0, "streets": 0, "homes": 0, "residents": 0, "numbers": 0}, "skipped": []}

        def created(obj, kind):
            s.add(obj)
            s.flush()
            audit.record(s, staff.estate_id, f"{staff.actor}:import", "create", obj)
            result["created"][kind] += 1
            return obj

        for r in b.rows["rows"]:
            if r["errors"]:
                continue
            z = zones.get(r["zone"].lower()) or created(Zone(estate_id=staff.estate_id, name=r["zone"]), "zones")
            zones[r["zone"].lower()] = z
            st = streets.get((z.id, r["street"].lower())) or created(Street(estate_id=staff.estate_id, zone_id=z.id, name=r["street"]), "streets")
            streets[(z.id, r["street"].lower())] = st
            h = homes.get((st.id, r["house"].lower())) or created(Home(estate_id=staff.estate_id, street_id=st.id, label=r["house"]), "homes")
            homes[(st.id, r["house"].lower())] = h
            if not r["resident"]:
                continue
            existing = s.scalars(select(Resident).where(Resident.home_id == h.id, Resident.name.ilike(r["resident"]))).first()
            if existing:
                result["skipped"].append({"line": r["line"], "reason": f"{r['resident']} is already registered at {r['house']}"})
                continue
            res = created(Resident(estate_id=staff.estate_id, home_id=h.id, name=r["resident"], contact_pref=r["contact_pref"],
                                   callback_required=r["callback_required"]), "residents")
            for i, p in enumerate(r["phones"]):
                try:
                    add_number(s, staff.estate_id, f"{staff.actor}:import", res, phones.decrypt(p["enc"].encode()), is_primary=i == 0)
                    result["created"]["numbers"] += 1
                except HTTPException as exc:
                    result["skipped"].append({"line": r["line"], "reason": f"***{p['last4']}: {exc.detail}"})
        b.status, b.committed_at = "committed", clock.now()
        b.rows = {"summary": b.rows.get("summary", {}), "result": result}  # drop the staged numbers
        out = _public(b)
    bg.add_task(push.estate_changed, staff.estate_id)
    return out
