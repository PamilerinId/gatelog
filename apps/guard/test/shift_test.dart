import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/app/shift.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/core/pin.dart';
import 'package:gatelog_guard/data/secrets.dart';
import 'package:gatelog_guard/data/store.dart';
import 'package:gatelog_guard/sync/api.dart';

import 'support.dart';

void main() {
  late GateStore store;
  late FakeApi api;
  late MemorySecretStore secretStore;
  late GateController c;
  var now = DateTime.utc(2026, 10, 21, 5); // 06:00 in Lagos

  Future<List<OutboxItem>> items(String kind) async => [for (final i in await store.outbox()) if (i.kind == kind) i];

  setUp(() async {
    initTimeZones();
    now = DateTime.utc(2026, 10, 21, 5);
    store = memoryStore();
    api = FakeApi()..state = sampleState();
    secretStore = MemorySecretStore();
    c = GateController(store: store, secrets: Secrets(secretStore), api: api, clock: () => now, pins: fastPins);
    await c.init();
    await c.pair('ABCD-2345');
    await c.idle();
  });

  tearDown(() async {
    await c.idle();
    await store.db.close();
  });

  person(String id) => c.snapshot!.guard(id)!;

  group('PIN', () {
    test('what each person is asked: enter, set, or blocked for consent', () {
      expect(c.pinStepFor(person('gu1')), PinStep.enterPin);
      expect(c.pinStepFor(person('gu2')), PinStep.setPin);
      expect(c.pinStepFor(person('gu3')), PinStep.noConsent);
    });

    test('checked offline against the hash from the state', () async {
      api.syncError = NetworkException('offline');
      api.stateError = NetworkException('offline');
      expect(await c.checkGuardPin('gu1', '482913'), isA<PinOk>());
      final wrong = await c.checkGuardPin('gu1', '111111');
      expect((wrong as PinWrong).triesLeft, 4);
    });

    test('five wrong tries lock that person out on this phone for five minutes', () async {
      for (var i = 1; i <= 4; i++) {
        expect(await c.checkGuardPin('gu1', '000000'), isA<PinWrong>());
      }
      final fifth = await c.checkGuardPin('gu1', '000000');
      expect(fifth, isA<PinLocked>());
      expect((fifth as PinLocked).until, now.add(const Duration(minutes: 5)));
      expect(c.pinStepFor(person('gu1')), PinStep.locked);
      // Even the right PIN is refused while locked.
      expect(await c.checkGuardPin('gu1', '482913'), isA<PinLocked>());
      // Others are not affected.
      expect(c.pinStepFor(person('cso1')), PinStep.setPin);

      // The lockout survives a restart.
      final again = GateController(store: store, secrets: Secrets(secretStore), api: api, clock: () => now, pins: fastPins);
      await again.init();
      expect(again.pinStepFor(again.snapshot!.guard('gu1')!), PinStep.locked);

      now = now.add(const Duration(minutes: 5, seconds: 1));
      expect(c.pinStepFor(person('gu1')), PinStep.enterPin);
      expect(await c.checkGuardPin('gu1', '482913'), isA<PinOk>());
      // A right PIN clears the count.
      expect((await c.checkGuardPin('gu1', '000000') as PinWrong).triesLeft, 4);
    });

    test('a new PIN is hashed and queued; only the hash leaves the phone', () async {
      api.syncError = NetworkException('offline');
      await c.setGuardPin('gu2', '246810');
      final pin = (await items(OutboxKind.pin)).single;
      expect(pin.serverId, 'gu2');
      expect(pin.payload.keys, unorderedEquals(['guard_id', 'pin_hash', 'set_at']));
      final hash = pin.payload['pin_hash'] as String;
      expect(hash, startsWith(r'pbkdf2-sha256$'));
      expect(hash, isNot(contains('246810')));
      expect(checkPin('246810', hash), isTrue);
      // The local PIN wins until it syncs.
      expect(c.pinStepFor(person('gu2')), PinStep.enterPin);
      expect(await c.checkGuardPin('gu2', '246810'), isA<PinOk>());
      expect(() => c.setGuardPin('gu2', '12345'), throwsArgumentError);
    });

    test('a PIN set here beats an older hash in the state until the state has it', () async {
      api.syncError = NetworkException('offline');
      await c.setGuardPin('gu1', '135790');
      expect(await c.checkGuardPin('gu1', '135790'), isA<PinOk>());
      expect(await c.checkGuardPin('gu1', '482913'), isA<PinWrong>());

      // Synced: the server stores it and the next state carries it.
      api.syncError = null;
      final synced = (await items(OutboxKind.pin)).single.payload['pin_hash'] as String;
      api.etag = '"v2"';
      api.state = sampleState(pinHashes: {'gu1': synced});
      await c.syncNow();
      expect(await items(OutboxKind.pin), isEmpty);
      expect(await c.checkGuardPin('gu1', '135790'), isA<PinOk>());
    });

    test('a PIN the server rejects (admin reset since) no longer counts: set it again', () async {
      api.onSync = (body) => SyncResult(
            accepted: [for (final id in FakeApi.idsIn(body)) if (id != 'gu1') id],
            duplicates: const [],
            rejected: {if ((body['pins'] as List).isNotEmpty) 'gu1': 'the admin reset this PIN after it was set; set it again'},
          );
      api.etag = '"v2"';
      api.state = sampleState(pinHashes: {'gu1': null}); // reset by the admin
      await c.setGuardPin('gu1', '135790');
      await c.idle();
      expect((await items(OutboxKind.pin)).single.isRejected, isTrue);
      expect(c.view.needsAttention.single.reason, contains('reset'));
      expect(c.pinStepFor(person('gu1')), PinStep.setPin);
    });
  });

  group('shift', () {
    test('a person without consent cannot open a shift', () async {
      expect(() => c.openShift('gu3'), throwsStateError);
      expect(await items(OutboxKind.shift), isEmpty);
    });

    test('open queues the shift record; end queues it again with the handover, sent as one shift id', () async {
      api.syncError = NetworkException('offline');
      await c.openShift('gu1');
      final shiftId = c.shift!.id;
      final open = (await items(OutboxKind.shift)).single.payload;
      expect(open, {'id': shiftId, 'guard_id': 'gu1', 'started_at': '2026-10-21T05:00:00.000Z', 'selfie_taken': false});

      await c.exitUnlisted('Delivery rider'); // one unsent record besides the shift
      now = now.add(const Duration(hours: 12));
      await c.endShift(handedTo: 'gu2');
      expect(c.phase, Phase.startShift);
      expect(c.shift, isNull);

      final end = (await items(OutboxKind.shift)).last;
      expect(end.id, '$shiftId:end');
      expect(end.serverId, shiftId);
      expect(end.payload['id'], shiftId);
      expect(end.payload['ended_at'], '2026-10-21T17:00:00.000Z');
      expect(end.payload['end_reason'], 'handover');
      expect(end.payload['handed_to'], 'gu2');
      expect(end.payload['handover'], {'inside': 0, 'unsynced': 2, 'night_list_open': 0});

      // Both go up together; the server answers the shift id as accepted then duplicate.
      api.syncError = null;
      api.onSync = (body) {
        final ids = FakeApi.idsIn(body);
        return SyncResult(accepted: ids.toSet().toList(), duplicates: [shiftId], rejected: const {});
      };
      await c.syncNow();
      final body = api.syncBodies.last;
      expect((body['shifts'] as List).map((s) => s['id']), [shiftId, shiftId]);
      expect(await items(OutboxKind.shift), isEmpty, reason: 'sent, then purged after the pull');
    });

    test('nobody taking over is an ordinary end', () async {
      api.syncError = NetworkException('offline');
      await c.openShift('gu1');
      await c.endShift();
      final end = (await items(OutboxKind.shift)).last.payload;
      expect(end['end_reason'], 'ended');
      expect(end['handed_to'], isNull);
    });

    test('takeover candidates: everyone with consent except the person ending', () async {
      await c.openShift('gu1');
      expect(c.takeoverCandidates.map((g) => g.id), ['gu2', 'cso1']);
    });

    test('ends by itself after 14 hours', () async {
      api.syncError = NetworkException('offline');
      await c.openShift('gu1');
      final started = now;
      now = now.add(const Duration(hours: 13, minutes: 59));
      await c.checkShiftExpiry();
      expect(c.shift, isNotNull);

      now = started.add(const Duration(hours: 15));
      await c.checkShiftExpiry();
      expect(c.shift, isNull);
      expect(c.phase, Phase.startShift);
      final end = (await items(OutboxKind.shift)).last.payload;
      expect(end['end_reason'], 'auto');
      expect(end['ended_at'], started.add(OpenShift.maxLength).toIso8601String());
    });

    test('a shift that ran out while the phone was off ends at start-up', () async {
      api.syncError = NetworkException('offline');
      await c.openShift('gu1');
      now = now.add(const Duration(hours: 20));
      final again = GateController(store: store, secrets: Secrets(secretStore), api: api, clock: () => now, pins: fastPins);
      await again.init();
      expect(again.phase, Phase.startShift);
      expect((await items(OutboxKind.shift)).last.payload['end_reason'], 'auto');
      await again.idle();
    });

    test('the role decides the view', () async {
      await c.openShift('cso1');
      expect(c.isCso, isTrue);
      await c.endShift();
      await c.openShift('gu1');
      expect(c.isCso, isFalse);
    });
  });

  group('CSO overview', () {
    test('fetched with the CSO shift id, kept for offline, refused for a guard', () async {
      await c.openShift('cso1');
      await c.idle();
      await c.refreshCso();
      expect(api.csoShiftIds, [c.shift!.id]);
      expect(c.cso!.overdue.single.guestName, 'Tunde Bakare');
      expect(c.cso!.refusedToday.single.who, 'Musa Ibrahim');
      expect(c.cso!.shiftsToday.single.handover!['night_list_open'], 1);
      expect(c.csoFetchedAt, now);

      // Offline: the last copy stays, with a note, also after a restart.
      api.csoError = NetworkException('No connection.');
      now = now.add(const Duration(minutes: 1));
      await c.refreshCso();
      expect(c.cso, isNotNull);
      expect(c.csoError, contains('last copy'));
      final again = GateController(store: store, secrets: Secrets(secretStore), api: api, clock: () => now, pins: fastPins);
      await again.init();
      expect(again.cso!.onDuty.single.guard, 'Mr Bello');
      expect(again.csoFetchedAt, now.subtract(const Duration(minutes: 1)));
    });

    test('a guard shift never asks for it', () async {
      await c.openShift('gu1');
      await c.refreshCso();
      expect(api.csoShiftIds, isEmpty);
    });

    test('mark left on an overdue guest is a list_tap exit carrying the shift', () async {
      api.state = sampleState(visits: [
        {
          'id': '9d0e7c6b-5a49-4382-a716-2f5e4d3c2b1a',
          'home_id': 'h1',
          'resident_id': 'r1',
          'guest_name': 'Tunde Bakare',
          'window_start': 1792540800,
          'window_end': 1792540800 + 3600,
          'key_version': 1,
          'code_issued': true,
          'source': 'whatsapp',
          'state': 'overstay',
          'expected_until': '2026-10-21T09:00:00+00:00',
          'entry_id': 'entry-1',
          'entered_at': '2026-10-21T08:00:00+00:00',
        },
      ]);
      api.etag = '"v2"';
      await c.syncNow();
      await c.openShift('cso1');
      api.syncError = NetworkException('offline');
      await c.markLeft('9d0e7c6b-5a49-4382-a716-2f5e4d3c2b1a', 'Tunde Bakare');
      final exit = (await items(OutboxKind.exit)).single.payload;
      expect(exit['method'], 'list_tap');
      expect(exit['entry_id'], 'entry-1');
      expect(exit['visit_id'], '9d0e7c6b-5a49-4382-a716-2f5e4d3c2b1a');
      expect(exit['guard_id'], 'cso1');
      expect(exit['shift_id'], c.shift!.id);
      expect(c.view.inside, isEmpty);
    });
  });
}
