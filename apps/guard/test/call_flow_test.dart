import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/admission.dart';
import 'package:gatelog_guard/app/call_flow.dart';
import 'package:gatelog_guard/app/caller.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/core/pin.dart';
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
  final now = DateTime.utc(2026, 10, 21, 10); // 11:00 in Lagos
  final clip = VoiceClip(Uint8List.fromList(List.filled(2000, 7)));
  final fromNewNumber = IncomingCall('08099998888', now.subtract(const Duration(minutes: 2)));
  final fromHome = IncomingCall('+2348031234567', now.subtract(const Duration(minutes: 2)));

  Future<void> boot({String guard = 'gu1', String? homePin, Map<String, dynamic>? state}) async {
    initTimeZones();
    store = memoryStore();
    api = FakeApi()
      ..state = state ?? sampleState(houseCodeHash: homePin == null ? null : makePinHash(homePin, iterations: 1000), pinHashes: {'cso1': musaPinHash})
      // Offline: everything waits in the queue, where the test reads it.
      ..syncError = NetworkException('offline');
    c = GateController(store: store, secrets: Secrets(MemorySecretStore()), api: api, clock: () => now, pins: fastPins);
    await c.init();
    api.syncError = null;
    await c.pair('ABCD-2345');
    await c.idle();
    api.syncError = NetworkException('offline');
    await c.openShift(guard);
    await c.idle();
  }

  tearDown(() async {
    await c.idle();
    await store.db.close();
  });

  Home home() => c.snapshot!.home('h1')!;
  Future<List<Map<String, dynamic>>> queued(String kind) async => [
    for (final i in await store.outbox())
      if (i.kind == kind) i.payload,
  ];

  CallFlow flowWith({IncomingCall? caller, Visit? visit}) {
    final f = CallFlow(c, home(), caller: caller, visit: visit);
    final (r, n) = f.numbers.first;
    f.dialling(r, n);
    f.calledBack(now);
    return f;
  }

  test('callback yes, here now: a callback_confirmed entry with the clip, the caller masked, the photos', () async {
    await boot();
    final f = flowWith(caller: fromNewNumber);
    expect(f.step, CallStep.answer);
    f.nameClip = clip;
    expect(await f.answer(CallOutcome.confirmed), CallStep.hereNow);
    final call = (await queued(OutboxKind.callback)).single;
    expect(call['outcome'], 'confirmed', reason: 'on file before the guard chooses');
    expect(call['number_id'], 'n1');

    await f.letIn(const GatePhotos(skipped: PhotoSkipped.refused, plateText: 'KJA 456 XY'));
    final e = (await queued(OutboxKind.entry)).single;
    expect(e['method'], 'callback_confirmed');
    expect(e['visit_id'], isNull);
    expect(e['guest_name'], 'Voice clip');
    expect(e['name_clip_id'], isNotNull);
    expect(e['caller_masked'], '0809•••8888');
    expect(e['photo_skipped'], 'refused');
    expect(e['plate'], 'KJA 456 XY');
    expect(e['guard_id'], 'gu1');
    expect(e['shift_id'], c.shift!.id);
    final media = await store.mediaWaiting();
    expect(media.single.kind, MediaKind.clip);
    expect(media.single.ref, e['id']);
    expect(media.single.id, e['name_clip_id']);
    // Called from a number not on file: offer it.
    expect(f.step, CallStep.offerNumber);
  });

  test('callback yes, coming later: a visit, and the confirming call again with its id', () async {
    await boot();
    final f = flowWith();
    await f.answer(CallOutcome.confirmed);
    f.notHereNow();
    expect(f.step, CallStep.stay);
    f.nameClip = clip;
    final id = await f.expect(Stay.overnight);
    final v = (await queued(OutboxKind.visit)).single;
    expect(v['id'], id);
    expect(v['trust'], 'verified');
    expect(v['resident_id'], 'r1');
    expect(v['guest_name'], 'Voice clip');
    expect(v['name_clip_id'], isNotNull);
    expect((await queued(OutboxKind.callback)).single['visit_id'], id);
    expect(f.step, CallStep.done, reason: 'the call came from no number: nothing to offer');
    expect(f.result, CallResult.expected);
  });

  test('callback no: to the CSO; a guard picks who decided', () async {
    await boot();
    final f = flowWith();
    expect(await f.answer(CallOutcome.saidNo), CallStep.pickCso);
    expect((await queued(OutboxKind.callback)).single['outcome'], 'declined');
    expect(f.stopWhy, 'Mrs Adeyemi said no on the callback');
  });

  test('no answer twice: the CSO decides; once is "call again"', () async {
    await boot();
    final f = flowWith();
    expect(await f.answer(CallOutcome.noAnswer), CallStep.callback);
    final (r, n) = f.numbers.first;
    f.dialling(r, n);
    f.calledBack(now);
    expect(await f.answer(CallOutcome.noAnswer), CallStep.pickCso);
    expect((await queued(OutboxKind.callback)).map((x) => x['outcome']), ['no_answer', 'no_answer']);
  });

  test('home PIN right: pin_checks with the caller, then a pin_confirmed entry', () async {
    await boot(homePin: '4821');
    final f = CallFlow(c, home(), caller: fromHome);
    expect(f.homeHasPin, isTrue);
    f.wantPin();
    expect(await f.tryPin('0000'), isFalse);
    expect(f.pinTriesLeft, 2);
    expect(await f.tryPin('4821'), isTrue);
    expect(f.step, CallStep.hereNow);
    final checks = await queued(OutboxKind.pinCheck);
    expect(checks.map((x) => (x['ok'], x['context'], x['caller_masked'])), [(false, 'gate', '0803•••4567'), (true, 'gate', '0803•••4567')]);
    expect(checks.toString(), isNot(contains('4821')), reason: 'the PIN never leaves the phone');

    f.nameClip = clip;
    await f.letIn(GatePhotos.none);
    final e = (await queued(OutboxKind.entry)).single;
    expect(e['method'], 'pin_confirmed');
    expect(e['caller_masked'], '0803•••4567');
    expect(f.step, CallStep.done, reason: 'no number offer after a PIN: nobody confirmed on a callback');
  });

  test('home PIN, coming later: a PIN-verified visit', () async {
    await boot(homePin: '4821');
    final f = CallFlow(c, home());
    f.wantPin();
    await f.tryPin('4821');
    f.notHereNow();
    await f.expect(Stay.hours);
    final v = (await queued(OutboxKind.visit)).single;
    expect(v['trust'], 'pin_verified');
    expect(v['resident_id'], isNull);
    expect(await queued(OutboxKind.callback), isEmpty);
  });

  test('home PIN: three wrong tries stop it for this call, each one a pin_checks record', () async {
    await boot(homePin: '4821');
    final f = CallFlow(c, home(), caller: fromNewNumber);
    f.wantPin();
    for (final p in ['0000', '1111', '2222']) {
      expect(await f.tryPin(p), isFalse);
    }
    expect(f.step, CallStep.pinLocked);
    final checks = await queued(OutboxKind.pinCheck);
    expect(checks, hasLength(3));
    expect(checks.every((x) => x['ok'] == false && x['caller_masked'] == '0809•••8888'), isTrue);
    f.backToCallback();
    expect(f.step, CallStep.callback);
  });

  test('a home with no PIN: no PIN path', () async {
    await boot();
    final f = CallFlow(c, home());
    expect(f.homeHasPin, isFalse);
    expect(await c.checkGatePin('h1', '4821'), isNull);
    expect(await queued(OutboxKind.pinCheck), isEmpty);
  });

  test("the CSO's decision: walk_in_admitted with who, why, the caller and the clip; or refused", () async {
    await boot();
    final f = flowWith(caller: fromNewNumber);
    f.supervisor();
    expect(f.step, CallStep.pickCso);
    f.pickCso(c.snapshot!.guard('cso1')!);
    f.pickReason(CsoReason.described);
    expect(f.step, CallStep.csoLetIn);
    f.nameClip = clip;
    await f.letIn(const GatePhotos(skipped: PhotoSkipped.noCamera));
    final e = (await queued(OutboxKind.entry)).single;
    expect(e['method'], 'walk_in_admitted');
    expect(e['decided_by'], 'cso1');
    expect(e['guard_id'], 'gu1');
    expect(e['reason'], 'Described the house well');
    expect(e['caller_masked'], '0809•••8888');
    expect(e['name_clip_id'], isNotNull);
    expect(e['photo_skipped'], 'no_camera');
    expect(f.step, CallStep.done, reason: 'nobody confirmed on a callback: no number offer');

    final g = flowWith();
    g.supervisor();
    g.pickCso(c.snapshot!.guard('cso1')!);
    await g.turnAway();
    final refused = (await queued(OutboxKind.entry)).last;
    expect(refused['method'], 'refused');
    expect(refused['decided_by'], 'cso1');
    expect(refused['reason'], 'The guard called the supervisor');
  });

  test('"Other": the reason said in a clip, its id in the note (the API has no field for it)', () async {
    await boot();
    final f = flowWith();
    f.supervisor();
    f.pickCso(c.snapshot!.guard('cso1')!);
    f.pickReason(CsoReason.other);
    expect(f.step, CallStep.csoOther);
    f.otherReasonSaid(clip);
    await f.letIn(GatePhotos.none);
    final e = (await queued(OutboxKind.entry)).single;
    expect(e['reason'], 'Other, said in a voice clip');
    expect(e['note'], startsWith('Reason clip: '));
    expect(e['name_clip_id'], isNull, reason: 'no name was said');
    expect(e['guest_name'], 'Visitor');
    expect((await store.mediaWaiting()).single.kind, MediaKind.clip);
  });

  test('the CSO on the gate decides alone: preselected, decided_by is their own id', () async {
    await boot(guard: 'cso1');
    final f = flowWith();
    expect(f.decidingAlone, isTrue);
    expect(await f.answer(CallOutcome.saidNo), CallStep.csoReason, reason: 'no "pick the CSO"');
    f.pickReason(CsoReason.known);
    await f.letIn(GatePhotos.none);
    final e = (await queued(OutboxKind.entry)).single;
    expect(e['decided_by'], 'cso1');
    expect(e['guard_id'], 'cso1');
  });

  /// Two CSOs: Mr Bello first in `guards`, Mrs Okafor second. [onDuty] null: an older server
  /// with no `on_duty` at all.
  Map<String, dynamic> twoCsos({List<Map<String, dynamic>>? onDuty}) {
    final s = sampleState(pinHashes: {'cso1': musaPinHash});
    (s['guards'] as List).add({'id': 'cso2', 'name': 'Mrs Okafor', 'role': 'cso', 'pin_hash': null, 'pin_reset_at': null, 'consent': true});
    if (onDuty != null) s['on_duty'] = onDuty;
    return s;
  }

  test("a guard picks from the CSOs on shift first: /state's on_duty, matched by guard id", () async {
    await boot(
      state: twoCsos(
        onDuty: [
          {'guard_id': 'gu2', 'gate_id': 'g1', 'since': now.subtract(const Duration(hours: 2)).toIso8601String()},
          {'guard_id': 'cso2', 'gate_id': 'g2', 'since': now.subtract(const Duration(hours: 1)).toIso8601String()},
        ],
      ),
    );
    expect(c.snapshot!.onDuty.map((d) => d.guardId), ['gu2', 'cso2']);
    expect(c.csosOnShiftFirst.map((g) => g.id), ['cso2', 'cso1'], reason: 'Mrs Okafor is on shift, Mr Bello is not');
    expect(c.csoOnShift(c.snapshot!.guard('cso2')!), isTrue);
    expect(c.csoOnShift(c.snapshot!.guard('cso1')!), isFalse);
    expect(c.onShift('gu1'), isTrue, reason: "this phone's own shift, before it has synced");

    // Kept with the rest of the state: the same after a restart with no network.
    final again = GateController(store: store, secrets: c.secrets, api: api, clock: () => now, pins: fastPins);
    await again.init();
    expect(again.csosOnShiftFirst.first.id, 'cso2');
    again.dispose();
  });

  test('no on_duty from an older server: nobody is on shift, the CSOs in register order', () async {
    await boot(state: twoCsos());
    expect(c.snapshot!.onDuty, isEmpty);
    expect(c.csosOnShiftFirst.map((g) => g.id), ['cso1', 'cso2']);
    expect(c.csoOnShift(c.snapshot!.guard('cso1')!), isFalse);
  });

  test('a listed shift older than 14 hours has ended by itself: not on shift', () async {
    await boot(
      state: twoCsos(
        onDuty: [
          {'guard_id': 'cso2', 'gate_id': 'g1', 'since': now.subtract(const Duration(hours: 15)).toIso8601String()},
        ],
      ),
    );
    expect(c.csoOnShift(c.snapshot!.guard('cso2')!), isFalse);
    expect(c.csosOnShiftFirst.first.id, 'cso1');
  });

  test('a number offer: only after a confirmed callback, from a number not on file', () async {
    await boot();
    final f = flowWith(caller: fromNewNumber);
    await f.answer(CallOutcome.confirmed);
    expect(f.canOfferNumber, isTrue);
    await f.letIn(GatePhotos.none);
    await f.offer(true);
    final o = (await queued(OutboxKind.numberOffer)).single;
    expect(o['resident_id'], 'r1');
    expect(o['number'], '08099998888', reason: 'the only record with a full number');
    expect(o['shift_id'], c.shift!.id);
    expect(f.step, CallStep.done);
    expect(c.describe((await store.outbox()).firstWhere((i) => i.kind == OutboxKind.numberOffer)), isNot(contains('8888')));

    // From a registered number: nothing to offer. Said No: nothing recorded.
    final g = flowWith(caller: fromHome);
    await g.answer(CallOutcome.confirmed);
    expect(g.canOfferNumber, isFalse);
    final h = flowWith(caller: fromNewNumber);
    await h.answer(CallOutcome.confirmed);
    await h.offer(false);
    expect(await queued(OutboxKind.numberOffer), hasLength(1));
  });

  test('a coded guest whose home wants a call first: yes lets them in by code, with the callback on the visit', () async {
    await boot();
    final visit = Visit(
      id: '9d0e7c6b-5a49-4382-a716-2f5e4d3c2b1a',
      homeId: 'h1',
      residentId: 'r1',
      guestName: 'Tunde Bakare',
      windowStart: 0,
      windowEnd: 0,
      keyVersion: 1,
      codeIssued: true,
      source: 'whatsapp',
      state: 'expected',
      expectedUntil: null,
      entryId: null,
      enteredAt: null,
    );
    final f = flowWith(visit: visit);
    expect(await f.answer(CallOutcome.confirmed), CallStep.letIn);
    expect((await queued(OutboxKind.callback)).single['visit_id'], visit.id);
    await f.letIn(GatePhotos.none);
    final e = (await queued(OutboxKind.entry)).single;
    expect(e['method'], 'code');
    expect(e['visit_id'], visit.id);
    expect(e['guest_name'], 'Tunde Bakare');
  });

  test('the caller hint lasts 10 minutes', () async {
    await boot();
    final ids = FakeCallerId(IncomingCall('08031234567', now.subtract(const Duration(minutes: 9))));
    final c2 = GateController(store: store, secrets: Secrets(MemorySecretStore()), api: api, clock: () => now, callerId: ids);
    expect(await c2.recentCaller(), isNotNull);
    ids.call = IncomingCall('08031234567', now.subtract(const Duration(minutes: 11)));
    expect(await c2.recentCaller(), isNull);
    ids.call = null;
    expect(await c2.recentCaller(), isNull);
    // Asked once per pairing; refused, nothing changes.
    await c2.askForCallerIdOnce();
    await c2.askForCallerIdOnce();
    expect(ids.asked, 1);
    c2.dispose();
  });
}
