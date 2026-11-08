"""Committee reports (read-mostly). What happened at the gate, split by how people got in,
and whether exits are being captured. Two of these numbers are the spec's kill criteria:

    phone share        admitted entries that were phone-announced or callback-confirmed.
                       Over 40% and not falling after 8 weeks: codes are not being adopted.
    exit capture rate  admitted entries with an exit confirmed at the gate (code or list tap).
                       Under 70% after 4 weeks: fix exit capture before anything reads it.
"""

import io
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import clock, db, directory, usage, visits
from ..auth import Staff, require
from ..models import ENTRY_METHODS, Entry, Estate, Exit, Gate, Guard, Home, Rollup, Visit

router = APIRouter(prefix="/v1/reports", tags=["committee"])
reader = require("admin", "committee", "security_head", "treasurer", "org_admin", "org_viewer")

METHODS = ENTRY_METHODS
GATE_CONFIRMED = ("code", "list_tap")
# A spreadsheet runs a cell starting with one of these as a formula. Guest names arrive by SMS,
# whose sender can be forged, so every text cell in an export is neutralised.
FORMULA_START = ("=", "+", "-", "@", "\t", "\r")


def _text(v: str | None) -> str | None:
    return "'" + v if v and v.startswith(FORMULA_START) else v


def _period(since: datetime | None, until: datetime | None) -> tuple[datetime, datetime]:
    until = until or clock.now()
    return since or until - timedelta(days=30), until


def summary(s: Session, estate: Estate, since: datetime, until: datetime) -> dict:
    tz = visits.tz(estate)
    entries = s.scalars(select(Entry).where(Entry.at >= since, Entry.at < until)).all()
    admitted = [e for e in entries if e.method != "refused"]
    exits = {x.entry_id: x for x in s.scalars(select(Exit).where(Exit.entry_id.in_([e.id for e in admitted])))}
    open_in_time = set(s.scalars(select(Visit.id).where(Visit.state == "inside", Visit.expected_until > clock.now())))
    gates = {g.id: g.name for g in s.scalars(select(Gate))}

    by_day: dict[str, Counter] = defaultdict(Counter)
    for e in entries:
        by_day[e.at.astimezone(tz).date().isoformat()][e.method] += 1
    by_gate = Counter(gates.get(e.gate_id, "?") for e in entries)
    methods = Counter(e.method for e in entries)

    # Guests legitimately still inside are not missed exits yet.
    measurable = [e for e in admitted if e.visit_id not in open_in_time]
    gate_exits = sum(1 for e in measurable if e.id in exits and exits[e.id].method in GATE_CONFIRMED)
    resident_exits = sum(1 for e in measurable if e.id in exits and exits[e.id].method == "resident_confirmed")
    missed = sum(1 for e in measurable if e.id in exits and exits[e.id].method == "rollup_closed")
    phone = methods["phone_announced"] + methods["callback_confirmed"]

    rollups = s.scalars(select(Rollup).where(Rollup.for_date >= since.astimezone(tz).date(), Rollup.for_date <= until.astimezone(tz).date()).order_by(Rollup.for_date)).all()
    entries_dir = directory.entries(s)
    return {
        "since": since, "until": until,
        "entries": {"total": len(entries), "admitted": len(admitted), "by_method": {m: methods[m] for m in METHODS}},
        "entries_by_day": [{"date": d, **{m: c[m] for m in METHODS}} for d, c in sorted(by_day.items())],
        "entries_by_gate": [{"gate": g, "count": n} for g, n in by_gate.most_common()],
        "phone_share": round(phone / len(admitted), 3) if admitted else None,
        "exits": {
            "measurable_entries": len(measurable),
            "gate_confirmed": gate_exits,
            "resident_confirmed": resident_exits,
            "missed": missed,
            "capture_rate": round(gate_exits / len(measurable), 3) if measurable else None,
            "unmatched_exits": len(s.scalars(select(Exit.id).where(Exit.unmatched.is_(True), Exit.at >= since, Exit.at < until)).all()),
        },
        "overstays_by_night": [
            {"date": r.for_date.isoformat(), "open_at_rollup": r.open_count, "closed_by_morning": r.closed_by_morning,
             "missed": None if r.closed_by_morning is None else r.open_count - r.closed_by_morning}
            for r in rollups
        ],
        "directory": {
            "numbers": len(entries_dir),
            "overdue_verification": sum(1 for e in entries_dir if directory.overdue(e)),
            "reported_not_working": sum(1 for e in entries_dir if e.reported_not_working_at),
        },
    }


