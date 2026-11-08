import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/core/estate_time.dart';

void main() {
  setUpAll(initTimeZones);

  // 14:20 in Lagos (UTC+1).
  final et = EstateTime('Africa/Lagos', clock: () => DateTime.utc(2026, 10, 21, 13, 20, 30));

  test('window runs from now to 23:59 local today', () {
    final p = planVisit(et, Stay.hour);
    expect(p.windowStart.toUtc(), DateTime.utc(2026, 10, 21, 13, 20, 30));
    expect(p.windowEnd.toUtc(), DateTime.utc(2026, 10, 21, 22, 59));
    expect(p.windowEnd.hour, 23);
  });

  test('about an hour and a few hours', () {
    final h = planVisit(et, Stay.hour);
    expect(h.stayType, 'hour');
    expect(h.stayMinutes, 60);
    expect(h.expectedUntil.difference(h.windowStart), const Duration(minutes: 60));
    final hs = planVisit(et, Stay.hours);
    expect(hs.stayType, 'hours');
    expect(hs.stayMinutes, 180);
  });

  test('overnight is 10:00 tomorrow, local', () {
    final p = planVisit(et, Stay.overnight);
    expect(p.stayType, 'overnight');
    expect(p.stayMinutes, isNull);
    expect(p.expectedUntil.toUtc(), DateTime.utc(2026, 10, 22, 9));
  });

  test('a date is 18:00 that day, local', () {
    final p = planVisit(et, Stay.date, until: DateTime(2026, 10, 25));
    expect(p.stayType, 'multi_day');
    expect(p.expectedUntil.toUtc(), DateTime.utc(2026, 10, 25, 17));
  });

  test('late at night the window still lasts an hour', () {
    final late = EstateTime('Africa/Lagos', clock: () => DateTime.utc(2026, 10, 21, 22, 40));
    final p = planVisit(late, Stay.hour);
    expect(p.windowEnd.difference(p.windowStart), const Duration(hours: 1));
  });

  test('formatting', () {
    final now = et.now();
    expect(hhmm(now), '14:20');
    expect(when(now, now), 'today 14:20');
    expect(when(et.at(2026, 10, 22, 10), now), 'tomorrow 10:00');
    expect(when(et.at(2026, 10, 25, 18), now), 'Sun 25 Oct 18:00');
  });
}
