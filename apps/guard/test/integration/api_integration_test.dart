/// End to end against a running API. Skipped unless these are set:
///
///   GATELOG_IT_BASE_URL       e.g. http://127.0.0.1:8799
///   GATELOG_IT_PAIRING_CODE   an unused pairing code from POST /v1/admin/devices
///   GATELOG_IT_CODE           the six-digit code of a guest expected now (computed server side)
///   GATELOG_IT_ADMIN_TOKEN    the estate admin's token, to check what the server stored
///   GATELOG_IT_HOUSE_CODE     14B's home PIN (optional; the PIN-confirmed entry and the flag-down then use it)
///
/// `tool/it_seed.py` prints all of them. See README.md, "Integration check".
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/admission.dart';
import 'package:gatelog_guard/app/call_flow.dart';
import 'package:gatelog_guard/app/caller.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/app/positions.dart';
import 'package:gatelog_guard/app/rides.dart';
import 'package:gatelog_guard/app/shift.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/core/selfie_image.dart';
import 'package:gatelog_guard/core/verify.dart';
import 'package:gatelog_guard/data/secrets.dart';
import 'package:gatelog_guard/data/shuttle.dart';
import 'package:gatelog_guard/sync/api.dart';
import 'package:gatelog_guard/sync/capture.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../support.dart';

/// The rider phone's GPS, played back by the test.
class _Gps implements LocationSource {
  final _fixes = StreamController<PositionFix>.broadcast();
  void at(DateTime t) => _fixes.add(PositionFix(lat: 6.61, lng: 3.39, accuracyM: 6, heading: 90, speed: 4, at: t));
  @override
  Future<LocationAccess> ensureAccess() async => LocationAccess.granted;
  @override
  Stream<PositionFix> watch(Duration every) => _fixes.stream;
  @override
  Future<void> openSettings() async {}
}

