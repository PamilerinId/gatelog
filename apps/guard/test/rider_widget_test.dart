import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/core/card.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/core/pin.dart';
import 'package:gatelog_guard/data/secrets.dart';
import 'package:gatelog_guard/data/store.dart';
import 'package:gatelog_guard/sync/api.dart';
import 'package:gatelog_guard/ui/app.dart';
import 'package:gatelog_guard/ui/widgets.dart';

import 'support.dart';

const rideA = '5b7a8f40-1c2d-4e5f-8a9b-0c1d2e3f4a5b';
const rideB = '6c8b9051-2d3e-4f60-9bac-1d2e3f4a5b6c';

void main() {
  setUp(() => dial = (n) async => true);

  Future<(GateController, GateStore)> boot(WidgetTester tester, FakeApi api, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    initTimeZones();
    final store = memoryStore();
    final c = GateController(store: store, secrets: Secrets(MemorySecretStore()), api: api, pins: fastPins);
    await tester.runAsync(() async {
      await c.init();
      await c.pair('ABCD-2345');
      await c.idle();
    });
    await tester.pumpWidget(GuardApp(controller: c));
    return (c, store);
  }

  Future<void> finish(WidgetTester tester, GateController c, GateStore store) async {
    for (var i = 0; i < 200 && (i < 10 || c.busy); i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(c.busy, isFalse);
    c.dispose();
    await tester.runAsync(() => store.db.close());
  }

  /// A tap that records something: let the record, the sync and the pull finish.
  Future<void> act(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Scrolls [target] to the middle of its list, so a tap lands on it and not on the dock.
  Future<void> reveal(WidgetTester tester, Finder target) async {
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
  }

  Future<void> go(WidgetTester tester, Finder target) async {
    await reveal(tester, target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Finder key(String d) => find.descendant(of: find.byType(Keypad), matching: find.text(d));

  Future<void> typeDigits(WidgetTester tester, String digits) async {
    final all = digits.split('');
    for (final d in all.take(all.length - 1)) {
      await tester.tap(key(d));
      await tester.pump();
    }
    await act(tester, key(all.last));
  }

  // 360dp and 320dp wide.
  for (final size in const [Size(720, 1520), Size(640, 1136)]) {
    testWidgets('rider: shift on S1, taken by another, card pickup, drop-off, flagged down with the house code (${size.width ~/ 2}dp)', (tester) async {
      final now = DateTime.now().toUtc();
      String ago(int min) => now.subtract(Duration(minutes: min)).toIso8601String();
      final api = FakeApi()
        ..state = sampleState(
          shuttle: sampleShuttle(cardHash: cardHash('e1', cardUid), rides: [
            sampleRide(rideA, wantedAt: ago(12), note: 'Bring the helmet'),
            sampleRide(rideB, kind: 'delivery', source: 'gate', fromHome: false, passenger: 'Jumia parcel', wantedAt: ago(3)),
          ]),
          houseCodeHash: makePinHash('4821', iterations: 1000),
        );
      // Ade got the parcel first.
      api.onSync = (body) {
        final lost = {
          for (final e in (body['ride_events'] as List).cast<Map>())
            if (e['event'] == 'accept' && e['ride_id'] == rideB) e['id'] as String: 'taken by Ade Rider',
        };
        return SyncResult(accepted: [for (final id in FakeApi.idsIn(body)) if (!lost.containsKey(id)) id], duplicates: const [], rejected: lost);
      };
      final (c, store) = await boot(tester, api, size);

      // Start: name, PIN, no camera, then the motorcycle.
      expect(find.text('Shuttle rider'), findsWidgets);
      await tester.tap(find.text('Kunle Rider'));
      await tester.pump();
      await typeDigits(tester, '482913');
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      await tester.tap(find.text('Start shift'));
      await tester.pumpAndSettle();
      expect(find.text('Which motorcycle are you on?'), findsOneWidget);
      expect(find.textContaining('every 15 seconds'), findsOneWidget);
      await act(tester, find.text('S1'));
      expect(c.shift!.shuttleId, 'bike1');

      // The rider view: the queue and New ride. Nothing else.
      expect(find.text('Shuttle S1'), findsOneWidget);
      expect(find.text('Rider: Kunle Rider'), findsOneWidget);
      expect(find.text('Waiting (2)'), findsOneWidget);
      expect(find.text('Waiting 12 min'), findsOneWidget);
      expect(find.text('Parcel: Jumia parcel', skipOffstage: false), findsOneWidget);
      expect(find.text('Note: Bring the helmet'), findsOneWidget);
      expect(find.text('New ride'), findsOneWidget);
      expect(find.text('No code'), findsNothing);
      expect(find.text('Take it', skipOffstage: false), findsNWidgets(2));

      // Taken by another rider: say so, drop it.
      await reveal(tester, find.text('Take it', skipOffstage: false).last);
      await act(tester, find.text('Take it').last);
      expect(find.text('Taken by Ade Rider'), findsOneWidget);
      expect(find.text('Waiting (1)'), findsOneWidget);
      expect(find.text('Jumia parcel'), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(find.text('Taken by Ade Rider'), findsNothing);
      // The rest happens with no network: the rider's phone works offline.
      api.syncError = NetworkException('offline');

      // Take the resident's ride: Picked up, Hand back, No-show.
      await reveal(tester, find.text('Take it'));
      await act(tester, find.text('Take it'));
      expect(find.text('Your ride'), findsOneWidget);
      expect(find.text('Hand back'), findsOneWidget);
      expect(find.text('No-show'), findsOneWidget);
      expect(find.text('No rides waiting.'), findsOneWidget);

      // Who rode: the estate card. No NFC in a test; the debug-only typed UID stands in.
      await go(tester, find.text('Picked up'));
      expect(find.text('Who is riding?'), findsOneWidget);
      await go(tester, find.text('Estate card'));
      expect(find.text('This phone cannot read cards'), findsOneWidget);
      expect(find.text('Test build only: type a card UID'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '04:a2:1b:7c:55:80');
      await go(tester, find.text('Use this UID'));
      expect(find.text('Mrs Adeyemi'), findsOneWidget);
      await act(tester, find.text('Yes, this is them'));
      await tester.pumpAndSettle();
      expect(find.text('Dropped off'), findsOneWidget);
      expect(find.text('Under way'), findsOneWidget);

      await reveal(tester, find.text('Dropped off'));
      await act(tester, find.text('Dropped off'));
      expect(find.text('Dropped off at Main gate'), findsOneWidget);
      expect(find.text('Your ride'), findsNothing);

      // Flagged down: house code (one wrong try), then from and to.
      await go(tester, find.text('New ride'));
      await go(tester, find.text('House code'));
      await tester.enterText(find.byType(TextField), '14b');
      await tester.pump();
      await go(tester, find.text('14B Adeniyi Close, Block C'));
      expect(find.text('Ask for the 4-digit house code'), findsOneWidget);
      await typeDigits(tester, '0000');
      expect(find.text('Wrong code. 4 tries left.'), findsOneWidget);
      await typeDigits(tester, '4821');
      await tester.pumpAndSettle();
      expect(find.text('Who is it?'), findsOneWidget);
      await go(tester, find.text('Mrs Adeyemi'));
      expect(find.text('Where are you picking them up?'), findsOneWidget);
      await go(tester, find.text('Their home'));
      expect(find.text('Where are they going?'), findsOneWidget);
      expect(find.text('Their home'), findsNothing);
      await act(tester, find.text('Clubhouse'));
      await tester.pumpAndSettle();
      expect(find.text('Your ride'), findsOneWidget);
      expect(find.text('Dropped off'), findsOneWidget);

      final queued = (await tester.runAsync(() => store.outbox()))!;
      final sent = [for (final i in queued) if (i.kind == OutboxKind.rideEvent) i.payload];
      final cardPickup = sent.firstWhere((e) => e['event'] == 'pick_up' && e['ride_id'] == rideA);
      expect(cardPickup['confirmed_by'], 'card');
      expect(cardPickup['card_id'], 'card1');
      final flag = [for (final i in queued) if (i.kind == OutboxKind.ride) i.payload].single;
      expect(flag['source'], 'flag');
      expect(flag['dropoff'], {'kind': 'place', 'ref': 'pl1'});
      final flagPickup = sent.firstWhere((e) => e['ride_id'] == flag['id']);
      expect(flagPickup['confirmed_by'], 'house_code');
      expect(flagPickup['resident_id'], 'r1');
      expect(sent.toString(), isNot(contains('04A21B')), reason: 'no raw card UID leaves the phone');

      // End: another rider takes over, or nobody.
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Shuttle to the home'), findsNothing, reason: 'the gate books, not the rider');
      await tester.tap(find.text('End my shift'));
      await tester.pumpAndSettle();
      expect(find.text('Ade Rider'), findsOneWidget);
      expect(find.text('Musa Ibrahim'), findsNothing);
      await act(tester, find.text('Nobody'));
      expect(find.text('Start your shift'), findsOneWidget);

      expect(tester.takeException(), isNull);
      await finish(tester, c, store);
    });
  }

  testWidgets('guard: Shuttle to the home from the menu, and after letting a guest in (No code)', (tester) async {
    final api = FakeApi()
      ..state = sampleState(shuttle: sampleShuttle())
      ..syncError = NetworkException('offline');
    final (c, store) = await boot(tester, api, const Size(640, 1136));
    await tester.runAsync(() => c.openShift('gu1'));
    await tester.pump();
    expect(find.text('Shuttle to the home'), findsNothing, reason: 'not on the keypad screen');

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await go(tester, find.text('Shuttle to the home'));
    await go(tester, find.text('14B Adeniyi Close, Block C'));
    expect(find.text('Parcel'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'What is the parcel?'), 'Jumia parcel');
    await tester.pump();
    await act(tester, find.text('Book the shuttle'));
    await tester.pumpAndSettle();
    expect(find.text('Shuttle booked: parcel to 14B Adeniyi Close, Block C'), findsOneWidget);

    // No code, confirmed, let in: then the shuttle, with the guest's name.
    await go(tester, find.text('No code'));
    await tester.enterText(find.byType(TextField), 'adey');
    await tester.pump();
    await go(tester, find.text('14B Adeniyi Close, Block C'));
    await go(tester, find.text('Call'));
    await act(tester, find.text('Confirmed'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Tunde');
    await go(tester, find.text('Next'));
    await act(tester, find.text('They are here: let them in'));
    await tester.pumpAndSettle();
    expect(find.text('Let in: Tunde'), findsOneWidget);
    await go(tester, find.text('Shuttle to the home'));
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Guest name')).controller!.text, 'Tunde');
    await act(tester, find.text('Book the shuttle'));
    await tester.pumpAndSettle();
    expect(find.text('No code'), findsOneWidget, reason: 'back on the keypad');

    final rides = [for (final i in (await tester.runAsync(() => store.outbox()))!) if (i.kind == OutboxKind.ride) i.payload];
    expect(rides.map((r) => (r['kind'], r['passenger'], r['source'])), [('delivery', 'Jumia parcel', 'gate'), ('guest', 'Tunde', 'gate')]);
    expect(tester.takeException(), isNull);
    await finish(tester, c, store);
  });

  testWidgets('CSO: Shuttle tab with open rides, waiting rides on Now, Book a ride, Issue a card (320dp)', (tester) async {
    final now = DateTime.now().toUtc();
    final api = FakeApi()
      ..state = sampleState(
        shuttle: sampleShuttle(rides: [
          sampleRide(rideA, wantedAt: now.subtract(const Duration(minutes: 25)).toIso8601String()),
          sampleRide(rideB, state: 'accepted', riderId: 'ri1', rider: 'Kunle Rider', wantedAt: now.toIso8601String()),
        ]),
      )
      ..csoBody = {
        ...sampleCso(),
        'needs': {
          ...(sampleCso()['needs'] as Map<String, dynamic>),
          'rides_waiting': [
            {'ride_id': rideA, 'kind': 'resident', 'from': '14B Adeniyi Close, Block C', 'to': 'Main gate', 'wanted_at': now.subtract(const Duration(minutes: 25)).toIso8601String()},
          ],
        },
      };
    final (c, store) = await boot(tester, api, const Size(640, 1136));
    await tester.runAsync(() async {
      await c.setGuardPin('cso1', '135790');
      await c.openShift('cso1');
      await c.idle();
    });
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Shuttle rides waiting over 10 minutes (1)', skipOffstage: false), findsOneWidget);

    await tester.tap(find.byIcon(Icons.two_wheeler));
    await tester.pumpAndSettle();
    expect(find.text('Waiting over 10 minutes (1)'), findsOneWidget);
    expect(find.text('Open rides (2)', skipOffstage: false), findsOneWidget);
    expect(find.text('Taken by Kunle Rider', skipOffstage: false), findsOneWidget);

    await go(tester, find.text('Book a ride'));
    await go(tester, find.text('14B Adeniyi Close, Block C'));
    expect(find.text('Who rang?'), findsOneWidget);
    await tester.tap(find.text('Their home').first);
    await tester.pump();
    await tester.ensureVisible(find.text('Clubhouse').last);
    await tester.tap(find.text('Clubhouse').last);
    await tester.pump();
    await act(tester, find.text('Book the ride'));
    await tester.pumpAndSettle();
    final booked = [for (final b in api.syncBodies) ...(b['rides'] as List).cast<Map>()].single;
    expect(booked['source'], 'dispatch');
    expect(booked['resident_id'], 'r1');
    expect(booked['dropoff'], {'kind': 'place', 'ref': 'pl1'});

    await go(tester, find.text('Issue a card'));
    await go(tester, find.text('Tap the card'));
    await tester.enterText(find.byType(TextField), '04B0000000000007');
    await go(tester, find.text('Use this UID'));
    expect(find.text('Card ending 0007'), findsOneWidget);
    await go(tester, find.text('Pick the resident'));
    await go(tester, find.text('14B Adeniyi Close, Block C'));
    await go(tester, find.text('Mrs Adeyemi'));
    await act(tester, find.text('Issue the card'));
    await tester.pumpAndSettle();
    expect(find.text('Card issued'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await finish(tester, c, store);
  });
}
