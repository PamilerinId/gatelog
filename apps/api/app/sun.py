"""Sunrise and sunset at the estate, for the map's day and night styles.

The NOAA sunrise equation, accurate to a minute or two, which is all a map theme needs.
Near the equator (all of Nigeria) there is always a sunrise and a sunset.
"""

import math
from datetime import date, datetime, timedelta, timezone

ZENITH = 90.833  # the sun's centre 50 arc-minutes below the horizon: refraction plus its radius


def _event(d: date, lat: float, lng: float, rising: bool) -> datetime | None:
    n = d.timetuple().tm_yday
    lng_hour = lng / 15
    t = n + ((6 if rising else 18) - lng_hour) / 24
    m = 0.9856 * t - 3.289  # mean anomaly
    true_lng = (m + 1.916 * math.sin(math.radians(m)) + 0.020 * math.sin(math.radians(2 * m)) + 282.634) % 360
    ra = math.degrees(math.atan(0.91764 * math.tan(math.radians(true_lng)))) % 360
    ra += (true_lng // 90) * 90 - (ra // 90) * 90  # same quadrant as the true longitude
    ra /= 15
    sin_dec = 0.39782 * math.sin(math.radians(true_lng))
    cos_dec = math.cos(math.asin(sin_dec))
    cos_h = (math.cos(math.radians(ZENITH)) - sin_dec * math.sin(math.radians(lat))) / (cos_dec * math.cos(math.radians(lat)))
    if not -1 <= cos_h <= 1:
        return None  # polar day or night
    h = (360 - math.degrees(math.acos(cos_h)) if rising else math.degrees(math.acos(cos_h))) / 15
    local_mean = h + ra - 0.06571 * t - 6.622
    utc_hours = (local_mean - lng_hour) % 24
    return datetime(d.year, d.month, d.day, tzinfo=timezone.utc) + timedelta(hours=utc_hours)


def times(d: date, lat: float, lng: float) -> tuple[datetime | None, datetime | None]:
    """(sunrise, sunset) in UTC for the local date d at (lat, lng)."""
    return _event(d, lat, lng, True), _event(d, lat, lng, False)


def is_night(now: datetime, lat: float, lng: float, local_date: date) -> bool:
    rise, set_ = times(local_date, lat, lng)
    if rise is None or set_ is None:
        return False
    return not (rise <= now < set_)
