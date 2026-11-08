"""Scheduled work, driven by one idempotent tick (Cloud Scheduler, every 5 minutes).

    nudges    a guest passes expected_until -> "Is Tunde still with you?"
    rollup    at the estate's rollup time (10pm) -> list of guests still open past their time,
              to the guard app and the security head
    handover  at the morning handover (7am) -> anything still open on last night's list
              closes as rollup_closed, counted as a missed exit

Each step is safe to run twice: unique constraints (one nudge per visit per expected_until,
one rollup per estate per night) make a repeated tick a no-op, and a missed tick is caught
up by the next one.
"""

import logging
from collections import defaultdict
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import abuse, clock, db, email, messaging, numbers, shifts, shuttle, usage, visits
from .estate_settings import EstateSettings
from .models import Conversation, Entry, Estate, Exit, OverstayNudge, PhoneNumber, Resident, Rollup, RollupItem, StaffUser, Visit

log = logging.getLogger("gatelog.jobs")


def _in_quiet_hours(local: datetime, st: EstateSettings) -> bool:
    t = local.time()
    return t >= st.rollup_time or t < st.handover_time


def send_nudges(s: Session, estate: Estate) -> int:
    st = EstateSettings.model_validate(estate.settings)
    if _in_quiet_hours(visits.local_now(estate), st):
        return 0
    due = s.scalars(
        select(Visit).where(Visit.state.in_(visits.OPEN_STATES), Visit.expected_until < clock.now())
    ).all()
    sent = 0
    for v in due:
        already = s.scalars(select(OverstayNudge).where(OverstayNudge.visit_id == v.id, OverstayNudge.for_until == v.expected_until)).first()
        if already:
            continue
        v.state = "overstay"
        s.add(OverstayNudge(estate_id=estate.id, visit_id=v.id, for_until=v.expected_until, sent_at=clock.now()))
        resident = s.get(Resident, v.resident_id) if v.resident_id else None
        if resident is None:
            continue  # nobody to ask; the rollup lists it
        conv = s.scalars(select(Conversation).where(Conversation.resident_id == resident.id)).first()
        if conv is None:
            conv = Conversation(estate_id=estate.id, resident_id=resident.id)
            s.add(conv)
        conv.awaiting, conv.visit_id = "nudge", v.id
        messaging.to_resident(
            s, estate, resident, "overstay_nudge",
            f"Is {v.guest_name} still with you? Reply 1 staying (until when?), 2 already left.",
            {"guest": v.guest_name},
        )
        sent += 1
    return sent


def run_rollup(s: Session, estate: Estate) -> Rollup | None:
    st = EstateSettings.model_validate(estate.settings)
    local = visits.local_now(estate)
    if local.time() < st.rollup_time:
        return None
    if s.scalars(select(Rollup).where(Rollup.for_date == local.date())).first():
        return None
    open_visits = s.scalars(
        select(Visit).where(Visit.state.in_(visits.OPEN_STATES), Visit.expected_until < clock.now())
    ).all()
    rollup = Rollup(estate_id=estate.id, for_date=local.date(), open_count=len(open_visits), run_at=clock.now())
    s.add(rollup)
    s.flush()
    by_home: dict[str, list[str]] = defaultdict(list)
    tz = visits.tz(estate)
    for v in sorted(open_visits, key=lambda v: v.home.address):
        s.add(RollupItem(estate_id=estate.id, rollup_id=rollup.id, visit_id=v.id))
        entry = s.scalars(select(Entry).where(Entry.visit_id == v.id, Entry.method != "refused").order_by(Entry.at.desc())).first()
        came = f"in {visits.clock_24h(entry.at.astimezone(tz))}" if entry else "entry not logged"
        by_home[v.home.address].append(f"{v.guest_name}, {came}, due {visits.clock_24h(v.expected_until.astimezone(tz))}, resident: {_last_reply_text(s, v, tz)}")

    day = local.strftime("%a %d %b").replace(" 0", " ")
    if open_visits:
        noun = "guest" if len(open_visits) == 1 else "guests"
        lines = [f"Gatelog night list, {day}: {len(open_visits)} {noun} still inside past their time."]
        for home, items in by_home.items():
            lines += [f"{home}: {i}" for i in items]
        summary = "; ".join(f"{home}: {', '.join(i.split(',')[0] for i in items)}" for home, items in by_home.items())
    else:
        lines = [f"Gatelog night list, {day}: no guests past their time."]
        summary = "none"
    body = "\n".join(lines)
    for number in _security_head_numbers(s, estate):
        messaging.queue(
            s, estate.id, number, messaging.channel_for(estate, "whatsapp"), "rollup", body,
            {"count": str(len(open_visits)), "summary": summary},
        )
    return rollup


