import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/app/positions.dart';
import 'package:gatelog_guard/app/rides.dart';
import 'package:gatelog_guard/app/shift.dart';
import 'package:gatelog_guard/core/card.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/core/pin.dart';
import 'package:gatelog_guard/data/secrets.dart';
import 'package:gatelog_guard/data/shuttle.dart';
import 'package:gatelog_guard/data/store.dart';
import 'package:gatelog_guard/sync/api.dart';

import 'support.dart';

/// Where the phone is, on demand.
class FakeLocation implements LocationSource {
  LocationAccess access = LocationAccess.granted;
  int asked = 0;
  int settingsOpened = 0;
  StreamController<PositionFix>? _fixes;
  bool get listening => _fixes != null && _fixes!.hasListener;

  void at(DateTime when, {double lat = 6.61, double lng = 3.39}) => _fixes?.add(PositionFix(lat: lat, lng: lng, accuracyM: 8, at: when));

  @override
  Future<LocationAccess> ensureAccess() async {
    asked++;
    return access;
  }

  @override
  Stream<PositionFix> watch(Duration every) {
    final c = StreamController<PositionFix>();
    c.onCancel = () => _fixes = null;
    _fixes = c;
    return c.stream;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

const rideA = '5b7a8f40-1c2d-4e5f-8a9b-0c1d2e3f4a5b';
const rideB = '6c8b9051-2d3e-4f60-9bac-1d2e3f4a5b6c';

void main() {
  group('estate card hash', () {
    test('the pinned vector', () {
      // hashlib.sha256(b"gatelog-card-v1|e3b0c442-98fc-4c14-9afb-f4c8996fb924|04A21B7C5580").hexdigest()
      expect(cardHash('e3b0c442-98fc-4c14-9afb-f4c8996fb924', '04:A2:1B:7C:55:80'), '118658b98511c8e549d393b2be2321e4467c4e60f844387ef38e5dea8c4547a7');
    });

    test('any separators and case give the same hash; bytes read from a tag are upper-case hex', () {
      const estate = 'e3b0c442-98fc-4c14-9afb-f4c8996fb924';
      final want = cardHash(estate, '04A21B7C5580');
      expect(cardHash(estate, '04 a2 1b 7c 55 80'), want);
      expect(cardHash(estate.toUpperCase(), '04-a2-1b-7c-55-80'), want);
      expect(uidHex([0x04, 0xa2, 0x1b, 0x7c, 0x55, 0x80]), '04A21B7C5580');
      expect(uidLast4('04:A2:1B:7C:55:80'), '5580');
      expect(isPlausibleUid('04A21B7C'), isTrue);
      expect(isPlausibleUid('04A2'), isFalse);
    });
  });

  late GateStore store;
  late FakeApi api;
  late FakeLocation location;
  late GateController c;
  var booted = false;
  var now = DateTime.utc(2026, 10, 21, 9); // 10:00 in Lagos
  final hash = cardHash('e1', cardUid);
  final houseHash = makePinHash('4821', iterations: 1000);

  Future<List<OutboxItem>> items(String kind) async => [
    for (final i in await store.outbox())
      if (i.kind == kind) i,
  ];

  void serve(Map<String, dynamic> shuttle) {
    api.state = sampleState(shuttle: shuttle, houseCodeHash: houseHash);
    api.etag = '"${DateTime.now().microsecondsSinceEpoch}"';
  }

  Future<void> boot({Map<String, dynamic>? shuttle}) async {
    initTimeZones();
    now = DateTime.utc(2026, 10, 21, 9);
    store = memoryStore();
    api = FakeApi();
    serve(
      shuttle ??
          sampleShuttle(
            cardHash: hash,
            rides: [
              sampleRide(rideA),
              sampleRide(rideB, kind: 'delivery', source: 'gate', fromHome: false, passenger: 'Jumia parcel'),
            ],
          ),
    );
    location = FakeLocation();
    c = GateController(store: store, secrets: Secrets(MemorySecretStore()), api: api, clock: () => now, pins: fastPins, location: location);
    await c.init();
    await c.pair('ABCD-2345');
    await c.idle();
    booted = true;
  }

  tearDown(() async {
    if (!booted) return;
    booted = false;
    await c.idle();
    c.dispose();
    await store.db.close();
  });

  group('rider shift', () {
    setUp(boot);

    test('a rider picks the motorcycle; the shift record carries it, start and end', () async {
      final rider = c.snapshot!.guard('ri1')!;
      expect(rider.isRider, isTrue);
      await c.openShift('ri1', shuttleId: 'bike1');
      expect(c.isRider, isTrue);
      expect(c.bike?.label, 'S1');
      await c.idle();
      final start = api.syncBodies.expand((b) => b['shifts'] as List).first as Map;
      expect(start['shuttle_id'], 'bike1');
      await c.endShift();
      await c.idle();
      final end = api.syncBodies.expand((b) => b['shifts'] as List).last as Map;
      expect(end['ended_at'], isNotNull);
      expect(end['shuttle_id'], 'bike1');
    });

    test('only a rider picks a motorcycle, and only one of the estate\'s', () async {
      expect(() => c.openShift('gu1', shuttleId: 'bike1'), throwsArgumentError);
      expect(() => c.openShift('ri1', shuttleId: 'nope'), throwsArgumentError);
    });

    test('a rider hands over to riders; a guard to guards and the CSO', () async {
      await c.openShift('ri1', shuttleId: 'bike1');
      expect(c.takeoverCandidates.map((g) => g.id), ['ri2']);
      await c.endShift();
      await c.openShift('gu1');
      expect(c.takeoverCandidates.map((g) => g.id), ['gu2', 'cso1']);
    });
  });

  group('home PIN', () {
    setUp(() async {
      await boot();
      await c.openShift('ri1', shuttleId: 'bike1');
      await c.idle();
    });

    test('checked offline like a PIN; three wrong tries on one home, then ask them to call the gate; every check is a pin_checks record', () async {
      api.syncError = NetworkException('offline');
      api.stateError = NetworkException('offline');
      expect(await c.checkHouseCode('h1', '4821'), isA<HouseCodeOk>());
      for (var left = 2; left >= 1; left--) {
        expect((await c.checkHouseCode('h1', '0000') as HouseCodeWrong).triesLeft, left);
      }
      final locked = await c.checkHouseCode('h1', '0000');
      expect(locked, isA<HouseCodeLocked>());
      expect((locked as HouseCodeLocked).until, now.add(const Duration(minutes: 5)));
      expect(await c.checkHouseCode('h1', '4821'), isA<HouseCodeLocked>(), reason: 'even the right PIN waits');

      final checks = [for (final i in await items(OutboxKind.pinCheck)) i.payload];
      expect(checks.map((p) => p['ok']), [true, false, false, false], reason: 'a locked try is not a check');
      expect(checks.first['home_id'], 'h1');
      expect(checks.first['context'], 'shuttle');
      expect(checks.first['guard_id'], 'ri1');
      expect(checks.first['shift_id'], c.shift!.id);
      expect(checks.toString(), isNot(contains('4821')), reason: 'the PIN never leaves the phone');

      now = now.add(const Duration(minutes: 5, seconds: 1));
      expect(await c.checkHouseCode('h1', '4821'), isA<HouseCodeOk>());
      api.syncError = null;
      api.stateError = null;
      await c.syncNow();
      expect(api.syncBodies.last['pin_checks'], hasLength(5));
    });

    test('the lockout survives a restart', () async {
      for (var i = 0; i < 3; i++) {
        await c.checkHouseCode('h1', '9999');
      }
      final again = GateController(store: store, secrets: c.secrets, api: api, clock: () => now, pins: fastPins);
      await again.init();
      expect(again.houseCodeLockedUntil('h1'), isNotNull);
      again.dispose();
    });

    test('a home with no PIN says so, and malformed input never matches', () async {
      expect(await c.checkHouseCode('h1', '48211'), isA<HouseCodeWrong>());
      expect(await c.checkHouseCode('h1', '482'), isA<HouseCodeWrong>());
      api.state = sampleState(shuttle: sampleShuttle()); // no house_code_hash
      api.etag = '"no-code"';
      await c.syncNow();
      expect(await c.checkHouseCode('h1', '4821'), isA<HouseCodeNone>());
    });
  });

  group('rides', () {
    setUp(() async {
      await boot();
      await c.openShift('ri1', shuttleId: 'bike1');
      await c.idle();
      await pumpEventQueue();
    });

    Ride ride(String id) => c.rides.ride(id)!;

    test('the queue: requested rides, and the rider\'s own once taken', () async {
      expect(c.waitingRides.map((r) => r.id), [rideA, rideB]);
      expect(c.myRides, isEmpty);
      api.syncError = NetworkException('offline');
      await c.acceptRide(ride(rideA));
      expect(c.waitingRides.map((r) => r.id), [rideB]);
      expect(c.myRides.single.id, rideA, reason: 'taken offline, shown as mine at once');
      expect(c.myRides.single.state, RideState.accepted);
      await c.releaseRide(ride(rideA));
      expect(c.waitingRides.map((r) => r.id), [rideA, rideB], reason: 'handed back to the queue');
    });

    test('taken by another rider: the sync rejects it, the rider is told, the ride goes', () async {
      api.onSync = (body) {
        final ev = (body['ride_events'] as List).cast<Map>();
        final lost = {
          for (final e in ev)
            if (e['event'] == 'accept') e['id'] as String: 'taken by Ade Rider',
        };
        return SyncResult(
          accepted: [
            for (final id in FakeApi.idsIn(body))
              if (!lost.containsKey(id)) id,
          ],
          duplicates: const [],
          rejected: lost,
        );
      };
      // On the server Ade already has it; this phone has not pulled that yet.
      final requestedA = ride(rideA);
      serve(
        sampleShuttle(
          cardHash: hash,
          rides: [
            sampleRide(rideA, state: 'accepted', riderId: 'ri2', rider: 'Ade Rider'),
            sampleRide(rideB, kind: 'delivery', source: 'gate', fromHome: false, passenger: 'Jumia parcel'),
          ],
        ),
      );
      await c.acceptRide(requestedA);
      await c.idle();
      expect(c.rideNotice, 'Taken by Ade Rider');
      expect(c.waitingRides.map((r) => r.id), [rideB]);
      expect(c.myRides, isEmpty);
      expect(await items(OutboxKind.rideEvent), isEmpty, reason: 'not a needs-attention item');
      expect(c.view.needsAttention, isEmpty);

      // Without a fresh state (304), the lost ride stays off this rider's list.
      api.onSync = (body) {
        final ev = (body['ride_events'] as List).cast<Map>();
        return SyncResult(accepted: const [], duplicates: const [], rejected: {for (final e in ev) e['id'] as String: 'taken by Ade Rider'});
      };
      await c.acceptRide(ride(rideB));
      await c.idle();
      expect(c.waitingRides, isEmpty);
      c.clearRideNotice();
      expect(c.rideNotice, isNull);
    });

    test('picked up with the card, then dropped off: the records and the queue', () async {
      api.syncError = NetworkException('offline');
      await c.acceptRide(ride(rideA));
      final card = c.cardFor('04a21b7c5580')!;
      expect(card.residentId, 'r1');
      expect(c.cardFor('04:A2:1B:7C:55:81'), isNull, reason: 'an unknown card says so');
      await c.pickUp(
        ride(rideA),
        who: RideConfirm.card(cardId: card.id, residentId: card.residentId),
      );
      expect(c.myRides.single.state, RideState.pickedUp);
      await c.dropOff(ride(rideA));
      expect(c.myRides, isEmpty);
      expect(c.rides.ride(rideA), isNull);

      final events = [for (final i in await items(OutboxKind.rideEvent)) i.payload];
      expect(events.map((e) => e['event']), ['accept', 'pick_up', 'drop_off']);
      final pickup = events[1];
      expect(pickup['ride_id'], rideA);
      expect(pickup['confirmed_by'], 'card');
      expect(pickup['card_id'], 'card1');
      expect(pickup['resident_id'], 'r1');
      expect(pickup['guard_id'], 'ri1');
      expect(pickup['shift_id'], c.shift!.id);
      expect(events[2]['confirmed_by'], isNull, reason: 'a passenger is confirmed at pickup');
      expect(pickup.toString(), isNot(contains('04A21B')), reason: 'no raw UID leaves the phone');
    });

    test('a parcel: who took it is recorded at drop-off, not at pickup', () async {
      await c.acceptRide(ride(rideB));
      await c.pickUp(ride(rideB), who: const RideConfirm.guard());
      await c.dropOff(ride(rideB), who: const RideConfirm.houseCode(residentId: 'r1'));
      await c.idle();
      final events = [for (final b in api.syncBodies) ...(b['ride_events'] as List).cast<Map>()];
      expect(events.firstWhere((e) => e['event'] == 'pick_up')['confirmed_by'], isNull);
      final drop = events.firstWhere((e) => e['event'] == 'drop_off');
      expect(drop['confirmed_by'], 'house_code');
      expect(drop['resident_id'], 'r1');
    });

    test('no-show closes the ride', () async {
      await c.acceptRide(ride(rideA));
      await c.noShow(ride(rideA));
      expect(c.rides.ride(rideA), isNull);
    });

    test('flagged down: the ride and its pickup go in the same batch', () async {
      final home = c.snapshot!.home('h1')!;
      final stops = rideStops(c.snapshot!, home: home);
      expect(stops.map((s) => s.label), ['14B Adeniyi Close, Block C', 'Main gate', 'Clubhouse']);
      final id = await c.newFlagRide(home: home, pickup: stops[0], dropoff: stops[2], who: const RideConfirm.rider());
      expect(c.myRides.single.id, id);
      expect(c.myRides.single.state, RideState.pickedUp);
      expect(c.myRides.single.dropoff.label, 'Clubhouse');
      await c.idle();
      final body = api.syncBodies.firstWhere((b) => (b['rides'] as List).isNotEmpty);
      final r = (body['rides'] as List).single as Map;
      expect(r['source'], 'flag');
      expect(r['kind'], 'resident');
      expect(r['pickup'], {'kind': 'home', 'ref': 'h1'});
      expect(r['dropoff'], {'kind': 'place', 'ref': 'pl1'});
      final ev = (body['ride_events'] as List).single as Map;
      expect(ev['ride_id'], id);
      expect(ev['event'], 'pick_up');
      expect(ev['confirmed_by'], 'rider');
    });

    test('pickup and drop-off carry where the phone was', () async {
      location.at(now);
      await pumpEventQueue();
      await c.acceptRide(ride(rideA));
      await c.idle();
      final ev = (api.syncBodies.last['ride_events'] as List).single as Map;
      expect(ev['lat'], 6.61);
      expect(ev['lng'], 3.39);
    });
  });

  group('booking', () {
    setUp(boot);

    test('the guard books a parcel and a guest from the gate to the home', () async {
      await c.openShift('gu1');
      final home = c.snapshot!.home('h1')!;
      await c.bookAtGate(home: home, kind: RideKind.delivery, passenger: ' Jumia parcel ');
      await c.bookAtGate(home: home, kind: RideKind.guest, passenger: 'Tunde', note: 'Walking stick');
      await c.idle();
      final rides = [for (final b in api.syncBodies) ...(b['rides'] as List).cast<Map>()];
      expect(rides.map((r) => (r['kind'], r['source'], r['passenger'])), [('delivery', 'gate', 'Jumia parcel'), ('guest', 'gate', 'Tunde')]);
      expect(rides.first['pickup'], {'kind': 'gate', 'ref': 'g1'});
      expect(rides.first['dropoff'], {'kind': 'home', 'ref': 'h1'});
      expect(rides.first['guard_id'], 'gu1');
      expect(rides.last['note'], 'Walking stick');
      expect(() => c.bookAtGate(home: home, kind: RideKind.resident, passenger: 'x'), throwsArgumentError);
    });

    test('the CSO books for a resident who rang, and issues a card', () async {
      await c.setGuardPin('cso1', '135790');
      await c.openShift('cso1');
      final home = c.snapshot!.home('h1')!;
      final stops = rideStops(c.snapshot!, home: home);
      final later = now.add(const Duration(hours: 2));
      await c.bookDispatch(home: home, residentId: 'r1', pickup: stops[0], dropoff: stops[1], wantedAt: later, note: 'Slow walker');
      expect(() => c.bookDispatch(home: home, residentId: 'r1', pickup: stops[1], dropoff: stops[1]), throwsArgumentError);
      await c.issueCard(uid: '04:B0:00:00:00:01', resident: home.residents.single);
      await c.idle();
      final ride = [for (final b in api.syncBodies) ...(b['rides'] as List).cast<Map>()].single;
      expect(ride['source'], 'dispatch');
      expect(ride['kind'], 'resident');
      expect(ride['resident_id'], 'r1');
      expect(ride['wanted_at'], isoNow(later));
      final card = [for (final b in api.syncBodies) ...(b['cards'] as List).cast<Map>()].single;
      expect(card['uid_hash'], cardHash('e1', '04B000000001'));
      expect(card['uid_last4'], '0001');
      expect(card['resident_id'], 'r1');
      expect(card['guard_id'], 'cso1');
      expect(card.toString(), isNot(contains('04B000')), reason: 'only the hash and last 4 leave the phone');
    });

    test('a card already issued comes back rejected with whose it is', () async {
      await c.setGuardPin('cso1', '135790');
      await c.openShift('cso1');
      api.onSync = (body) {
        final cards = (body['cards'] as List).cast<Map>();
        return SyncResult(
          accepted: [
            for (final id in FakeApi.idsIn(body))
              if (!cards.any((x) => x['id'] == id)) id,
          ],
          duplicates: const [],
          rejected: {for (final x in cards) x['id'] as String: "this card is already Mrs Adeyemi's; revoke it in the dashboard first"},
        );
      };
      final id = await c.issueCard(uid: '04:B0:00:00:00:02', resident: c.snapshot!.home('h1')!.residents.single);
      await c.idle();
      await c.syncNow();
      final item = await c.queuedItem(id);
      expect(item!.isRejected, isTrue);
      expect(item.reason, contains("already Mrs Adeyemi's"));
    });

    test('only the CSO issues cards', () async {
      await c.openShift('gu1');
      expect(() => c.issueCard(uid: '04B0000000000003', resident: c.snapshot!.home('h1')!.residents.single), throwsStateError);
    });
  });

  group('positions', () {
    setUp(boot);

    test('recorded only during an open rider shift, sent, and stopped the moment it ends', () async {
      await c.openShift('gu1');
      await c.idle();
      expect(location.asked, 0, reason: 'a guard shift never asks for location');
      location.at(now);
      await c.endShift();
      await c.idle();

      await c.openShift('ri1', shuttleId: 'bike1');
      await c.idle();
      await pumpEventQueue();
      expect(location.listening, isTrue);
      final shiftId = c.shift!.id;
      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(seconds: 15));
        location.at(now);
        await pumpEventQueue();
        await c.idle();
      }
      expect(api.positionBatches.expand((b) => b.$2), hasLength(3));
      expect(api.positionBatches.every((b) => b.$1 == shiftId), isTrue);

      await c.endShift();
      expect(location.listening, isFalse, reason: 'the foreground service stops with the shift');
      location.at(now.add(const Duration(seconds: 15)));
      await c.idle();
      expect(await store.positions(), isEmpty);
      expect(api.positionBatches.expand((b) => b.$2), hasLength(3));
    });

    test('a faster fix than 15 seconds is skipped', () async {
      await c.openShift('ri1', shuttleId: 'bike1');
      await c.idle();
      api.positionError = NetworkException('offline');
      location.at(now);
      location.at(now.add(const Duration(seconds: 5)));
      location.at(now.add(const Duration(seconds: 15)));
      await pumpEventQueue();
      expect(await store.positions(), hasLength(2));
    });

    test('offline: kept two hours at most, then sent oldest first in batches of 200, before the shift end', () async {
      api.syncError = NetworkException('offline');
      api.positionError = NetworkException('offline');
      api.stateError = NetworkException('offline');
      await c.openShift('ri1', shuttleId: 'bike1');
      final shiftId = c.shift!.id;
      await pumpEventQueue();
      final start = now;
      // 3 hours of points, every 15 seconds.
      for (var i = 0; i < 720; i++) {
        now = start.add(Duration(seconds: 15 * i));
        location.at(now);
        await pumpEventQueue(times: 2);
      }
      await pumpEventQueue();
      final kept = await store.positions();
      expect(kept.length, lessThanOrEqualTo(481));
      expect(kept.first.fix.at.isBefore(now.subtract(PositionReporter.keep)), isFalse);

      await c.endShift();
      await c.idle();
      api.syncError = null;
      api.positionError = null;
      api.stateError = null;
      final syncsBefore = api.syncBodies.length;
      await c.syncNow();
      await c.idle();
      final batches = api.positionBatches;
      expect(api.positionAfterSyncs.toSet(), {syncsBefore + 1}, reason: 'after the first push, before the shift end');
      expect(api.syncBodies.length, syncsBefore + 2);
      expect(batches.map((b) => b.$2.length).every((n) => n <= 200), isTrue);
      expect(batches.expand((b) => b.$2).length, kept.length);
      final times = [for (final b in batches) ...b.$2.map((p) => p.at)];
      expect(times, [...times]..sort(), reason: 'oldest first');
      expect(batches.every((b) => b.$1 == shiftId), isTrue);
      // The shift's start went before the points, its end after them.
      final shiftBodies = [for (final b in api.syncBodies.skip(syncsBefore)) ...(b['shifts'] as List).cast<Map>()];
      expect(shiftBodies.last['ended_at'], isNotNull);
      expect(api.syncBodies.skip(syncsBefore).last['shifts'], isNotEmpty, reason: 'the end is the last push');
      expect(await store.positions(), isEmpty);
    });

    test('409 while the shift has not synced keeps the points; 403 or a closed shift drops them', () async {
      api.syncError = NetworkException('offline');
      await c.openShift('ri1', shuttleId: 'bike1');
      await c.idle();
      await pumpEventQueue();
      api.positionStatuses.add(409);
      location.at(now);
      await pumpEventQueue();
      expect(api.positionStatuses, isEmpty, reason: 'sent, and refused');
      expect(await store.positions(), hasLength(1), reason: 'the shift start is still queued');

      api.syncError = null;
      await c.syncNow(); // the shift goes up; then the points
      expect(await store.positions(), isEmpty);

      now = now.add(const Duration(seconds: 15));
      location.at(now);
      await pumpEventQueue();
      api.positionStatuses.add(403);
      now = now.add(const Duration(seconds: 15));
      location.at(now);
      await pumpEventQueue();
      expect(api.positionStatuses, isEmpty);
      expect(await store.positions(), isEmpty);
    });

    test('refused location: the rider is told, and Turn on asks again', () async {
      location.access = LocationAccess.denied;
      await c.openShift('ri1', shuttleId: 'bike1');
      await pumpEventQueue();
      expect(c.locationProblem, LocationAccess.denied);
      api.etag = '"changed"';
      await c.syncNow();
      expect(location.asked, 1, reason: 'not asked again on every sync');
      location.access = LocationAccess.granted;
      await c.retryLocation();
      expect(c.locationProblem, isNull);
      expect(location.listening, isTrue);
    });
  });

  test('no shuttle in the state: nothing of it shows and a rider gets no tracking', () async {
    await boot();
    api.state = sampleState();
    api.etag = '"none"';
    await c.syncNow();
    expect(c.shuttle, isNull);
    expect(c.rides.open, isEmpty);
    expect(c.waitingRides, isEmpty);
  });
}
