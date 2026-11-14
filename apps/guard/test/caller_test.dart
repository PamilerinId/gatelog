import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/caller.dart';
import 'package:gatelog_guard/data/models.dart';

import 'support.dart';

/// The API's `CALLER_MASK` (apps/api/app/routers/device.py): at most 4 leading and 4 trailing digits.
final serverMask = RegExp(r'^\+?\d{0,4}[•*]{2,4}\d{4}$');

void main() {
  group('caller_masked', () {
    test('Nigerian numbers are shown the local way: the first 4 and the last 4 digits', () {
      expect(maskCaller('08031234567'), '0803•••4567');
      expect(maskCaller('+2348031234567'), '0803•••4567');
      expect(maskCaller('2348031234567'), '0803•••4567');
      expect(maskCaller('+234 803 123 4567'), '0803•••4567');
      expect(maskCaller('0803-123-4567'), '0803•••4567');
    });

    test('other numbers keep their plus and country code, still 4 and 4', () {
      expect(maskCaller('+447700900123'), '+4477•••0123');
      expect(maskCaller('00447700900123'), '+4477•••0123');
    });

    test('short numbers show only the last 4; too short or hidden numbers are not sent', () {
      expect(maskCaller('7123456'), '•••3456');
      expect(maskCaller('12345'), isNull);
      expect(maskCaller(''), isNull);
      expect(maskCaller('Private'), isNull);
    });

    test('every mask passes the server pattern and never holds the full number', () {
      for (final n in ['08031234567', '+2348031234567', '+447700900123', '7123456', '+12025550143']) {
        final m = maskCaller(n)!;
        expect(serverMask.hasMatch(m), isTrue, reason: m);
        expect(m.replaceAll(RegExp(r'\D'), '').length, lessThanOrEqualTo(8));
      }
      expect(serverMask.hasMatch('08031234567'), isFalse, reason: 'the server rejects a full number');
    });

    test('the incoming call prints masked', () {
      final call = IncomingCall('08031234567', DateTime(2026, 11, 8));
      expect('$call', isNot(contains('1234567')));
      expect('$call', contains('0803•••4567'));
    });
  });

  group('who called', () {
    final snap = StateSnapshot.fromJson(sampleState());
    final home = snap.homes.single;

    test('a registered number finds its home and resident, in any form', () {
      for (final n in ['+2348031234567', '08031234567', '234 803 123 4567']) {
        final who = whoCalled(n, snap.homes);
        expect(who?.$1.id, 'h1', reason: n);
        expect(who?.$2.name, 'Mrs Adeyemi');
      }
      expect(isRegisteredTo('08031234567', home), isTrue);
    });

    test('an unknown number finds nothing', () {
      expect(whoCalled('08099998888', snap.homes), isNull);
      expect(isRegisteredTo('08099998888', home), isFalse);
    });
  });
}
