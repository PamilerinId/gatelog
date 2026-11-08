import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _tzReady = false;

void initTimeZones() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

/// Local time in the estate's timezone (Africa/Lagos for every estate today).
class EstateTime {
  EstateTime(String name, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now, location = _location(name);

  final tz.Location location;
  final DateTime Function() _clock;

  static tz.Location _location(String name) {
    initTimeZones();
    try {
      return tz.getLocation(name);
    } catch (_) {
      return tz.getLocation('Africa/Lagos');
    }
  }

  tz.TZDateTime now() => tz.TZDateTime.from(_clock(), location);
  tz.TZDateTime of(DateTime t) => tz.TZDateTime.from(t, location);
  tz.TZDateTime ofUnix(int seconds) => tz.TZDateTime.from(DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true), location);
  tz.TZDateTime at(int y, int m, int d, [int h = 0, int min = 0]) => tz.TZDateTime(location, y, m, d, h, min);
}

/// How long a phone-announced guest is staying (flow A).
enum Stay {
  hour('hour', 'About an hour'),
  hours('hours', 'A few hours'),
  overnight('overnight', 'Overnight'),
  date('multi_day', 'Until a date');

  const Stay(this.apiType, this.label);
  final String apiType;
  final String label;
}

class VisitPlan {
  const VisitPlan({required this.windowStart, required this.windowEnd, required this.expectedUntil, required this.stayType, required this.stayMinutes});
  final tz.TZDateTime windowStart;
  final tz.TZDateTime windowEnd;
  final tz.TZDateTime expectedUntil;
  final String stayType;
  final int? stayMinutes;
}

/// Window: now until 23:59 local today (at least an hour, so a call at 23:30 still works).
/// Stay: an hour = 60 min, a few hours = 180, overnight = 10:00 next day, a date = 18:00 that day.
VisitPlan planVisit(EstateTime et, Stay stay, {DateTime? until}) {
  final now = et.now();
  final start = et.at(now.year, now.month, now.day, now.hour, now.minute).add(Duration(seconds: now.second));
  var end = et.at(now.year, now.month, now.day, 23, 59);
  if (end.difference(start) < const Duration(hours: 1)) end = start.add(const Duration(hours: 1));
  final tomorrow = et.at(now.year, now.month, now.day + 1);
  final (expected, minutes) = switch (stay) {
    Stay.hour => (start.add(const Duration(minutes: 60)), 60),
    Stay.hours => (start.add(const Duration(minutes: 180)), 180),
    Stay.overnight => (et.at(tomorrow.year, tomorrow.month, tomorrow.day, 10), null),
    Stay.date => (et.at(until!.year, until.month, until.day, 18), null),
  };
  return VisitPlan(windowStart: start, windowEnd: end, expectedUntil: expected, stayType: stay.apiType, stayMinutes: minutes);
}

String two(int n) => n.toString().padLeft(2, '0');

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "14:05"
String hhmm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

/// "Tue 21 Oct"
String dayMonth(DateTime t) => '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';

/// "today 14:05", "tomorrow 10:00", "Tue 21 Oct 18:00"
String when(DateTime t, DateTime now) {
  final d = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = d.difference(today).inDays;
  final day = switch (diff) { 0 => 'today', 1 => 'tomorrow', -1 => 'yesterday', _ => dayMonth(t) };
  return '$day ${hhmm(t)}';
}

/// ISO 8601 with offset, as the sync endpoint wants. Uses UTC ("Z").
String isoNow(DateTime t) => t.toUtc().toIso8601String();
