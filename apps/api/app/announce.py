"""Read a resident's guest announcement.

    "Tunde, today 4pm, for 2 hours"
    "Tunde Bakare is coming tomorrow by 3pm, staying overnight"
    "Expecting Mrs Okafor on Saturday"

Rule-based on purpose: the inputs are short, the vocabulary is small, and a wrong guess at
a gate is worse than asking again. When the name cannot be found we ask; when the stay is
missing we use the estate default and offer the quick options.
"""

import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

from .stay import Stay, at, find_stay, parse_clock, parse_day

_LEADING_FILLER = re.compile(
    r"^(?:(?:hi|hello|hey|good\s+(?:morning|afternoon|evening)|pls|please|kindly|gatelog|guest|visitor|"
    r"expecting|i'?m\s+expecting|i\s+am\s+expecting|i\s+have|my\s+guest|my\s+visitor|announce|new\s+guest)\b[\s,:.\-]*)+",
    re.I,
)
# Where the name stops: the first word that starts the when/how-long part of the message.
_NAME_STOP = re.compile(
    r"\s(?:is|will|would|should|coming|comes|arriving|arrives|visiting|today|tonight|tomorrow|tmrw|tmr|"
    r"at|on|by|around|about|for|till|until|from|this|next|staying|overnight|between|"
    r"mon|tue|wed|thu|fri|sat|sun|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b|\s\d",
    re.I,
)
_NAME_OK = re.compile(r"^[A-Za-z][A-Za-z'.\- ]{0,58}[A-Za-z.]$|^[A-Za-z]{2}$")

_PART_OF_DAY_ARRIVAL = {"this morning": time(9, 0), "this afternoon": time(14, 0), "this evening": time(18, 0), "tonight": time(19, 0)}

ARRIVAL_SLACK = timedelta(hours=2)


@dataclass
class Announcement:
    guest_name: str | None
    day: date
    arrival: time | None
    stay: Stay | None

    def arrival_at(self, tz) -> datetime | None:
        return at(self.day, self.arrival, tz) if self.arrival else None


def guest_name(text: str) -> str | None:
    first = re.split(r"[,;\n]", text.strip(), maxsplit=1)[0]
    first = _LEADING_FILLER.sub("", first).strip()
    m = _NAME_STOP.search(" " + first)
    if m:
        first = (" " + first)[: m.start()].strip()
    first = re.sub(r"\s+", " ", first).strip(" .-")
    if not first or not _NAME_OK.match(first) or len(first.split()) > 4:
        return None
    return " ".join(w if w.isupper() and len(w) <= 3 else w[:1].upper() + w[1:] for w in first.split())


def parse(text: str, now_local: datetime) -> Announcement:
    lowered = text.lower()
    day = parse_day(lowered, now_local.date()) or now_local.date()
    arrival = next((t for phrase, t in _PART_OF_DAY_ARRIVAL.items() if phrase in lowered), None)

    # Read the stay first and blank it out, so "until 6pm" is not taken as the arrival time.
    provisional_base = at(day, time(12, 0), now_local.tzinfo) if day != now_local.date() else now_local
    found = find_stay(lowered, provisional_base)
    without_stay = lowered
    if found:
        s, e = found[1]
        without_stay = lowered[:s] + " " * (e - s) + lowered[e:]
    arrival = parse_clock(without_stay) or arrival

    stay = None
    if found:
        base = at(day, arrival, now_local.tzinfo) if arrival else provisional_base
        stay = find_stay(lowered, base)[0]  # recompute against the real arrival
    return Announcement(guest_name(text), day, arrival, stay)


def code_window(a: Announcement, now_local: datetime, valid_until_default: time) -> tuple[datetime, datetime]:
    """When the guest may enter. From the start of the day (or now) until two hours after the
    arrival time, or the estate default if no time was given. Never past midnight."""
    tz = now_local.tzinfo
    start = max(at(a.day, time(0, 0), tz), now_local.replace(second=0, microsecond=0))
    end_of_day = at(a.day, time(23, 59), tz)
    if a.arrival:
        end = min(at(a.day, a.arrival, tz) + ARRIVAL_SLACK, end_of_day)
    else:
        end = at(a.day, valid_until_default, tz)
        if end <= start:
            end = end_of_day
    if end <= start:
        end = min(start + ARRIVAL_SLACK, end_of_day) if start < end_of_day else start + ARRIVAL_SLACK
    return start, end