@router.get("/summary")
def get_summary(since: datetime | None = None, until: datetime | None = None, staff: Staff = Depends(reader)) -> dict:
    with db.session(staff.estate_id) as s:
        return summary(s, s.get(Estate, staff.estate_id), *_period(since, until))


@router.get("/export.xlsx")
def export(
    view: str = Query("entries", pattern="^(entries|summary)$"),
    since: datetime | None = None, until: datetime | None = None, staff: Staff = Depends(reader),
) -> StreamingResponse:
    """Any view as an Excel file for ExCo meetings."""
    from openpyxl import Workbook

    since, until = _period(since, until)
    wb = Workbook()
    ws = wb.active
    with db.session(staff.estate_id) as s:
        estate = s.get(Estate, staff.estate_id)
        tz = visits.tz(estate)
        if view == "entries":
            ws.title = "Entries"
            ws.append(["Date", "Time", "Guest", "Home", "Gate", "Method", "Plate", "Decided by", "Reason", "Exit", "Exit method"])
            rows = s.scalars(select(Entry).where(Entry.at >= since, Entry.at < until).order_by(Entry.at)).all()
            homes = {h.id: h.address for h in s.scalars(select(Home))}
            gates = {g.id: g.name for g in s.scalars(select(Gate))}
            people = {g.id: g.name for g in s.scalars(select(Guard))}
            exits = {x.entry_id: x for x in s.scalars(select(Exit).where(Exit.entry_id.in_([e.id for e in rows])))}
            for e in rows:
                at = e.at.astimezone(tz)
                x = exits.get(e.id)
                ws.append([at.date().isoformat(), at.strftime("%H:%M"), _text(e.guest_name), _text(homes.get(e.home_id)),
                           _text(gates.get(e.gate_id)), e.method, e.plate, _text(people.get(e.decided_by)), _text(e.reason),
                           x.at.astimezone(tz).strftime("%Y-%m-%d %H:%M") if x else "", x.method if x else ""])
        else:
            data = summary(s, estate, since, until)
            ws.title = "Summary"
            ws.append(["Gatelog report", _text(estate.name)])
            ws.append(["From", since.astimezone(tz).strftime("%Y-%m-%d"), "To", until.astimezone(tz).strftime("%Y-%m-%d")])
            ws.append([])
            ws.append(["Entries", data["entries"]["total"]])
            for m, n in data["entries"]["by_method"].items():
                ws.append([f"  {m.replace('_', ' ')}", n])
            ws.append(["Phone share of admitted entries", data["phone_share"]])
            ws.append(["Exit capture rate", data["exits"]["capture_rate"]])
            ws.append(["Missed exits", data["exits"]["missed"]])
            ws.append([])
            ws.append(["Date", *METHODS])
            for d in data["entries_by_day"]:
                ws.append([d["date"], *(d[m] for m in METHODS)])
            ws2 = wb.create_sheet("Night lists")
            ws2.append(["Date", "Open at rollup", "Closed by morning", "Missed"])
            for r in data["overstays_by_night"]:
                ws2.append([r["date"], r["open_at_rollup"], r["closed_by_morning"], r["missed"]])
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    name = f"gatelog-{view}-{since.astimezone(tz).date()}-{until.astimezone(tz).date()}.xlsx"
    return StreamingResponse(buf, media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                             headers={"Content-Disposition": f'attachment; filename="{name}"'})


@router.get("/messaging")
def messaging_usage(month: str | None = Query(None, pattern=r"^\d{4}-\d{2}$"), staff: Staff = Depends(reader)) -> dict:
    """Messages sent this month (or `month=YYYY-MM`) by purpose and channel, against the SMS
    allowance, with a projection to month end. Counts only."""
    with db.session(staff.estate_id) as s:
        estate = s.get(Estate, staff.estate_id)
        if month:
            y, m = month.split("-")
            when = date(int(y), int(m), 1)
        else:
            when = clock.now().astimezone(visits.tz(estate)).date()
        return usage.report(s, estate, when)
