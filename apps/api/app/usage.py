"""Messaging usage for the Exco and treasurer: what was sent this month, against the SMS
allowance in the contract, so the bill is never a surprise. Counts only: no message bodies,
no numbers."""

import calendar
from collections import Counter
from datetime import date, datetime, time

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from . import clock, messaging, visits
from .estate_settings import EstateSettings
from .models import Estate, Home, MessageLog


def month_bounds(estate: Estate, month: date) -> tuple[datetime, datetime]:
    tz = visits.tz(estate)
    start = datetime.combine(month.replace(day=1), time(0), tzinfo=tz)
    days = calendar.monthrange(month.year, month.month)[1]
    end = datetime.combine(date(month.year, month.month, days), time(23, 59, 59), tzinfo=tz)
    return start, end


def report(s: Session, estate: Estate, month: date) -> dict:
    st = EstateSettings.model_validate(estate.settings)
    start, end = month_bounds(estate, month)
    rows = s.execute(
        select(MessageLog.kind, MessageLog.channel, func.count())
        .where(MessageLog.direction == "out", MessageLog.status.in_(("sent", "queued")), MessageLog.created_at >= start, MessageLog.created_at <= end)
        .group_by(MessageLog.kind, MessageLog.channel)
    ).all()
    by_purpose: dict[str, Counter] = {}
    billed_purposes: set[str] = set()
    sms_billable = 0
    for kind, channel, n in rows:
        by_purpose.setdefault(messaging.purpose(kind), Counter())[channel] += n
        if messaging.billable(kind):
            billed_purposes.add(messaging.purpose(kind))
            if channel == "sms":
                sms_billable += n

    homes = s.scalar(select(func.count()).select_from(Home)) or 0
    allowance = st.sms_allowance_per_home * homes if st.sms_allowance_per_home is not None else None
    now = clock.now()
    if start <= now <= end:
        elapsed = max((now - start).total_seconds(), 3600) / (end - start).total_seconds()
        projected = round(sms_billable / elapsed)
    else:
        projected = sms_billable
    overage = None
    if allowance is not None and st.sms_overage_naira is not None:
        overage = round(max(0, projected - allowance) * st.sms_overage_naira, 2)
    return {
        "month": month.strftime("%Y-%m"),
        "by_purpose": [
            {"purpose": p, "whatsapp": c.get("whatsapp", 0), "sms": c.get("sms", 0), "billed": p in billed_purposes}
            for p, c in sorted(by_purpose.items())
        ],
        "sms_counted": sms_billable,
        "sms_allowance": allowance,
        "sms_projected": projected,
        "projected_overage_naira": overage,
        "allowance_used": round(projected / allowance, 3) if allowance else None,
        "note": "SOS, emergency-number and gate safety messages are shown but never counted or billed.",
    }
