import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/app/no_code.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/data/models.dart';
import 'package:gatelog_guard/data/secrets.dart';
import 'package:gatelog_guard/data/store.dart';
import 'package:gatelog_guard/sync/api.dart';

import 'support.dart';

void main() {
  late GateStore store;
  late FakeApi api;
  late GateController c;
  late Home home;
  late Resident resident;
  late PhoneNumber number;
  final now = DateTime.utc(2026, 10, 21, 10);

  Future<List<Map<String, dynamic>>> queued(String kind) async => [for (final i in await store.outbox()) if (i.kind == kind) i.payload];

  setUp(() async {
    initTimeZones();
    store = memoryStore();
    api = FakeApi()..state = sampleState();
    c = GateController(store: store, secrets: Secrets(MemorySecretStore()), api: api, clock: () => now, pins: fastPins);
    await c.init();
    await pairAndOpenShift(c);
    api.syncError = NetworkException('offline'); // the gate works with no network
    home = c.snapshot!.homes.single;
    resident = home.residents.single;
    number = resident.numbers.single;
  });

  tearDown(() async {
    await c.idle();
    await store.db.close();
  });

  group('the flow', () {
    test('confirmed asks for the guest: in now or later', () {
      final f = NoCodeFlow(home)..call(resident, number);
      expect(f.record(CallOutcome.confirmed), NoCodeStep.confirmed);
      expect(f.confirmedBy, (resident, number));
    });

    test('said no stops at once', () {
      final f = NoCodeFlow(home)..call(resident, number);
      expect(f.record(CallOutcome.saidNo), NoCodeStep.stop);
      expect(f.stopReason, 'Mrs Adeyemi said no on the callback');
    });

    test('no answer once: try again; twice: stop', () {
      final f = NoCodeFlow(home)..call(resident, number);
      expect(f.record(CallOutcome.noAnswer), NoCodeStep.tryAgain);
      f.call(resident, number);
      expect(f.record(CallOutcome.noAnswer), NoCodeStep.stop);
      expect(f.stopReason, contains('No answer on two calls'));
    });

    test('an outcome needs a call', () {
      expect(() => NoCodeFlow(home).record(CallOutcome.confirmed), throwsStateError);
    });

    test('outcomes map to the API', () {
      expect(CallOutcome.values.map((o) => o.api), ['confirmed', 'declined', 'no_answer']);
    });
  });

  group('the records', () {
    test('they are here: a confirmed callback, then a callback_confirmed entry with no visit', () async {
      await c.recordCallback(homeId: home.id, numberId: number.id, outcome: CallOutcome.confirmed.api);
      await c.admitOnCallback(home.id, 'Chidi', plate: 'kja-456 xy');
      final cb = (await queued(OutboxKind.callback)).single;
      final entry = (await queued(OutboxKind.entry)).single;
      expect(cb['outcome'], 'confirmed');
      expect(cb['visit_id'], isNull);
      expect(entry['method'], 'callback_confirmed');
      expect(entry['visit_id'], isNull);
      expect(entry['plate'], 'kja-456 xy');
      expect(home.vehicleFor(entry['plate'] as String)?.description, 'Black Corolla');
      for (final r in [cb, entry]) {
        expect(r['shift_id'], c.shift!.id);
        expect(r['guard_id'], 'gu1');
      }
      expect(c.view.inside.single.guestName, 'Chidi');
    });

    test('coming later: a visit for the stay, linked from the confirming callback', () async {
      final id = await c.expectLater(home: home, residentId: resident.id, call: await c.recordConfirmedCall(homeId: home.id, numberId: number.id), guestName: 'Ngozi', stay: Stay.overnight);
      final visit = (await queued(OutboxKind.visit)).single;
      final cb = (await queued(OutboxKind.callback)).single;
      expect(cb['visit_id'], id);
      expect(visit['stay_type'], 'overnight');
      expect(visit['expected_until'], '2026-10-22T09:00:00.000Z'); // 10:00 Lagos the next day
      expect(visit['window_end'], '2026-10-21T22:59:00.000Z'); // 23:59 Lagos today
      expect(await queued(OutboxKind.entry), isEmpty, reason: 'nobody comes in yet');
      expect(c.view.confirmedFor(home.id).single.guestName, 'Ngozi');
    });

    test('said no, then turned away with the reason', () async {
      final f = NoCodeFlow(home)..call(resident, number);
      f.record(CallOutcome.saidNo);
      await c.recordCallback(homeId: home.id, numberId: number.id, outcome: CallOutcome.saidNo.api);
      await c.turnAway(homeId: home.id, guestName: 'Hawker', reason: f.stopReason);
      final entry = (await queued(OutboxKind.entry)).single;
      expect(entry['method'], 'refused');
      expect(entry['reason'], 'Mrs Adeyemi said no on the callback');
      expect((await queued(OutboxKind.callback)).single['outcome'], 'declined');
      expect(c.view.inside, isEmpty);
    });

    test('turned away with no reason sends none', () async {
      await c.turnAway(homeId: home.id, guestName: 'Hawker', reason: '  ');
      expect((await queued(OutboxKind.entry)).single['reason'], isNull);
    });
  });

  group('walk-in decisions', () {
    test('need who decided and a reason', () async {
      expect(() => c.admitWalkIn(homeId: home.id, guestName: 'Electrician', decidedBy: 'cso1', reason: '  '), throwsArgumentError);
      expect(() => c.admitWalkIn(homeId: home.id, guestName: 'Electrician', decidedBy: '', reason: 'Known to the CSO'), throwsArgumentError);
      expect(await queued(OutboxKind.entry), isEmpty);
    });

    test('recorded as walk_in_admitted with the decider and reason, and the guest is inside', () async {
      expect(c.csos.map((g) => g.id), ['cso1']);
      await c.admitWalkIn(homeId: home.id, guestName: 'Electrician', decidedBy: 'cso1', reason: ' Estate electrician, known to the CSO ', plate: 'LND 1');
      final entry = (await queued(OutboxKind.entry)).single;
      expect(entry['method'], 'walk_in_admitted');
      expect(entry['decided_by'], 'cso1');
      expect(entry['reason'], 'Estate electrician, known to the CSO');
      expect(entry['guard_id'], 'gu1');
      expect(entry['shift_id'], c.shift!.id);
      expect(entry['plate'], 'LND 1');
      expect(entry['visit_id'], isNull);
      expect(c.view.inside.single.guestName, 'Electrician');
    });
  });

  test('plates match the home after upper-casing and stripping spaces and dashes', () {
    expect(normalisePlate('kja 456-xy'), 'KJA456XY');
    expect(home.vehicleFor('KJA-456-XY')?.plate, 'KJA456XY');
    expect(home.vehicleFor('kja456x'), isNull);
    expect(home.vehicleFor(''), isNull);
    expect(home.vehicleFor(null), isNull);
  });
}
