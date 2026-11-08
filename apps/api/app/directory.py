"""Emergency directory: one list per estate, merged from the estate tier and the state/LGA
tier. Accuracy is the product: every number carries a last-verified date, a reported dead
number stays visible (a flaky line beats none in a fire) but is flagged, and whoever owns
the tier is asked to re-test it within 48 hours."""

import logging
from datetime import timedelta
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from . import clock, db, email
from .config import get_settings
from .models import DirectoryEntry, DirectoryReport, Estate, StaffUser

log = logging.getLogger("gatelog.directory")

CATEGORY_ORDER = ["estate", "crime", "fire", "medical", "utilities"]
CATEGORY_LABEL = {"estate": "Estate", "crime": "Crime", "fire": "Fire", "medical": "Medical", "utilities": "Utilities"}
REPORT_WINDOW = timedelta(days=7)
REPORTS_TO_FLAG = 2
VERIFY_EVERY = timedelta(days=92)  # quarterly


def entries(s: Session) -> list[DirectoryEntry]:
    """Every live number this estate can see (RLS limits the state tier to its state/LGA)."""
    rows = s.scalars(select(DirectoryEntry).where(DirectoryEntry.active.is_(True))).all()
    return sorted(rows, key=lambda e: (CATEGORY_ORDER.index(e.category), e.rank, e.name))


def top_five(s: Session) -> list[DirectoryEntry]:
    return sorted(entries(s), key=lambda e: (e.rank, CATEGORY_ORDER.index(e.category), e.name))[:5]


def as_text(rows: list[DirectoryEntry]) -> str:
    lines = [f"{e.name}: {e.number}" + (" (reported not working)" if e.reported_not_working_at else "") for e in rows]
    return "Emergency numbers:\n" + "\n".join(lines) if lines else "Your estate has not added its emergency numbers yet."


def overdue(e: DirectoryEntry) -> bool:
    return e.verified_at is None or clock.now() - e.verified_at > VERIFY_EVERY


def report(estate_id: UUID, entry_id: UUID, reporter: str) -> bool:
    """'This number didn't work'. Returns True if this report flagged the number. It takes two
    different people: one person tapping twice is one report."""
    with db.session(estate_id) as s:
        entry = s.get(DirectoryEntry, entry_id)
        if entry is None:  # not visible to this estate
            raise LookupError("no such number")
        s.add(DirectoryReport(entry_id=entry_id, estate_id=estate_id, reporter=reporter, at=clock.now()))

    # Count across every estate that can see the number (state-tier numbers are shared).
    with db.session(ops=True) as s:
        entry = s.get(DirectoryEntry, entry_id, with_for_update=True)
        recent = s.scalar(
            select(func.count(func.distinct(DirectoryReport.reporter))).where(
                DirectoryReport.entry_id == entry_id,
                DirectoryReport.resolved_at.is_(None),
                DirectoryReport.at > clock.now() - REPORT_WINDOW,
            )
        )
        if recent < REPORTS_TO_FLAG or entry.reported_not_working_at is not None:
            return False
        entry.reported_not_working_at = clock.now()
        owners = _owners(s, entry)
        name, number, where = entry.name, entry.number, _where(s, entry)
    for to in owners:
        _send_quietly(
            to,
            f"Re-test within 48 hours: {name}",
            f"{name} ({number}) on the {where} emergency list has been reported not working twice in 7 days.\n"
            "It still shows, marked 'reported not working'. Please dial it, then mark it verified or replace it "
            "in the Gatelog dashboard within 48 hours.",
        )
    return True


def _send_quietly(to: str, subject: str, body: str) -> None:
    """The flag is already saved and shows on every list; a failed email must not undo the report."""
    try:
        email.send(to, subject, body)
    except Exception as exc:
        log.error("directory alert email failed err=%s", type(exc).__name__)


def _owners(s: Session, entry: DirectoryEntry) -> list[str]:
    if entry.scope == "estate":
        return list(s.scalars(select(StaffUser.email).where(StaffUser.estate_id == entry.estate_id, StaffUser.role == "admin", StaffUser.active.is_(True))))
    ops = get_settings().ops_email
    return [ops] if ops else []


def _where(s: Session, entry: DirectoryEntry) -> str:
    if entry.scope == "estate":
        estate = s.get(Estate, entry.estate_id)
        return estate.name if estate else "estate"
    return f"{entry.lga}, {entry.state}" if entry.lga else str(entry.state)


def mark_verified(s: Session, entry: DirectoryEntry, by: str, note: str | None) -> None:
    entry.verified_at, entry.verified_by, entry.verification_note = clock.now(), by, note
    entry.reported_not_working_at = None
    for r in s.scalars(select(DirectoryReport).where(DirectoryReport.entry_id == entry.id, DirectoryReport.resolved_at.is_(None))):
        r.resolved_at = clock.now()
