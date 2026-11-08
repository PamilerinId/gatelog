"""How long a guest stays, read from what the resident wrote or picked.

Relative stays ("for 2 hours") keep their length in minutes and are re-anchored to the real
entry time when the guard logs the entry. Absolute stays ("overnight", "till Sunday", "until
6pm") are fixed times. All times here are estate-local and timezone-aware.
"""

import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

STAY_TYPES = ("hour", "hours", "overnight", "multi_day")

OVERNIGHT_UNTIL = time(10, 0)  # next morning
MULTI_DAY_UNTIL = time(18, 0)  # on the last day

WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
_WD = {d: i for i, d in enumerate(WEEKDAYS)} | {d[:3]: i for i, d in enumerate(WEEKDAYS)} | {"tues": 1, "thur": 3, "thurs": 3}
MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
_WORD_NUM = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "a": 1, "an": 1}
_PARTS_OF_DAY = {"morning": time(12, 0), "afternoon": time(16, 0), "evening": time(19, 0), "night": time(22, 0)}

QUICK_OPTIONS_TEXT = (
    "How long will they stay? Reply\n"
    "1 about an hour\n"
    "2 a few hours\n"
    "3 overnight\n"
    "4 longer (we'll ask the date)"
)


@dataclass(frozen=True)
class Stay:
    type: str
    until: datetime
    minutes: int | None = None  # set for relative stays
    given: bool = True

    def anchored(self, start: datetime) -> "Stay":
        """Re-anchor a relative stay to when the guest actually came in."""
        if self.minutes is None:
            return self
        return Stay(self.type, start + timedelta(minutes=self.minutes), self.minutes, self.given)


def at(d: date, t: time, tz) -> datetime:
    return datetime.combine(d, t, tzinfo=tz)


def _relative(base: datetime, minutes: int) -> Stay:
    return Stay("hour" if minutes <= 60 else "hours", base + timedelta(minutes=minutes), minutes)


def _num(token: str) -> int | None:
    return int(token) if token.isdigit() else _WORD_NUM.get(token)


def parse_day(text: str, today: date) -> date | None:
    """today, tomorrow, a weekday (next occurrence, today counts), 25/10, 25th, 25 Oct, Oct 25."""
    t = text.lower()
    if re.search(r"\btoday\b|\btonight\b|\bthis (?:morning|afternoon|evening)\b", t):
        return today
    if re.search(r"\btomorrow\b|\btmrw\b|\btmr\b", t):
        return today + timedelta(days=1)
    m = re.search(r"\b(?:next\s+)?(" + "|".join(sorted(_WD, key=len, reverse=True)) + r")\b", t)
    if m:
        ahead = (_WD[m.group(1)] - today.weekday()) % 7
        if m.group(0).startswith("next") and ahead == 0:
            ahead = 7
        return today + timedelta(days=ahead)
    m = re.search(r"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b", t)
    if m:
        return _resolve(today, int(m.group(1)), int(m.group(2)), m.group(3))
    m = re.search(r"\b(\d{1,2})(?:st|nd|rd|th)?\s+(" + "|".join(MONTHS) + r")[a-z]*\b", t) or re.search(
        r"\b(" + "|".join(MONTHS) + r")[a-z]*\s+(\d{1,2})(?:st|nd|rd|th)?\b", t
    )
    if m:
        a, b = m.group(1), m.group(2)
        day_s, mon_s = (a, b) if a.isdigit() else (b, a)
        return _resolve(today, int(day_s), MONTHS.index(mon_s[:3]) + 1, None)
    m = re.search(r"\b(\d{1,2})(?:st|nd|rd|th)\b", t)
    if m:
        d = int(m.group(1))
        month, year = today.month, today.year
        if d < today.day:
            month, year = (1, year + 1) if month == 12 else (month + 1, year)
        return _resolve(today, d, month, str(year))
    return None


def _resolve(today: date, d: int, month: int, year: str | None) -> date | None:
    try:
        if year:
            y = int(year)
            return date(y + 2000 if y < 100 else y, month, d)
        candidate = date(today.year, month, d)
        return candidate if candidate >= today else date(today.year + 1, month, d)
    except ValueError:
        return None


def parse_clock(text: str) -> time | None:
    """4pm, 4:30pm, 4.30 pm, 16:00, noon. A bare 'at 4' reads as afternoon for 1 to 7."""
    t = text.lower()
    if re.search(r"\bnoon\b|\bmidday\b", t):
        return time(12, 0)
    m = re.search(r"\b(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)\b", t)
    if m:
        h, mins = int(m.group(1)) % 12, int(m.group(2) or 0)
        if m.group(3) == "pm":
            h += 12
        return time(h, mins) if h < 24 and mins < 60 else None
    m = re.search(r"\b([01]?\d|2[0-3]):([0-5]\d)\b", t)
    if m:
        return time(int(m.group(1)), int(m.group(2)))
    m = re.search(r"\b(?:at|by|around|about)\s+(\d{1,2})\b(?!\s*(?:hours?|hrs?|days?|/))", t)
    if m:
        h = int(m.group(1))
        if 1 <= h <= 7:
            h += 12
        return time(h, 0) if h < 24 else None
    return None