void main() {
  final env = Platform.environment;
  final base = env['GATELOG_IT_BASE_URL'];
  final pairing = env['GATELOG_IT_PAIRING_CODE'];
  final code = env['GATELOG_IT_CODE'];
  final adminToken = env['GATELOG_IT_ADMIN_TOKEN'];
  final houseCode = env['GATELOG_IT_HOUSE_CODE'];
  final skip = base == null || pairing == null || code == null || adminToken == null ? 'set GATELOG_IT_* to run against a live API' : null;

  Future<dynamic> admin(String path) async {
    final r = await http.get(Uri.parse('$base$path'), headers: {'Authorization': 'Bearer $adminToken'});
    expect(r.statusCode, 200, reason: r.body);
    return jsonDecode(r.body);
  }

  /// A binary admin read (a clip, a photo): only the status matters here.
  Future<int> adminStatus(String path) async =>
      (await http.get(Uri.parse('$base$path'), headers: {'Authorization': 'Bearer $adminToken'})).statusCode;

  void noneRejected(GateController c) =>
      expect(c.view.needsAttention, isEmpty, reason: c.view.needsAttention.map((i) => '${i.kind}: ${i.reason}').join('; '));

  test('PIN, shift with selfie, entries with plates, No code outcomes, handover, CSO overview', () async {
    initTimeZones();
    final store = memoryStore();
    final api = HttpGateApi(base!);
    final secretStore = MemorySecretStore();
    // The real hasher: 60,000 iterations in an isolate, the hash the server must accept.
    final gps = _Gps();
    final c = GateController(store: store, secrets: Secrets(secretStore), api: api, location: gps);
    await c.init();

    // Pairing takes any case and a missing dash.
    await c.pair(GateController.normalizePairingCode(pairing!.toLowerCase().replaceAll('-', ''))!);
    expect(c.phase, Phase.startShift, reason: c.lastError);
    final musa = c.snapshot!.guards.firstWhere((g) => g.name == 'Musa Ibrahim');
    final bello = c.snapshot!.guards.firstWhere((g) => g.isCso);
    expect(musa.consent, isTrue);
    expect(c.pinStepFor(musa), PinStep.setPin);

    // First shift: set the PIN, then the selfie, then open.
    await c.setGuardPin(musa.id, '482913');
    expect(await c.checkGuardPin(musa.id, '482913'), isA<PinOk>());
    final photo = img.Image(width: 1280, height: 960);
    img.fill(photo, color: img.ColorRgb8(30, 60, 90));
    final jpeg = shrinkSelfieSync(Uint8List.fromList(img.encodeJpg(photo)))!;
    await c.openShift(musa.id, selfieJpeg: jpeg);
    final musaShift = c.shift!.id;
    await c.idle();
    await c.syncNow(); // the selfie goes up after the shift has synced
    noneRejected(c);
    expect(await store.selfieShiftIds(), isEmpty, reason: 'uploaded, then deleted from the phone');
    expect(c.snapshot!.guard(musa.id)!.pinHash, startsWith(r'pbkdf2-sha256$60000$'), reason: 'the server stored the hash');
    expect(c.pinStepFor(c.snapshot!.guard(musa.id)!), PinStep.enterPin);

    // Offline verification with the keys from /state reproduces the server's code.
    final check = c.verifyCode(code!);
    expect(check, isA<AdmitMatch>());
    final visit = (check as AdmitMatch).visit;
    final home = c.snapshot!.home(visit.homeId)!;
    expect(home.vehicleFor('KJA-456 xy')?.description, 'Black Corolla');
    await c.admitWithCode(visit, plate: 'kja 456-xy');
    await c.idle();
    await c.syncNow();
    noneRejected(c);
    expect(c.view.inside.map((g) => g.visitId), contains(visit.id));
    final logged = (await admin('/v1/admin/entries?plate=KJA456')) as List;
    expect(logged.single['plate'], 'KJA456XY');
    expect(logged.single['shift_id'], musaShift);

    final exit = c.verifyCode(code);
    expect(exit, isA<ExitMatch>());
    await c.exitByCode((exit as ExitMatch).visit, plate: 'KJA456XY');

    // No code: confirmed and here now; confirmed and coming later; said no and turned away;
    // nobody reachable and the CSO decides.
    final resident = home.residents.first;
    final number = resident.numbers.first;
    await c.recordCallback(homeId: home.id, numberId: number.id, outcome: 'confirmed');
    await c.admitOnCallback(home.id, 'Chidi', plate: 'LND 1 AB');
    final later = await c.expectLater(home: home, residentId: resident.id, call: await c.recordConfirmedCall(homeId: home.id, numberId: number.id), guestName: 'Ngozi', stay: Stay.overnight);
    await c.recordCallback(homeId: home.id, numberId: number.id, outcome: 'declined');
    await c.turnAway(homeId: home.id, guestName: 'Hawker', reason: 'Mrs Adeyemi said no on the callback');
    await c.recordCallback(homeId: home.id, numberId: number.id, outcome: 'no_answer');
    await c.recordCallback(homeId: home.id, numberId: number.id, outcome: 'no_answer');
    await c.admitWalkIn(
      homeId: home.id,
      guestName: 'Electrician',
      decidedBy: bello.id,
      reason: 'Estate electrician, known to the CSO',
      callerMasked: '0803•••1234',
    );
    await c.idle();
    await c.syncNow();
    noneRejected(c);
    expect(c.view.queued, 0);
    expect(c.view.inside.map((g) => g.guestName), containsAll(['Chidi', 'Electrician']));
    expect(c.view.inside.where((g) => g.guestName == 'Chidi'), hasLength(1), reason: 'the server visit replaces the local walk-in once');
    expect(c.view.confirmedFor(home.id).map((v) => v.id), contains(later));
    final walkIn = ((await admin('/v1/admin/entries?method=walk_in_admitted')) as List).single;
    expect(walkIn['decided_by'], 'Mr Bello');
    expect(walkIn['reason'], 'Estate electrician, known to the CSO');
    // Admitted on a description: unverified, so the server texted the home "Not you? Reply NO".
    expect(walkIn['trust'], 'unverified');
    expect(walkIn['caller'], '0803•••1234');
    expect(walkIn['decided_alone'], isFalse);

    // --- Phone call: a resident rings from a new number; the callback is the proof ------------
    // The guard says the visitor's name (a clip), photographs the visitor and the plate, and the
    // home is asked to confirm the new number. All through the call flow, as the screens drive it.
    final newNumber = '0809${(Random().nextInt(9000000) + 1000000)}';
    final rang = IncomingCall(newNumber, DateTime.now());
    final m4a = Uint8List.fromList([0, 0, 0, 0x18, ...'ftypM4A '.codeUnits, ...List.filled(3000, 1)]);
    final call = CallFlow(c, home, caller: rang);
    final (callee, dialled) = call.numbers.first;
    call.dialling(callee, dialled);
    call.calledBack(DateTime.now());
    call.nameClip = VoiceClip(m4a);
    expect(await call.answer(CallOutcome.confirmed), CallStep.hereNow);
    final plateJpeg = shrinkGatePhotoSync(Uint8List.fromList(img.encodeJpg(photo)))!;
    final clipped = await call.letIn(GatePhotos(visitor: jpeg, plate: plateJpeg, plateText: 'KJA 456 XY'));
    expect(call.step, CallStep.offerNumber);
    await call.offer(true);

    // The home PIN (the real hash, checked offline): PIN-verified.
    String? pinEntry;
    if (houseCode != null) {
      final byPin = CallFlow(c, home, caller: rang);
      byPin.wantPin();
      expect(await byPin.tryPin(houseCode), isTrue);
      pinEntry = await byPin.letIn(const GatePhotos(skipped: PhotoSkipped.refused));
    }
    await c.idle();
    await c.syncNow();
    noneRejected(c);
    expect(await store.mediaWaiting(), isEmpty, reason: 'the clip and both photos uploaded, then deleted');

    final entries = (await admin('/v1/admin/entries')) as List;
    final spoken = entries.firstWhere((e) => e['id'] == clipped);
    expect(spoken['method'], 'callback_confirmed');
    expect(spoken['trust'], 'verified');
    expect(spoken['guest_name'], 'Voice clip');
    expect(spoken['name_clip_id'], isNotNull);
    expect(spoken['caller'], maskCaller(newNumber));
    expect(spoken['plate'], 'KJA456XY');
    expect(spoken['visitor_photo_id'], isNotNull);
    expect(spoken['plate_photo_id'], isNotNull);
    expect(await adminStatus('/v1/admin/clips/${spoken['name_clip_id']}'), 200, reason: 'the clip reached the server');
    expect(await adminStatus('/v1/admin/photos/${spoken['visitor_photo_id']}'), 200);
    expect(await adminStatus('/v1/admin/photos/${spoken['plate_photo_id']}'), 200);
    if (pinEntry != null) {
      final pin = entries.firstWhere((e) => e['id'] == pinEntry);
      expect(pin['method'], 'pin_confirmed');
      expect(pin['trust'], 'pin_verified');
      expect(pin['photo_skipped'], 'refused');
      expect(pin['caller'], maskCaller(newNumber));
    }
    // The new number waits, invisible to the gate, for the home's YES.
    final adeyemiRow = ((await admin('/v1/admin/residents?q=Adeyemi')) as List).single as Map<String, dynamic>;
    final offered = (adeyemiRow['numbers'] as List).cast<Map<String, dynamic>>().where((n) => n['last4'] == newNumber.substring(newNumber.length - 4));
    expect(offered.single['pending'], isTrue);
    expect(c.snapshot!.home(home.id)!.residents.first.numbers.map((n) => n.last4), isNot(contains(newNumber.substring(newNumber.length - 4))));

    // End with a handover to the CSO.
    await c.endShift(handedTo: bello.id);
    expect(c.phase, Phase.startShift);
    await c.idle();
    await c.syncNow();
    noneRejected(c);
    final shifts = (await admin('/v1/admin/shifts')) as List;
    final mine = shifts.firstWhere((s) => s['id'] == musaShift);
    expect(mine['handed_to'], 'Mr Bello');
    expect(mine['end_reason'], 'handover');
    expect(mine['selfie'], 'available');

    // The CSO's shift and the CSO view.
    await c.setGuardPin(bello.id, '135790');
    await c.openShift(bello.id);
    expect(c.isCso, isTrue);
    await c.refreshCso();
    expect(c.csoError, isNull);
    final o = c.cso!;
    expect(o.refusedToday.map((d) => d.reason), contains('Mrs Adeyemi said no on the callback'));
    expect(o.walkInsToday.single.who, 'Mr Bello');
    expect(o.onDuty.map((d) => d.guard), contains('Mr Bello'));
    final musaToday = o.shiftsToday.firstWhere((s) => s.id == musaShift);
    expect(musaToday.handedTo, 'Mr Bello');
    expect(musaToday.handover, {'inside': isA<int>(), 'unsynced': isA<int>(), 'night_list_open': 0});
    expect(musaToday.selfie, isTrue);

    // The CSO on the gate decides a walk-in alone: no "pick the CSO", decided_by is the CSO.
    final alone = CallFlow(c, c.snapshot!.home(home.id)!);
    expect(alone.decidingAlone, isTrue);
    alone.supervisor();
    expect(alone.step, CallStep.csoReason);
    alone.pickReason(CsoReason.known);
    final aloneId = await alone.letIn(const GatePhotos(skipped: PhotoSkipped.noCamera));
    await c.idle();
    await c.syncNow();
    noneRejected(c);
    final decided = ((await admin('/v1/admin/entries?method=walk_in_admitted')) as List).firstWhere((e) => e['id'] == aloneId);
    expect(decided['decided_alone'], isTrue);
    expect(decided['trust'], 'unverified');
    await c.refreshCso();
    expect(c.cso!.walkInsToday.firstWhere((d) => d.entryId == aloneId).decidedAlone, isTrue);

    // Retrying a batch is safe: the second time the server answers duplicates.
    final token = (await Secrets(secretStore).token())!;
    final id = '6f1b0c2e-8a4d-4c1e-9b7a-${DateTime.now().microsecondsSinceEpoch.toString().padLeft(12, '0').substring(0, 12)}';
    final body = {
      'exits': [
        {'id': id, 'method': 'list_tap', 'guest_name': 'Retry test', 'guard_id': bello.id, 'shift_id': c.shift!.id, 'at': DateTime.now().toUtc().toIso8601String()},
      ],
      'rollup_checks': [],
    };
    expect((await api.sync(token, body)).accepted, [id]);
    expect((await api.sync(token, body)).duplicates, [id]);

    // --- The estate shuttle -----------------------------------------------------------------
    expect(c.shuttle, isNotNull, reason: 'the seed turns the shuttle on');
    final shuttleHome = c.snapshot!.home(home.id)!;
    expect(shuttleHome.houseCodeHash, startsWith(r'pbkdf2-sha256$60000$'));
    final adeyemi = shuttleHome.residents.first;

    // The CSO issues Mrs Adeyemi's card (only the hash leaves the phone), and books a guest at
    // the gate. The same card again is refused with whose it is.
    const uid = '04:A2:1B:7C:55:80';
    await c.issueCard(uid: uid, resident: adeyemi);
    await c.bookAtGate(home: shuttleHome, kind: RideKind.guest, passenger: 'Tunde');
    await c.idle();
    await c.syncNow();
    noneRejected(c);
    expect(c.cardFor(uid)?.residentId, adeyemi.id, reason: 'the card came back in /state, hashed');
    final again = await c.issueCard(uid: uid, resident: adeyemi);
    await c.idle();
    await c.syncNow();
    final refused = await c.queuedItem(again);
    expect(refused!.isRejected, isTrue);
    expect(refused.reason, contains("already Mrs Adeyemi's"));
    await c.dismissRejected(again);
    final gateRide = c.waitingRides.singleWhere((r) => r.passenger == 'Tunde');
    expect(gateRide.source, 'gate');
    expect(gateRide.pickup.kind, 'gate');
    await c.endShift();
    await c.idle();

    // The rider: PIN, the motorcycle, positions every 15 seconds while the shift is open.
    final kunle = c.snapshot!.guards.firstWhere((g) => g.isRider);
    await c.setGuardPin(kunle.id, '864209');
    final bike = c.shuttle!.shuttles.single;
    await c.openShift(kunle.id, shuttleId: bike.id);
    final riderShift = c.shift!.id;
    await c.idle();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.positions!.running, isTrue);
    final t0 = DateTime.now().toUtc();
    for (var i = 0; i < 3; i++) {
      gps.at(t0.add(Duration(seconds: 15 * i)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await c.syncNow();
    noneRejected(c);
    expect(await store.positions(), isEmpty, reason: 'sent');

    // Book at the gate -> the rider takes it -> picked up with the card -> dropped off.
    await c.acceptRide(c.rides.ride(gateRide.id)!);
    await c.idle();
    await c.syncNow();
    noneRejected(c);
    expect(c.rideNotice, isNull);
    expect(c.myRides.single.id, gateRide.id, reason: 'the pulled state says Kunle has it');
    final card = c.cardFor('04a21b7c5580')!;
    await c.pickUp(c.myRides.single, who: RideConfirm.card(cardId: card.id, residentId: card.residentId));
    await c.idle();
    await c.dropOff(c.rides.ride(gateRide.id)!);
    await c.idle();
    await c.syncNow();
    noneRejected(c);
    final done = await admin('/v1/admin/rides/${gateRide.id}') as Map<String, dynamic>;
    expect(done['state'], 'done');
    expect(done['rider'], 'Kunle Rider');
    expect(done['shuttle'], 'S1');
    expect(done['confirmed_by'], 'card');
    expect(done['confirmed_resident'], 'Mrs Adeyemi');
    expect([for (final e in done['events'] as List) e['event']], ['accept', 'pick_up', 'drop_off']);

    // Flagged down: the house code (checked offline, the real hash), the ride and its pickup.
    RideConfirm who = const RideConfirm.rider();
    if (houseCode != null) {
      expect(await c.checkHouseCode(home.id, houseCode), isA<HouseCodeOk>());
      who = RideConfirm.houseCode(residentId: adeyemi.id);
    }
    final stops = rideStops(c.snapshot!, home: shuttleHome);
    final flagId = await c.newFlagRide(home: shuttleHome, pickup: stops.first, dropoff: stops.firstWhere((s) => s.kind == 'place'), who: who);
    await c.idle();
    await c.syncNow();
    noneRejected(c);
    expect(c.view.queued, 0, reason: 'the pin_checks record went up with the ride');
    final flag = await admin('/v1/admin/rides/$flagId') as Map<String, dynamic>;
    expect(flag['source'], 'flag');
    expect(flag['state'], 'picked_up');
    expect(flag['to'], 'Clubhouse');
    expect(flag['confirmed_by'], houseCode == null ? 'rider' : 'house_code');
    expect(c.myRides.single.id, flagId);

    // The estate map: the admin sees the rider where the phone was.
    final live = await admin('/v1/admin/live') as Map<String, dynamic>;
    final onMap = (live['shuttles'] as List).cast<Map<String, dynamic>>().singleWhere((s) => s['shift_id'] == riderShift);
    expect(onMap['rider'], 'Kunle Rider');
    expect(onMap['shuttle'], 'S1');
    expect(onMap['lat'], 6.61);
    expect(onMap['lng'], 3.39);
    expect((onMap['trail'] as List).length, 3);
    expect((onMap['ride'] as Map)['id'], flagId);

    // Ending the rider's shift stops the reports at once; the server refuses any more.
    await c.endShift();
    expect(c.positions!.running, isFalse);
    gps.at(t0.add(const Duration(seconds: 60)));
    await c.idle();
    await c.syncNow();
    noneRejected(c);
    expect(await store.positions(), isEmpty, reason: 'nothing recorded after the shift ended');
    final after = await http.post(
      Uri.parse('$base/v1/device/positions'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'shift_id': riderShift, 'points': [PositionFix(lat: 6.61, lng: 3.39, at: DateTime.now().toUtc()).toJson()]}),
    );
    expect(after.statusCode, 409);
    final liveAfter = await admin('/v1/admin/live') as Map<String, dynamic>;
    expect((liveAfter['shuttles'] as List).where((s) => s['shift_id'] == riderShift), isEmpty);

    await c.idle();
    await store.db.close();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));

  test('a revoked or unknown token wipes the phone', () async {
    initTimeZones();
    final store = memoryStore();
    final secrets = MemorySecretStore();
    await secrets.write('device_token', 'gld.00000000-0000-0000-0000-000000000000.00000000-0000-0000-0000-000000000000.nope');
    final c = GateController(store: store, secrets: Secrets(secrets), api: HttpGateApi(base!));
    await c.init();
    await c.syncNow();
    expect(c.phase, Phase.unpaired);
    expect(await secrets.read('device_token'), isNull);
    await store.db.close();
  }, skip: skip);
}
