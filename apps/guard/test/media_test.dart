import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/admission.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/data/models.dart';
import 'package:gatelog_guard/data/secrets.dart';
import 'package:gatelog_guard/data/store.dart';
import 'package:gatelog_guard/sync/api.dart';
import 'package:gatelog_guard/sync/capture.dart';

import 'support.dart';

void main() {
  late GateStore store;
  late FakeApi api;
  late GateController c;
  var now = DateTime.utc(2026, 10, 21, 10);
  final clip = VoiceClip(Uint8List.fromList(List.filled(3000, 1)));
  final jpeg = List<int>.filled(5000, 2);

  setUp(() async {
    initTimeZones();
    now = DateTime.utc(2026, 10, 21, 10);
    store = memoryStore();
    api = FakeApi()..state = sampleState();
    c = GateController(store: store, secrets: Secrets(MemorySecretStore()), api: api, clock: () => now, pins: fastPins);
    await c.init();
    await pairAndOpenShift(c);
  });

  tearDown(() async {
    await c.idle();
    await store.db.close();
  });

  Future<Map<String, dynamic>> lastEntry() async => (await store.outbox()).lastWhere((i) => i.kind == OutboxKind.entry).payload;

  group('the clip and photo queue', () {
    test('a clip and two photos are kept with the entry that names them, then uploaded and deleted', () async {
      api.syncError = NetworkException('offline');
      await c.admitOnCallback('h1', null, clip: clip, photos: GatePhotos(visitor: jpeg, plate: jpeg, plateText: 'KJA456XY'));
      await c.idle();
      final e = await lastEntry();
      final waiting = await store.mediaWaiting();
      expect({for (final m in waiting) m.kind: m.id}, {
        MediaKind.clip: e['name_clip_id'],
        MediaKind.visitor: e['visitor_photo_id'],
        MediaKind.plate: e['plate_photo_id'],
      });
      expect(waiting.every((m) => m.ref == e['id']), isTrue);
      expect(e['photo_skipped'], isNull);
      expect(e['plate'], 'KJA456XY');
      expect(c.hasClip([e['id'] as String]), isTrue, reason: 'Leaving can play it back while it is on the phone');
      expect((await c.clipOf([e['id'] as String]))!.bytes.length, 3000);
      expect(api.media, isEmpty, reason: 'no network: nothing went');

      api.syncError = null;
      await c.syncNow();
      expect(api.media.map((m) => (m.$1, m.$2)).toSet(), {
        (e['name_clip_id'], 'clip'),
        (e['visitor_photo_id'], 'visitor'),
        (e['plate_photo_id'], 'plate'),
      });
      expect(await store.mediaWaiting(), isEmpty, reason: 'deleted once uploaded');
      expect(c.hasClip([e['id'] as String]), isFalse);
    });

    test('a refusal (413, 415, 400) deletes the local copy; no network keeps it', () async {
      api.mediaError = NetworkException('offline');
      await c.admitOnCallback('h1', null, clip: clip, photos: GatePhotos(visitor: jpeg));
      await c.idle();
      expect(await store.mediaWaiting(), hasLength(2));
      api.mediaError = null;
      api.mediaStatuses.addAll([413, 204]);
      await c.syncNow();
      expect(await store.mediaWaiting(), isEmpty);
      expect(api.media, hasLength(1));
    });

    test('a clip that never uploaded goes after 7 days, a photo after 30', () async {
      api.mediaError = NetworkException('offline');
      await c.admitOnCallback('h1', null, clip: clip, photos: GatePhotos(visitor: jpeg));
      await c.idle();
      now = now.add(const Duration(days: 8));
      await c.syncNow();
      expect((await store.mediaWaiting()).map((m) => m.kind), [MediaKind.visitor]);
      now = now.add(const Duration(days: 23));
      await c.syncNow();
      expect(await store.mediaWaiting(), isEmpty);
    });

    test('Undo before it was sent takes the clip and photos with it', () async {
      api.syncError = NetworkException('offline');
      api.mediaError = NetworkException('offline');
      final id = await c.admitOnCallback('h1', null, clip: clip, photos: GatePhotos(visitor: jpeg));
      await c.idle();
      expect(await c.undo(id), isTrue);
      expect(await store.mediaWaiting(), isEmpty);
    });

    test('a visit for later names its clip too', () async {
      api.syncError = NetworkException('offline');
      final home = c.snapshot!.home('h1')!;
      final id = await c.expectLater(home: home, residentId: 'r1', stay: Stay.hour, clip: clip);
      await c.idle();
      final m = (await store.mediaWaiting()).single;
      expect(m.ref, id);
      expect(c.hasClip([id]), isTrue);
    });

    test('clips and photos are wiped with everything else on a 401', () async {
      api.mediaError = NetworkException('offline');
      await c.admitOnCallback('h1', null, clip: clip);
      await c.idle();
      api.stateError = UnauthorizedException();
      await c.syncNow();
      expect(await store.mediaWaiting(), isEmpty);
    });
  });

  group('the visitor photo rule and the skip reasons', () {
    test("all, phone entries (the default) and off", () {
      Estate e(String rule) => Estate(id: 'e', name: 'E', timezone: 'Africa/Lagos', walkInPolicy: '', keyVersion: 1, visitorPhotos: rule);
      expect(e('all').photoFor('code'), isTrue);
      expect(e('phone_entries').photoFor('code'), isFalse);
      for (final m in ['callback_confirmed', 'pin_confirmed', 'walk_in_admitted']) {
        expect(e('phone_entries').photoFor(m), isTrue, reason: m);
        expect(e('off').photoFor(m), isFalse, reason: m);
      }
      expect(Estate.fromJson({'id': 'e', 'name': 'E'}).visitorPhotos, 'phone_entries');
      expect(c.snapshot!.estate.visitorPhotos, 'phone_entries');
    });

    test('the rule survives a restart (kept with the estate)', () async {
      api.state = {
        ...sampleState(),
        'estate': {...(sampleState()['estate'] as Map<String, dynamic>), 'visitor_photos': 'all'},
      };
      api.etag = '"v2"';
      await c.syncNow();
      expect(c.snapshot!.estate.visitorPhotos, 'all');
      expect((await store.loadSnapshot())!.estate.visitorPhotos, 'all');
    });

    test('skipped: no_camera or refused is sent, and only without a photo', () async {
      api.syncError = NetworkException('offline');
      await c.admitOnCallback('h1', 'Tunde', photos: const GatePhotos(skipped: PhotoSkipped.noCamera));
      await c.idle();
      expect((await lastEntry())['photo_skipped'], 'no_camera');
      await c.admitOnCallback('h1', 'Tunde', photos: const GatePhotos(skipped: PhotoSkipped.refused));
      await c.idle();
      expect((await lastEntry())['photo_skipped'], 'refused');
      await c.admitOnCallback('h1', 'Tunde', photos: GatePhotos(visitor: jpeg, skipped: PhotoSkipped.refused));
      await c.idle();
      final e = await lastEntry();
      expect(e['photo_skipped'], isNull);
      expect(e['visitor_photo_id'], isNotNull);
      await c.admitOnCallback('h1', 'Tunde');
      await c.idle();
      expect((await lastEntry())['photo_skipped'], isNull, reason: 'no photo was wanted');
    });
  });
}