# Each pattern returns a Stay given (match, base, tz). Order matters: specific before general.
def _stay_patterns():
    num = r"(\d+|one|two|three|four|five|six|seven|eight|a|an)"

    def hours(m, base, tz):
        n = _num(m.group(1))
        return _relative(base, n * 60) if n else None

    def few_hours(m, base, tz):
        return _relative(base, 180)

    def half_hour(m, base, tz):
        return _relative(base, 30)

    def days(m, base, tz):
        n = _num(m.group(1))
        if not n:
            return None
        return Stay("multi_day", at(base.date() + timedelta(days=n), MULTI_DAY_UNTIL, tz))

    def week(m, base, tz):
        return Stay("multi_day", at(base.date() + timedelta(days=7), MULTI_DAY_UNTIL, tz))

    def overnight(m, base, tz):
        return Stay("overnight", at(base.date() + timedelta(days=1), OVERNIGHT_UNTIL, tz))

    def until_part_of_day(m, base, tz):
        target = at(base.date(), _PARTS_OF_DAY[m.group(1)], tz)
        if target <= base:
            target = base + timedelta(hours=2)
        return Stay("hours", target)

    def until_clock(m, base, tz):
        t = parse_clock(m.group(1))
        if not t:
            return None
        target = at(base.date(), t, tz)
        if target <= base:
            target += timedelta(days=1)
            return Stay("overnight", target)
        return Stay("hour" if target - base <= timedelta(hours=1) else "hours", target)

    def until_tomorrow(m, base, tz):
        return Stay("overnight", at(base.date() + timedelta(days=1), time(12, 0), tz))

    def until_day(m, base, tz):
        d = parse_day(m.group(1), base.date())
        if not d or d <= base.date():
            # "till Sunday" said on a Sunday means next Sunday.
            if d and m.group(1).strip() in _WD:
                d = d + timedelta(days=7)
            else:
                return None
        return Stay("multi_day" if (d - base.date()).days > 1 else "overnight", at(d, MULTI_DAY_UNTIL, tz))

    till = r"(?:till|until|untill|til|to|through)"
    return [
        (re.compile(r"\b(?:for\s+)?(?:a\s+)?few\s+hours?\b"), few_hours),
        (re.compile(r"\b(?:for\s+)?(?:half\s+(?:an\s+)?hour|30\s*min(?:ute)?s?)\b"), half_hour),
        (re.compile(rf"\b(?:for\s+)?{num}\s*(?:hours?|hrs?|h)\b"), hours),
        (re.compile(rf"\b(?:for\s+)?{num}\s*(?:days?|nights?)\b"), days),
        (re.compile(r"\b(?:for\s+)?(?:a|one)\s+week\b"), week),
        (re.compile(r"\b(?:overnight|over\s*night|sleep\s*over|spend(?:ing)?\s+the\s+night|staying\s+the\s+night|sleeping\s+over)\b"), overnight),
        (re.compile(rf"\b{till}\s+tomorrow\b"), until_tomorrow),
        (re.compile(rf"\b{till}\s+(?:the\s+)?(morning|afternoon|evening|night)\b"), until_part_of_day),
        (re.compile(rf"\b{till}\s+(\d{{1,2}}(?:[:.]\d{{2}})?\s*(?:am|pm)|[01]?\d:[0-5]\d|noon)"), until_clock),
        (
            re.compile(
                rf"\b{till}\s+((?:next\s+)?(?:{'|'.join(sorted(_WD, key=len, reverse=True))})|\d{{1,2}}/\d{{1,2}}(?:/\d{{2,4}})?|\d{{1,2}}(?:st|nd|rd|th)(?:\s+(?:{'|'.join(MONTHS)})[a-z]*)?|(?:{'|'.join(MONTHS)})[a-z]*\s+\d{{1,2}})\b"
            ),
            until_day,
        ),
    ]


_PATTERNS = _stay_patterns()


def find_stay(text: str, base: datetime) -> tuple[Stay, tuple[int, int]] | None:
    """The stay a message describes, and where in the (lowercased) text it was said."""
    t = text.lower()
    for pattern, build in _PATTERNS:
        m = pattern.search(t)
        if m:
            stay = build(m, base, base.tzinfo)
            if stay:
                return stay, m.span()
    return None


def parse_stay(text: str, base: datetime) -> Stay | None:
    found = find_stay(text, base)
    return found[0] if found else None


def quick_option(choice: str, base: datetime) -> Stay | None:
    """The four quick replies. '4' (longer) returns None: ask for the date next."""
    c = choice.strip()
    if c == "1":
        return _relative(base, 60)
    if c == "2":
        return _relative(base, 180)
    if c == "3":
        return Stay("overnight", at(base.date() + timedelta(days=1), OVERNIGHT_UNTIL, base.tzinfo))
    return None


def until_date(d: date, base: datetime) -> Stay:
    return Stay("multi_day" if (d - base.date()).days > 1 else "overnight", at(d, MULTI_DAY_UNTIL, base.tzinfo))


def default_stay(base: datetime, default_until: time) -> Stay:
    """No answer: today until the estate default (9pm), or two hours if that has passed."""
    target = at(base.date(), default_until, base.tzinfo)
    if target <= base:
        target = base + timedelta(hours=2)
    return Stay("hours", target, None, given=False)
