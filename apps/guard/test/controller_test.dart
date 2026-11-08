import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/core/codes.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/core/verify.dart';
import 'package:gatelog_guard/data/secrets.dart';
import 'package:gatelog_guard/data/store.dart';
import 'package:gatelog_guard/sync/api.dart';

import 'support.dart';

final key1 = List<int>.generate(32, (i) => i); // matches key_b64 in sampleState
const visitId = '9d0e7c6b-5a49-4382-a716-2f5e4d3c2b1a';

void main() {
  late GateStore store;
  late FakeApi api;
  late MemorySecretStore secretStore;
  late GateController c;
  var now = DateTime.utc(2026, 10, 21, 10); // 11:00 in Lagos

  int unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  Map<String, dynamic> codedVisit({String state = 'expected', String? entryId}) => {
        'id': visitId,
        'home_id': 'h1',
        'resident_id': 'r1',
        'guest_name': 'Tunde Bakare',
        'window_start': unix(now) - 3600,
        'window_end': unix(now) + 3600,
        'key_version': 1,
        'code_issued': true,
        'source': 'whatsapp',
        'state': state,
        'expected_until': null,
        'entry_id': entryId,
        'entered_at': entryId == null ? null : now.toIso8601String(),
      };

  setUp(() async {
    initTimeZones();
    now = DateTime.utc(2026, 10, 21, 10);
    store = memoryStore();
    api = FakeApi()..state = sampleState(visits: [codedVisit()]);
    secretStore = MemorySecretStore();
    c = GateController(store: store, secrets: Secrets(secretStore), api: api, clock: () => now, pins: fastPins);
    await c.init();
  });

  tearDown(() async {
    await c.idle();
    await store.db.close();
  });

  Future<Map<String, dynamic>> queued(String kind) async => (await store.outbox()).lastWhere((i) => i.kind == kind).payload;

  test('pairing code normalisation', () {
    expect(GateController.normalizePairingCode('abcd2345'), 'ABCD-2345');
    expect(GateController.normalizePairingCode(' abcd - 2345 '), 'ABCD-2345');
    expect(GateController.normalizePairingCode('ABCD-234'), isNull);
  });

  test('pair, pull state, then the shift start screen until a shift opens', () async {
    expect(c.phase, Phase.unpaired);
    await c.pair('ABCD-2345');
    expect(c.phase, Phase.startShift);
    expect(c.snapshot!.homes.single.displayAddress, '14B Adeniyi Close, Block C');
    expect(c.snapshot!.homes.single.vehicles.single.plate, 'KJA456XY');
    expect(c.snapshot!.guards.map((g) => g.role), contains('cso'));
    expect(await secretStore.read('device_token'), isNotNull);
    expect(c.keys[1], key1);
    await c.openShift('gu1');
    expect(c.phase, Phase.ready);
    expect(c.isCso, isFalse);
  });

  test('state and the open shift survive a restart from the local store', () async {
    await pairAndOpenShift(c);
    final again = GateController(store: store, secrets: Secrets(secretStore), api: api, clock: () => now, pins: fastPins);
    await again.init();
    expect(again.phase, Phase.ready);
    expect(again.shift!.id, c.shift!.id);
    expect(again.guard!.name, 'Musa Ibrahim');
    expect(again.snapshot!.homes.single.residents.single.numbers.single.last4, '4567');
    expect(again.snapshot!.guards.firstWhere((g) => g.id == 'gu1').pinHash, musaPinHash);
    expect(again.snapshot!.homes.single.vehicles.single.description, 'Black Corolla');
    expect(again.keys[1], key1);
  });

  test('the second pull sends the ETag and handles 304', () async {
    await pairAndOpenShift(c);
    await c.syncNow();
    expect(api.stateEtags.last, '"v1"');
    expect(c.lastError, isNull);
  });

  test('offline: admit by code with a plate, the guest is inside, re-entering the code offers exit', () async {
    await pairAndOpenShift(c);
    api.syncError = NetworkException('No connection.');
    api.stateError = NetworkException('No connection.');

    final code = deriveCode(key1, 'h1', visitId, unix(now) - 3600, unix(now) + 3600);
    final first = c.verifyCode(code);
    expect(first, isA<AdmitMatch>());
    await c.admitWithCode((first as AdmitMatch).visit, plate: 'kja 456-xy');
    await c.syncNow();

    expect(c.view.inside.single.guestName, 'Tunde Bakare');
    expect(c.lastError, isNotNull);

    final second = c.verifyCode(code);
    expect(second, isA<ExitMatch>());
    await c.exitByCode((second as ExitMatch).visit, plate: '  ');
    expect(c.view.inside, isEmpty);

    final entry = await queued(OutboxKind.entry);
    expect(entry['guard_id'], 'gu1');
    expect(entry['shift_id'], c.shift!.id);
    expect(entry['gate_id'], 'g1');
    expect(entry['method'], 'code');
    expect(entry['visit_id'], visitId);
    expect(entry['plate'], 'kja 456-xy', reason: 'sent as typed; the server normalises');
    final exit = await queued(OutboxKind.exit);
    expect(exit['shift_id'], c.shift!.id);
    expect(exit['guard_id'], 'gu1');
    expect(exit['plate'], isNull, reason: 'a blank plate is not sent');
  });

  test('back online: the queue drains and the pulled state takes over', () async {
    await pairAndOpenShift(c);
    final code = deriveCode(key1, 'h1', visitId, unix(now) - 3600, unix(now) + 3600);
    api.syncError = NetworkException('offline');
    final m = c.verifyCode(code) as AdmitMatch;
    final entryId = await c.admitWithCode(m.visit);
    await c.syncNow();
    expect(c.view.queued, 1);

    api.syncError = null;
    api.etag = '"v2"';
    api.state = sampleState(visits: [codedVisit(state: 'inside', entryId: entryId)]);
    await c.syncNow();

    expect(c.view.queued, 0);
    expect(await store.outbox(), isEmpty); // acknowledged, then reflected in state
    expect(c.view.inside.single.entryId, entryId);
  });

  test('let in on a callback: shown at once offline, then once from the server visit after sync', () async {
    await pairAndOpenShift(c);
    api.syncError = NetworkException('offline');
    await c.recordCallback(homeId: 'h1', numberId: 'n1', outcome: 'confirmed');
    await c.admitOnCallback('h1', 'Chidi');
    expect(c.view.inside.map((g) => g.guestName), ['Chidi']); // offline: from the queue
    final entryId = (await store.outbox()).firstWhere((i) => i.kind == OutboxKind.entry).id;

    api.syncError = null;
    api.etag = '"v2"';
    api.state = sampleState(visits: [
      {
        ...codedVisit(state: 'inside', entryId: entryId),
        'id': 'walkup-visit',
        'guest_name': 'Chidi',
        'code_issued': false,
        'key_version': null,
        'source': 'phone_announced',
      },
    ]);
    await c.syncNow();
    expect(c.view.queued, 0);
    expect(await store.outbox(), isEmpty);
    expect(c.view.inside.map((g) => g.guestName), ['Chidi']); // from the server, not twice

    api.etag = '"v3"';
    api.state = sampleState();

    await c.recordExit(c.view.inside.single, method: 'list_tap');
    await c.syncNow();
    expect(c.view.inside, isEmpty);
    expect(await store.outbox(), isEmpty);
  });

  test('coming later: a confirmed callback creates a visit, already confirmed at the home, then let in', () async {
    await pairAndOpenShift(c);
    api.syncError = NetworkException('offline');
    final home = c.snapshot!.homes.single;
    final id = await c.expectLater(home: home, residentId: 'r1', call: await c.recordConfirmedCall(homeId: home.id, numberId: 'n1'), guestName: 'Ngozi', stay: Stay.hours);

    expect(c.view.confirmedFor('h1').single.id, id);
    final visit = await queued(OutboxKind.visit);
    final cb = await queued(OutboxKind.callback);
    expect(cb['visit_id'], id);
    expect(cb['outcome'], 'confirmed');
    expect(cb['shift_id'], c.shift!.id);
    expect(visit['stay_type'], 'hours');
    expect(visit['stay_minutes'], 180);
    expect(visit['shift_id'], c.shift!.id);
    expect(visit['guard_id'], 'gu1');
    // The call was queued first, then again behind the visit with its id: one record, after the visit.
    final kinds = [for (final i in await store.outbox()) i.kind];
    expect(kinds.where((k) => k == OutboxKind.callback).length, 1);
    expect(kinds.indexOf(OutboxKind.callback), greaterThan(kinds.indexOf(OutboxKind.visit)));

    await c.admitExpected(c.view.confirmedFor('h1').single, plate: 'LND 1 AB');
    expect(c.view.confirmedFor('h1'), isEmpty);
    expect(c.view.inside.single.guestName, 'Ngozi');
    final entry = await queued(OutboxKind.entry);
    expect(entry['method'], 'callback_confirmed');
    expect(entry['visit_id'], id);
    expect(entry['plate'], 'LND 1 AB');
  });

  test('undo removes a record that has not been sent', () async {
    await pairAndOpenShift(c);
    api.syncError = NetworkException('offline');
    final id = await c.exitUnlisted('Visitor');
    expect(await c.undo(id), isTrue);
    expect((await store.outbox()).where((i) => i.kind == OutboxKind.exit), isEmpty);
  });

  test('nothing is recorded without an open shift', () async {
    await c.pair('ABCD-2345');
    expect(() => c.exitUnlisted('Visitor'), throwsStateError);
  });

  test('401 wipes everything and goes back to pairing', () async {
    await pairAndOpenShift(c, selfie: [0xff, 0xd8, 0xff, 1]);
    api.syncError = NetworkException('offline');
    await c.exitUnlisted('Someone');
    api.syncError = UnauthorizedException();
    await c.syncNow();

    expect(c.phase, Phase.unpaired);
    expect(c.snapshot, isNull);
    expect(c.shift, isNull);
    expect(await secretStore.read('device_token'), isNull);
    expect(await secretStore.read('hmac_keys'), isNull);
    expect(await store.loadSnapshot(), isNull);
    expect(await store.outbox(), isEmpty);
    expect(await store.selfieShiftIds(), isEmpty);
    expect(await store.meta('shift'), isNull);
  });

  test('night list checks show at once, are queued once, and carry the shift', () async {
    api.state = sampleState(visits: [codedVisit(state: 'inside', entryId: 'e9')], rollup: {
      'id': 'ru1',
      'for_date': '2026-10-21',
      'items': [
        {'id': 'item1', 'visit_id': visitId, 'checked_at': null, 'check_result': null},
      ],
    });
    await pairAndOpenShift(c);
    api.syncError = NetworkException('offline');
    expect(c.view.nightListOpen(c.snapshot!.rollup), 1);
    await c.rollupCheck('item1', 'left');
    expect(c.view.rollupResults['item1'], 'left');
    expect(c.view.inside, isEmpty);
    expect(c.view.nightListOpen(c.snapshot!.rollup), 0);
    await c.rollupCheck('item1', 'still_inside');
    final checks = (await store.outbox()).where((i) => i.kind == OutboxKind.rollupCheck).toList();
    expect(checks, hasLength(1));
    expect(checks.single.payload['shift_id'], c.shift!.id);
    expect(checks.single.payload['guard_id'], 'gu1');
  });
}
