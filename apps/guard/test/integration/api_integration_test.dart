/// End to end against a running API. Skipped unless these are set:
///
///   GATELOG_IT_BASE_URL       e.g. http://127.0.0.1:8799
///   GATELOG_IT_PAIRING_CODE   an unused pairing code from POST /v1/admin/devices
///   GATELOG_IT_CODE           the six-digit code of a guest expected now (computed server side)
///   GATELOG_IT_ADMIN_TOKEN    the estate admin's token, to check what the server stored
///
/// `tool/it_seed.py` prints all of them. See README.md, "Integration check".
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/app/shift.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/core/selfie_image.dart';
import 'package:gatelog_guard/core/verify.dart';
import 'package:gatelog_guard/data/secrets.dart';
import 'package:gatelog_guard/sync/api.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../support.dart';

void main() {
  final env = Platform.environment;
  final base = env['GATELOG_IT_BASE_URL'];
  final pairing = env['GATELOG_IT_PAIRING_CODE'];
  final code = env['GATELOG_IT_CODE'];
  final adminToken = env['GATELOG_IT_ADMIN_TOKEN'];
  final skip = base == null || pairing == null || code == null || adminToken == null ? 'set GATELOG_IT_* to run against a live API' : null;

  Future<dynamic> admin(String path) async {
    final r = await http.get(Uri.parse('$base$path'), headers: {'Authorization': 'Bearer $adminToken'});
    expect(r.statusCode, 200, reason: r.body);
    return jsonDecode(r.body);
  }

  void noneRejected(GateController c) =>
      expect(c.view.needsAttention, isEmpty, reason: c.view.needsAttention.map((i) => '${i.kind}: ${i.reason}').join('; '));

  test('PIN, shift with selfie, entries with plates, No code outcomes, handover, CSO overview', () async {
    initTimeZones();
    final store = memoryStore();
    final api = HttpGateApi(base!);
    final secretStore = MemorySecretStore();
    // The real hasher: 60,000 iterations in an isolate, the hash the server must accept.
    final c = GateController(store: store, secrets: Secrets(secretStore), api: api);
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
    await c.admitWalkIn(homeId: home.id, guestName: 'Electrician', decidedBy: bello.id, reason: 'Estate electrician, known to the CSO');
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

    await c.endShift();
    await c.idle();
    await store.db.close();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

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
