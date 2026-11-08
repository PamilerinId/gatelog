import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/core/selfie_image.dart';
import 'package:gatelog_guard/data/secrets.dart';
import 'package:gatelog_guard/data/store.dart';
import 'package:gatelog_guard/sync/api.dart';
import 'package:gatelog_guard/sync/selfies.dart';
import 'package:image/image.dart' as img;

import 'support.dart';

final jpeg = [0xff, 0xd8, 0xff, 0xe0, ...List.filled(600, 0)];

void main() {
  late GateStore store;
  late FakeApi api;
  late GateController c;
  var now = DateTime.utc(2026, 10, 21, 5);

  setUp(() async {
    initTimeZones();
    now = DateTime.utc(2026, 10, 21, 5);
    store = memoryStore();
    api = FakeApi()..state = sampleState();
    c = GateController(store: store, secrets: Secrets(MemorySecretStore()), api: api, clock: () => now, pins: fastPins);
    await c.init();
    await c.pair('ABCD-2345');
    await c.idle();
  });

  tearDown(() async {
    await c.idle();
    await store.db.close();
  });

  test('a shift with a selfie says so; the selfie waits in the database, not in the outbox', () async {
    api.syncError = NetworkException('offline');
    await c.openShift('gu1', selfieJpeg: jpeg);
    final shiftId = c.shift!.id;
    final record = (await store.outbox()).single;
    expect(record.payload['selfie_taken'], isTrue);
    expect(record.payload.keys, unorderedEquals(['id', 'guard_id', 'started_at', 'selfie_taken']), reason: 'no image in the sync record');
    expect(await store.selfieShiftIds(), [shiftId]);
    expect(await store.selfie(shiftId), jpeg);
  });

  test('not uploaded while its shift is still queued', () async {
    api.syncError = NetworkException('offline');
    await c.openShift('gu1', selfieJpeg: jpeg);
    await c.syncNow();
    expect(api.selfies, isEmpty);
    expect(await store.selfieShiftIds(), hasLength(1));
  });

  test('uploaded after the shift syncs and deleted on 204', () async {
    await c.openShift('gu1', selfieJpeg: jpeg);
    await c.idle();
    expect(api.selfies, [(c.shift!.id, jpeg.length)]);
    expect(await store.selfieShiftIds(), isEmpty);
  });

  test('a 404 (shift not on the server yet) keeps it for after the next sync', () async {
    api.selfieStatuses.add(404);
    await c.openShift('gu1', selfieJpeg: jpeg);
    await c.idle();
    final shiftId = c.shift!.id;
    expect(api.selfies, isEmpty);
    expect(await store.selfieShiftIds(), [shiftId]);

    await c.syncNow();
    expect(api.selfies.single.$1, shiftId);
    expect(await store.selfieShiftIds(), isEmpty);
  });

  test('no network keeps it; 415 drops it rather than keep a selfie forever', () async {
    api.selfieError = NetworkException('No connection.');
    await c.openShift('gu1', selfieJpeg: jpeg);
    await c.idle();
    expect(await store.selfieShiftIds(), hasLength(1));

    api.selfieError = null;
    api.selfieStatuses.add(415);
    await c.syncNow();
    expect(await store.selfieShiftIds(), isEmpty);
    expect(api.selfies, isEmpty);
  });

  test('a selfie whose shift the server rejected is deleted', () async {
    api.onSync = (body) => SyncResult(
          accepted: const [],
          duplicates: const [],
          rejected: {for (final s in body['shifts'] as List) s['id'] as String: 'unknown guard'},
        );
    await c.openShift('gu1', selfieJpeg: jpeg);
    await c.idle();
    expect(await store.selfieShiftIds(), isEmpty);
    expect(api.selfies, isEmpty);
  });

  test('a selfie never uploaded goes after 30 days', () async {
    await store.saveSelfie('old-shift', jpeg, now.subtract(const Duration(days: 31)));
    api.selfieStatuses.add(404);
    final r = await SelfieUploader(store, api, clock: () => now).upload('t');
    expect(r.dropped, 1);
    expect(await store.selfieShiftIds(), isEmpty);
  });

  test('a camera photo becomes a JPEG about 640 px on the long side and under 400 KB', () {
    final big = img.Image(width: 1920, height: 2560);
    for (var y = 0; y < big.height; y += 1) {
      for (var x = 0; x < big.width; x += 1) {
        big.setPixelRgb(x, y, (x * 7 + y) & 0xff, (y * 3) & 0xff, (x ^ y) & 0xff);
      }
    }
    final raw = Uint8List.fromList(img.encodeJpg(big, quality: 95));
    final small = shrinkSelfieSync(raw)!;
    expect(small.length, lessThan(selfieMaxBytes));
    expect(small.sublist(0, 3), [0xff, 0xd8, 0xff]);
    final back = img.decodeJpg(small)!;
    expect(back.height, 640);
    expect(back.width, 480);
    expect(shrinkSelfieSync(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
