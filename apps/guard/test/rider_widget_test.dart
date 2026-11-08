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
import 'package:gatelog_guard/ui/kit.dart';
import 'package:gatelog_guard/ui/screens/rider_start_screen.dart';
import 'package:gatelog_guard/ui/widgets.dart';

import 'support.dart';

const rideA = '5b7a8f40-1c2d-4e5f-8a9b-0c1d2e3f4a5b';
const rideB = '6c8b9051-2d3e-4f60-9bac-1d2e3f4a5b6c';

void main() {
  final spoken = <String>[];
  setUp(() {
    spoken.clear();
    dial = (n) async => true;
    speak = (s) async => spoken.add(s);
    openFrontCamera = () async => null; // no camera in a test: the shift starts without a photo
  });

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
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapDigits(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Finder yes() => find.text('Yes').last;
  Finder no() => find.text('No').last;

  // 360dp and 320dp wide.
  for (final size in const [Size(720, 1520), Size(640, 1136)]) {
    testWidgets('rider (${size.width ~/ 2}dp): face, PIN, motorcycle; one ride at a time; taken by; card; arrived; flagged down with the home PIN', (
      tester,
    ) async {
      final now = DateTime.now().toUtc();
      String ago(int min) => now.subtract(Duration(minutes: min)).toIso8601String();
      final api = FakeApi()
        ..state = sampleState(
          shuttle: sampleShuttle(
            cardHash: cardHash('e1', cardUid),
            rides: [
              sampleRide(rideA, wantedAt: ago(12), note: 'Bring the helmet'),
              sampleRide(rideB, kind: 'delivery', source: 'gate', fromHome: false, passenger: 'Jumia parcel', wantedAt: ago(3)),
            ],
          ),
          houseCodeHash: makePinHash('4821', iterations: 1000),
        );
      // Ade got the parcel first.
      api.onSync = (body) {
        final lost = {
          for (final e in (body['ride_events'] as List).cast<Map>())
            if (e['event'] == 'accept' && e['ride_id'] == rideB) e['id'] as String: 'taken by Ade Rider',
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
      final (c, store) = await boot(tester, api, size);

      // Riders start on their own screen: tap your face, PIN, motorcycle.
      expect(find.text('Kunle Rider'), findsNothing, reason: 'not in the guards list');
      await act(tester, find.text('Shuttle rider'));
      expect(find.text('Tap your face'), findsOneWidget);
      expect(find.text('Photo is taken when you start'), findsOneWidget);
      await act(tester, find.text('Kunle Rider'));
      expect(find.text('Your PIN'), findsOneWidget);
      await tapDigits(tester, '111111');
      expect(find.text('Wrong PIN, try again'), findsOneWidget);
      expect(spoken.last, 'Wrong PIN, try again.');
      await tapDigits(tester, '482913');
      expect(find.text('Which motorcycle?'), findsOneWidget);
      expect(find.text('S2'), findsOneWidget);
      await act(tester, find.text('S1'));
      expect(c.shift!.shuttleId, 'bike1');
      expect(c.shift!.selfieTaken, isFalse);

      // One ride at a time: Take it? Yes or No.
      expect(find.text('Take it?'), findsOneWidget);
      expect(find.text('1 OF 2'), findsOneWidget);
      expect(find.text('WAITING 12 MIN'), findsOneWidget);
      expect(find.text('Bring the helmet'), findsOneWidget);
      expect(spoken.last, contains('Take it?'));
      await act(tester, no());
      expect(find.text('2 OF 2'), findsOneWidget);
      expect(find.text('Jumia parcel'), findsOneWidget);

      // Taken by another rider: said, shown, gone.
      await act(tester, yes());
      expect(find.text('Taken by Ade Rider'), findsOneWidget);
      expect(spoken, contains('Taken by Ade Rider'));
      await act(tester, find.text('OK'));
      expect(find.text('No more rides.'), findsOneWidget);
      // From here the rider has no network: the queue works offline.
      api.syncError = NetworkException('offline');
      await act(tester, find.text('See them again'));
      expect(find.text('1 OF 1'), findsOneWidget);
      await act(tester, yes());
      expect(spoken, contains('Ride taken.'));

      // Picked up: tap their card (the debug-only typed UID stands in for NFC).
      expect(find.text('Tap their card'), findsOneWidget);
      expect(find.text('No card'), findsOneWidget);
      expect(find.text('Hand back'), findsOneWidget);
      expect(find.text('Nobody came'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '04:a2:1b:7c:55:80');
      await act(tester, find.text('Use'));
      expect(find.text('Is this them?'), findsOneWidget);
      expect(spoken.last, 'Card is Mrs Adeyemi, 14B.');
      await act(tester, yes());
      expect(spoken, contains('Picked up.'));
      expect(find.text('Did they arrive?'), findsOneWidget);
      await act(tester, yes());
      expect(spoken, contains('Dropped off.'));
      expect(find.text('No rides now.'), findsOneWidget);

      // Flagged down: no card, the house, the code (one wrong try), who, from, to.
      await act(tester, find.text('New ride'));
      await act(tester, find.text('No card'));
      expect(find.text('14B'), findsOneWidget, reason: 'one street: straight to the house numbers');
      await act(tester, find.text('14B'));
      expect(find.text('HOME PIN'), findsOneWidget);
      await tapDigits(tester, '0000');
      expect(find.text('Wrong PIN, try again'), findsOneWidget);
      expect(spoken.last, 'Wrong PIN, try again.');
      await tapDigits(tester, '4821');
      expect(find.text('Is it Mrs Adeyemi?'), findsOneWidget);
      await act(tester, yes());
      expect(find.text('Picking up at their house?'), findsOneWidget);
      await act(tester, yes());
      expect(find.text('Going to Main gate?'), findsOneWidget);
      await act(tester, no());
      expect(find.text('Going to Clubhouse?'), findsOneWidget);
      await act(tester, yes());
      expect(spoken, contains('Ride started.'));
      expect(find.text('Did they arrive?'), findsOneWidget);

      final queued = (await tester.runAsync(() => store.outbox()))!;
      final events = [
        for (final i in queued)
          if (i.kind == OutboxKind.rideEvent) i.payload,
      ];
      final cardPickup = events.firstWhere((e) => e['event'] == 'pick_up' && e['ride_id'] == rideA);
      expect(cardPickup['confirmed_by'], 'card');
      expect(cardPickup['card_id'], 'card1');
      expect(events.where((e) => e['ride_id'] == rideA).map((e) => e['event']), ['accept', 'pick_up', 'drop_off']);
      final flag = [
        for (final i in queued)
          if (i.kind == OutboxKind.ride) i.payload,
      ].single;
      expect(flag['source'], 'flag');
      expect(flag['pickup'], {'kind': 'home', 'ref': 'h1'});
      expect(flag['dropoff'], {'kind': 'place', 'ref': 'pl1'});
      final flagPickup = events.firstWhere((e) => e['ride_id'] == flag['id']);
      expect(flagPickup['confirmed_by'], 'house_code');
      expect(flagPickup['resident_id'], 'r1');
      expect(events.toString(), isNot(contains('04A21B')), reason: 'no raw card UID leaves the phone');
      final pinChecks = [
        for (final i in queued)
          if (i.kind == OutboxKind.pinCheck) i.payload,
      ];
      expect(pinChecks.map((p) => (p['ok'], p['context'], p['home_id'])), [(false, 'shuttle', 'h1'), (true, 'shuttle', 'h1')]);
      expect(spoken.join(' '), isNot(contains('4821')), reason: 'a home PIN is never read aloud');

      // End: Yes or No, then who takes over.
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await act(tester, find.text('End my shift'));
      expect(find.text('End your shift?'), findsOneWidget);
      await act(tester, yes());
      expect(find.text('Is Ade Rider taking over?'), findsOneWidget);
      await act(tester, no());
      expect(find.text('Start your shift'), findsOneWidget);
      expect(c.shift, isNull);

      expect(tester.takeException(), isNull);
      await finish(tester, c, store);
    });
  }

  testWidgets('day and night tokens: charcoal at night, white by day', (tester) async {
    final api = FakeApi()..state = sampleState(shuttle: sampleShuttle());
    final (c, store) = await boot(tester, api, const Size(640, 1136));
    for (final night in [true, false]) {
      Palette.forceNight = night;
      await act(tester, find.text('Shuttle rider'));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
      expect(scaffold.backgroundColor, night ? const Color(0xFF111111) : const Color(0xFFF2F2F0));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
    Palette.forceNight = null;
    expect(Palette.at(DateTime(2026, 11, 8, 21)).night, isTrue);
    expect(Palette.at(DateTime(2026, 11, 8, 12)).night, isFalse);
    await finish(tester, c, store);
  });

  testWidgets('guard: Shuttle to the home from the menu (no typing), and after letting a guest in', (tester) async {
    final api = FakeApi()
      ..state = sampleState(shuttle: sampleShuttle())
      ..syncError = NetworkException('offline');
    final (c, store) = await boot(tester, api, const Size(640, 1136));
    await tester.runAsync(() => c.openShift('gu1'));
    await tester.pump();
    expect(find.text('Shuttle to the home'), findsNothing, reason: 'not on the keypad screen');

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await act(tester, find.text('Shuttle to the home'));
    await act(tester, find.text('14B'));
    expect(find.text('Parcel or guest?'), findsOneWidget);
    await act(tester, find.text('Parcel'));
    expect(find.text('Book the shuttle?'), findsOneWidget);
    await act(tester, yes());
    expect(spoken, contains('Shuttle booked.'));
    expect(find.text('Shuttle booked: parcel to 14B Adeniyi Close, Block C'), findsOneWidget);

    // No code, confirmed, let in: then the shuttle, with the guest's name.
    await act(tester, find.text('No code'));
    await tester.enterText(find.byType(TextField), 'adey');
    await tester.pump();
    await act(tester, find.text('14B Adeniyi Close, Block C'));
    await act(tester, find.text('Call'));
    await act(tester, find.text('Confirmed'));
    await tester.enterText(find.byType(TextField), 'Tunde');
    await act(tester, find.text('Next'));
    await act(tester, find.text('They are here: let them in'));
    expect(find.text('Let in: Tunde'), findsOneWidget);
    await act(tester, find.text('Shuttle to the home'));
    expect(find.text('Tunde'), findsOneWidget);
    await act(tester, yes());
    expect(find.text('No code'), findsOneWidget, reason: 'back on the keypad');

    final rides = [
      for (final i in (await tester.runAsync(() => store.outbox()))!)
        if (i.kind == OutboxKind.ride) i.payload,
    ];
    expect(rides.map((r) => (r['kind'], r['passenger'], r['source'])), [('delivery', null, 'gate'), ('guest', 'Tunde', 'gate')]);
    expect(tester.takeException(), isNull);
    await finish(tester, c, store);
  });

  testWidgets('CSO (320dp): waiting rides on Now, Shuttle tab, Book a ride and Issue a card by Yes or No', (tester) async {
    final now = DateTime.now().toUtc();
    final api = FakeApi()
      ..state = sampleState(
        shuttle: sampleShuttle(
          rides: [
            sampleRide(rideA, wantedAt: now.subtract(const Duration(minutes: 25)).toIso8601String()),
            sampleRide(rideB, state: 'accepted', riderId: 'ri1', rider: 'Kunle Rider', wantedAt: now.toIso8601String()),
          ],
        ),
      )
      ..csoBody = {
        ...sampleCso(),
        'needs': {
          ...(sampleCso()['needs'] as Map<String, dynamic>),
          'rides_waiting': [
            {
              'ride_id': rideA,
              'kind': 'resident',
              'from': '14B Adeniyi Close, Block C',
              'to': 'Main gate',
              'wanted_at': now.subtract(const Duration(minutes: 25)).toIso8601String(),
            },
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

    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.byIcon(Icons.two_wheeler)));
    await tester.pumpAndSettle();
    expect(find.text('WAITING OVER 10 MIN · 1'), findsOneWidget);
    expect(find.text('OPEN RIDES · 2', skipOffstage: false), findsOneWidget);
    expect(find.text('Taken by Kunle Rider', skipOffstage: false), findsOneWidget);

    await act(tester, find.text('Book a ride'));
    await act(tester, find.text('14B'));
    expect(find.text('Did Mrs Adeyemi ring?'), findsOneWidget);
    await act(tester, yes());
    expect(find.text('Pick up at home?'), findsOneWidget);
    await act(tester, yes());
    expect(find.text('Going to Main gate?'), findsOneWidget);
    await act(tester, no());
    await act(tester, yes()); // Clubhouse
    expect(find.text('Now?'), findsOneWidget);
    await act(tester, no());
    expect(find.text('In 30 minutes?'), findsOneWidget);
    await act(tester, yes());
    expect(find.text('Book this ride?'), findsOneWidget);
    await act(tester, yes());
    expect(spoken, contains('Ride booked.'));
    final booked = [for (final b in api.syncBodies) ...(b['rides'] as List).cast<Map>()].single;
    expect(booked['source'], 'dispatch');
    expect(booked['resident_id'], 'r1');
    expect(booked['dropoff'], {'kind': 'place', 'ref': 'pl1'});
    expect(booked['wanted_at'], isNotNull);

    await act(tester, find.text('Issue a card'));
    expect(find.text('Tap the new card'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '04B0000000000007');
    await act(tester, find.text('Use'));
    await act(tester, find.text('14B'));
    expect(find.text('Give the card to Mrs Adeyemi?'), findsOneWidget);
    await act(tester, yes());
    await tester.runAsync(() => c.idle());
    await tester.pumpAndSettle();
    expect(find.text('Card issued'), findsOneWidget);
    expect(spoken.last, 'Card issued to Mrs Adeyemi, 14B');
    final card = [for (final b in api.syncBodies) ...(b['cards'] as List).cast<Map>()].single;
    expect(card['uid_last4'], '0007');
    await act(tester, find.text('Done'));

    expect(tester.takeException(), isNull);
    await finish(tester, c, store);
  });
}
