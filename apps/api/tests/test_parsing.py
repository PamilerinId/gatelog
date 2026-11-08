from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import pytest

from app import announce, stay

LAGOS = ZoneInfo("Africa/Lagos")
# Wednesday 21 October 2026, 09:00 in Lagos
NOW = datetime(2026, 10, 21, 9, 0, tzinfo=LAGOS)


def local(d: int, h: int, m: int = 0, month: int = 10) -> datetime:
    return datetime(2026, month, d, h, m, tzinfo=LAGOS)


@pytest.mark.parametrize(
    "text, type_, until, minutes",
    [
        ("for 2 hours", "hours", local(21, 11), 120),
        ("for an hour", "hour", local(21, 10), 60),
        ("2hrs", "hours", local(21, 11), 120),
        ("a few hours", "hours", local(21, 12), 180),
        ("till evening", "hours", local(21, 19), None),
        ("until 6pm", "hours", local(21, 18), None),
        ("overnight", "overnight", local(22, 10), None),
        ("sleeping over", "overnight", local(22, 10), None),
        ("staying till Sunday", "multi_day", local(25, 18), None),
        ("for 3 days", "multi_day", local(24, 18), None),
        ("till tomorrow", "overnight", local(22, 12), None),
        ("until 25/10", "multi_day", local(25, 18), None),
    ],
)
def test_stay_phrases(text, type_, until, minutes):
    s = stay.parse_stay(text, NOW)
    assert s is not None, text
    assert (s.type, s.until, s.minutes) == (type_, until, minutes)


def test_no_stay_phrase():
    assert stay.parse_stay("Tunde is coming", NOW) is None


def test_relative_stay_reanchors_to_entry():
    s = stay.parse_stay("for 2 hours", NOW)
    assert s.anchored(local(21, 16, 30)).until == local(21, 18, 30)
    absolute = stay.parse_stay("overnight", NOW)
    assert absolute.anchored(local(21, 16)).until == absolute.until


def test_quick_options_and_default():
    assert stay.quick_option("1", NOW).until == local(21, 10)
    assert stay.quick_option("2", NOW).minutes == 180
    assert stay.quick_option("3", NOW).until == local(22, 10)
    assert stay.quick_option("4", NOW) is None
    d = stay.default_stay(NOW, time(21, 0))
    assert d.until == local(21, 21) and not d.given
    late = stay.default_stay(local(21, 22), time(21, 0))
    assert late.until == local(22, 0)


@pytest.mark.parametrize(
    "text, expected",
    [
        ("today", date(2026, 10, 21)),
        ("tomorrow", date(2026, 10, 22)),
        ("Saturday", date(2026, 10, 24)),
        ("wednesday", date(2026, 10, 21)),
        ("next wednesday", date(2026, 10, 28)),
        ("25/10", date(2026, 10, 25)),
        ("3rd Nov", date(2026, 11, 3)),
        ("Nov 3", date(2026, 11, 3)),
        ("the 5th", date(2026, 11, 5)),
    ],
)
def test_days(text, expected):
    assert stay.parse_day(text, NOW.date()) == expected


@pytest.mark.parametrize(
    "text, expected",
    [("4pm", time(16)), ("4:30 pm", time(16, 30)), ("16:00", time(16)), ("at 4", time(16)), ("at 10", time(10)), ("noon", time(12))],
)
def test_clock(text, expected):
    assert stay.parse_clock(text) == expected


@pytest.mark.parametrize(
    "text, name, day, arrival, stay_type",
    [
        ("Tunde, today 4pm, for 2 hours", "Tunde", date(2026, 10, 21), time(16), "hours"),
        ("Tunde Bakare is coming tomorrow by 3pm, staying overnight", "Tunde Bakare", date(2026, 10, 22), time(15), "overnight"),
        ("Expecting Mrs Okafor on Saturday", "Mrs Okafor", date(2026, 10, 24), None, None),
        ("Good morning. Chidi at 2pm", "Chidi", date(2026, 10, 21), time(14), None),
        ("guest: ngozi adeyemi till 6pm", "Ngozi Adeyemi", date(2026, 10, 21), None, "hours"),
        ("Tunde coming this evening", "Tunde", date(2026, 10, 21), time(18), None),
    ],
)
def test_announcements(text, name, day, arrival, stay_type):
    a = announce.parse(text, NOW)
    assert a.guest_name == name
    assert a.day == day
    assert a.arrival == arrival
    assert (a.stay.type if a.stay else None) == stay_type


def test_stay_counts_from_arrival():
    a = announce.parse("Tunde, today 4pm, for 2 hours", NOW)
    assert a.stay.until == local(21, 18)


def test_until_time_is_not_taken_as_arrival():
    a = announce.parse("Ngozi till 6pm", NOW)
    assert a.arrival is None and a.stay.until == local(21, 18)


@pytest.mark.parametrize("text", ["2 hours", "today at 4pm", "", "!!!", "please call me back when you can about the gate"])
def test_no_name(text):
    assert announce.parse(text, NOW).guest_name is None


def test_code_window():
    a = announce.parse("Tunde, today 4pm", NOW)
    start, end = announce.code_window(a, NOW, time(21))
    assert (start, end) == (NOW, local(21, 18))  # "valid today until 6pm"
    a = announce.parse("Tunde tomorrow", NOW)
    start, end = announce.code_window(a, NOW, time(21))
    assert (start, end) == (local(22, 0), local(22, 21))
    late = local(21, 22, 30)
    start, end = announce.code_window(announce.parse("Tunde", late), late, time(21))
    assert end == local(21, 23, 59) and end - start > timedelta(0)