def _last_reply_text(s: Session, v: Visit, tz) -> str:
    n = s.scalars(select(OverstayNudge).where(OverstayNudge.visit_id == v.id).order_by(OverstayNudge.sent_at.desc())).first()
    if n is None:
        return "not asked"
    if n.reply == "none":
        return "no reply"
    if n.reply == "staying" and n.new_until:
        return f"said staying until {visits.clock_24h(n.new_until.astimezone(tz))}"
    return {"staying": "said staying", "left": "said left"}[n.reply]


def _security_head_numbers(s: Session, estate: Estate) -> list[PhoneNumber]:
    heads = s.scalars(select(StaffUser.id).where(StaffUser.estate_id == estate.id, StaffUser.role == "security_head", StaffUser.active.is_(True))).all()
    if not heads:
        return []
    return list(s.scalars(select(PhoneNumber).where(PhoneNumber.staff_id.in_(heads))))


def run_handover(s: Session, estate: Estate) -> int:
    """Close last night's list at the morning handover. Returns how many were missed exits."""
    st = EstateSettings.model_validate(estate.settings)
    local = visits.local_now(estate)
    if not (st.handover_time <= local.time() < st.rollup_time):
        return 0
    pending = s.scalars(select(Rollup).where(Rollup.handover_at.is_(None), Rollup.for_date < local.date())).all()
    missed = 0
    for rollup in pending:
        closed_before = 0
        for item in s.scalars(select(RollupItem).where(RollupItem.rollup_id == rollup.id)):
            v = s.get(Visit, item.visit_id)
            if v.state in visits.OPEN_STATES:
                entry = s.scalars(select(Entry).where(Entry.visit_id == v.id, Entry.method != "refused").order_by(Entry.at.desc())).first()
                s.add(Exit(estate_id=estate.id, entry_id=entry.id if entry else None, visit_id=v.id, method="rollup_closed", unmatched=entry is None, at=clock.now()))
                v.state, v.closed_at = "rollup_closed", clock.now()
                missed += 1
            else:
                closed_before += 1
        rollup.closed_by_morning, rollup.handover_at = closed_before, clock.now()
    return missed


def tick() -> dict[str, int]:
    totals = {"estates": 0, "nudges": 0, "rollups": 0, "missed_exits": 0, "usage_alerts": 0}
    with db.session(ops=True) as s:
        estate_ids = list(s.scalars(select(Estate.id)))
    for estate_id in estate_ids:
        try:
            with db.session(estate_id) as s:
                estate = s.get(Estate, estate_id)
                totals["nudges"] += send_nudges(s, estate)
                totals["missed_exits"] += run_handover(s, estate)
                totals["rollups"] += 1 if run_rollup(s, estate) else 0
                totals["usage_alerts"] += 1 if usage_alert(s, estate) else 0
            totals["estates"] += 1
        except Exception:  # one estate's bad data must not stop the others' rollups
            log.exception("tick failed estate=%s", estate_id)
    messaging.dispatch()
    abuse.sweep()
    totals |= shifts.housekeeping()
    totals |= shuttle.housekeeping()
    totals |= numbers.housekeeping()
    return totals


USAGE_ALERT_AT = 0.8


def usage_alert(s: Session, estate: Estate) -> bool:
    """Tell the treasurer, once a month, when projected SMS use passes 80% of the allowance."""
    month = visits.local_now(estate).date()
    r = usage.report(s, estate, month)
    if not r["allowance_used"] or r["allowance_used"] < USAGE_ALERT_AT:
        return False
    if not abuse.hit(s, abuse.Limit("usage-alert", 1, timedelta(days=31)), f"{estate.id}:{r['month']}"):
        return False
    treasurers = s.scalars(select(StaffUser.email).where(StaffUser.estate_id == estate.id, StaffUser.role.in_(("treasurer", "admin")), StaffUser.active.is_(True))).all()
    for to in treasurers:
        try:
            email.send(to, f"SMS use at {round(r['allowance_used'] * 100)}% of this month's allowance",
                       f"{estate.name} is projected to send {r['sms_projected']} SMS this month against an allowance of {r['sms_allowance']}. "
                       "See Messaging usage in the Gatelog dashboard for the breakdown.")
        except Exception:
            log.warning("usage alert email failed estate=%s", estate.id)
    return True
