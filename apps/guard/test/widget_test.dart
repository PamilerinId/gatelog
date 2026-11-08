import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/core/codes.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/data/secrets.dart';
import 'package:gatelog_guard/data/store.dart';
import 'package:gatelog_guard/sync/api.dart';
import 'package:gatelog_guard/ui/app.dart';
import 'package:gatelog_guard/ui/widgets.dart';

import 'support.dart';

const visitId = '9d0e7c6b-5a49-4382-a716-2f5e4d3c2b1a';

Map<String, dynamic> visit(int ws, int we, {String state = 'expected', String? entryId}) => {
      'id': visitId,
      'home_id': 'h1',
      'resident_id': 'r1',
      'guest_name': 'Tunde Bakare',
      'window_start': ws,
      'window_end': we,
      'key_version': 1,
      'code_issued': true,
      'source': 'whatsapp',
      'state': state,
      'expected_until': null,
      'entry_id': entryId,
      'entered_at': null,
    };

void main() {
  final dialled = <String>[];
  setUp(() {
    dialled.clear();
    dial = (n) async {
      dialled.add(n);
      return true;
    };
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

  /// Lets any sync still running finish before the database closes. Syncs started from a tap
  /// run in the fake zone (frames move them on); ones started in runAsync need real time.
  Future<void> finish(WidgetTester tester, GateController c, GateStore store) async {
    for (var i = 0; i < 200 && (i < 10 || c.busy); i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    expect(c.busy, isFalse);
    c.dispose();
    await tester.runAsync(() => store.db.close());
  }

  /// A tap that records something. The in-memory database and the fake API complete on
  /// microtasks, so pumping frames lets the whole chain (record, sync, pull) finish.
  Future<void> act(WidgetTester tester, GateController c, Finder target) async {
    await tester.tap(target);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// The last digit completes the entry (PIN check or save), so it is an [act]. Digits are
  /// found on the keypad only: the sync chip shows the queued count as a bare number.
  Finder key(String d) => find.descendant(of: find.byType(Keypad), matching: find.text(d));

  Future<void> typeDigits(WidgetTester tester, String digits, GateController c) async {
    final all = digits.split('');
    for (final d in all.take(all.length - 1)) {
      await tester.tap(key(d));
      await tester.pump();
    }
    await act(tester, c, key(all.last));
  }


  // 360dp and 320dp wide: common cheap Android phones.
  for (final size in const [Size(720, 1520), Size(640, 1136)]) {
    testWidgets('start a shift with PIN and no camera, let a coded guest in, see them in Leaving (${size.width ~/ 2}dp)', (tester) async {
      final now = DateTime.now().toUtc();
      final ws = now.millisecondsSinceEpoch ~/ 1000 - 600, we = ws + 7200;
      final api = FakeApi()
        ..state = sampleState(visits: [visit(ws, we)])
        ..syncError = NetworkException('offline'); // the gate works with no network
      final (c, store) = await boot(tester, api, size);

      expect(find.text('Start your shift'), findsOneWidget);
      // No consent: blocked with a clear message.
      await tester.tap(find.text('New Guard'));
      await tester.pumpAndSettle();
      expect(find.text('Ask the estate admin to record your consent form first.'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Musa Ibrahim'));
      await tester.pump();
      expect(find.text('Enter your PIN'), findsOneWidget);
      await typeDigits(tester, '111111', c);
      expect(find.text('Wrong PIN. 4 tries left.'), findsOneWidget);
      await typeDigits(tester, '482913', c);

      // The camera is not there in a test (its call times out): the shift still starts,
      // marked "no selfie".
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      expect(find.text('The camera is not working'), findsOneWidget);
      await act(tester, c, find.text('Start shift'));
      expect(c.shift!.selfieTaken, isFalse);
      expect(find.text('On duty: Musa Ibrahim'), findsOneWidget);
      expect(find.text('No code'), findsOneWidget);
      expect(find.text('Leaving'), findsOneWidget);
      // The old tabs are gone.
      expect(find.text('Inside'), findsNothing);
      expect(find.text('Phone'), findsNothing);

      final code = deriveCode(List<int>.generate(32, (i) => i), 'h1', visitId, ws, we);
      await typeDigits(tester, code, c);
      expect(find.text('Code OK'), findsOneWidget);
      expect(find.text('Tunde Bakare'), findsOneWidget);
      expect(find.text('14B Adeniyi Close, Block C'), findsOneWidget);
      expect(find.text('Turn away'), findsOneWidget);

      // The plate is collapsed until asked for.
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Vehicle plate'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'kja 456-xy');
      await tester.pump();
      expect(find.text('Registered to this home: Black Corolla'), findsOneWidget);

      await tester.ensureVisible(find.text('Let them in'));
      await act(tester, c, find.text('Let them in'));
      expect(find.text('Let in: Tunde Bakare'), findsOneWidget);
      final entry = (await tester.runAsync(() => store.outbox()))!.firstWhere((i) => i.kind == OutboxKind.entry).payload;
      expect(entry['plate'], 'kja 456-xy');
      expect(entry['shift_id'], c.shift!.id);

      await tester.tap(find.text('Leaving'));
      await tester.pumpAndSettle();
      expect(find.text('Tunde Bakare'), findsOneWidget);
      await act(tester, c, find.text('Tunde Bakare'));
      expect(find.text('Left: Tunde Bakare'), findsOneWidget);
      expect(c.view.inside, isEmpty);

      // Emergency numbers and End my shift live in the menu.
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emergency numbers'));
      await tester.pumpAndSettle();
      expect(find.text('Police'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End my shift'));
      await tester.pumpAndSettle();
      expect(find.text('Who is taking over?'), findsOneWidget);
      expect(find.text('Sunday Etim'), findsOneWidget);
      expect(find.text('New Guard'), findsNothing, reason: 'no consent, cannot take over');
      await act(tester, c, find.text('Sunday Etim'));
      expect(find.text('Start your shift'), findsOneWidget);
      final end = (await tester.runAsync(() => store.outbox()))!.lastWhere((i) => i.kind == OutboxKind.shift).payload;
      expect(end['handed_to'], 'gu2');
      expect(end['end_reason'], 'handover');

      expect(tester.takeException(), isNull);
      await finish(tester, c, store);
    });
  }

  testWidgets('No code: call the home, confirmed, they are here: let them in', (tester) async {
    final api = FakeApi()
      ..state = sampleState()
      ..syncError = NetworkException('offline');
    final (c, store) = await boot(tester, api, const Size(720, 1520));
    await tester.runAsync(() => c.openShift('gu1'));
    await tester.pump();

    await tester.tap(find.text('No code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'adey');
    await tester.pump();
    await tester.tap(find.text('14B Adeniyi Close, Block C'));
    await tester.pumpAndSettle();
    expect(find.text('Mrs Adeyemi'), findsOneWidget);
    expect(find.textContaining('4567'), findsOneWidget);
    expect(find.textContaining('8031234567'), findsNothing, reason: 'never more than the last 4 digits on screen');

    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();
    expect(dialled, ['+2348031234567']);
    expect(find.text('What did they say?'), findsOneWidget);

    // No answer once: try again.
    await act(tester, c, find.text('No answer'));
    expect(find.text('No answer'), findsOneWidget);
    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmed'));
    await tester.pumpAndSettle();
    expect(find.text('Who is the guest?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Chidi');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed by Mrs Adeyemi'), findsOneWidget);
    expect(find.text('Coming later: expect them'), findsOneWidget);

    await act(tester, c, find.text('They are here: let them in'));
    expect(find.text('Let in: Chidi'), findsOneWidget);
    final items = (await tester.runAsync(() => store.outbox()))!;
    expect(items.where((i) => i.kind == OutboxKind.callback).map((i) => i.payload['outcome']), ['no_answer', 'confirmed']);
    final entry = items.firstWhere((i) => i.kind == OutboxKind.entry).payload;
    expect(entry['method'], 'callback_confirmed');
    expect(entry['visit_id'], isNull);

    expect(tester.takeException(), isNull);
    await finish(tester, c, store);
  });

  testWidgets('No code: said no shows the walk-in rule; the CSO decides to let them in', (tester) async {
    final api = FakeApi()
      ..state = sampleState()
      ..syncError = NetworkException('offline');
    final (c, store) = await boot(tester, api, const Size(720, 1520));
    await tester.runAsync(() => c.openShift('gu1'));
    await tester.pump();

    await tester.tap(find.text('No code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14B Adeniyi Close, Block C'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();
    await act(tester, c, find.text('Said no'));
    expect(find.text('Do not let them in on the phone'), findsOneWidget);
    expect(find.text('Do not admit.'), findsOneWidget, reason: 'the estate walk-in policy');

    await tester.tap(find.text('CSO decided: let them in'));
    await tester.pumpAndSettle();
    final button = find.ancestor(of: find.text('Let them in'), matching: find.byWidgetPredicate((w) => w is FilledButton));
    expect(tester.widget<FilledButton>(button).onPressed, isNull, reason: 'needs who decided and why');
    await tester.enterText(find.widgetWithText(TextField, 'Guest name'), 'Electrician');
    await tester.tap(find.text('Mr Bello'));
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Reason (required)'), 'Estate electrician');
    await tester.pump();
    await tester.ensureVisible(button);
    await act(tester, c, button);

    final entry = (await tester.runAsync(() => store.outbox()))!.firstWhere((i) => i.kind == OutboxKind.entry).payload;
    expect(entry['method'], 'walk_in_admitted');
    expect(entry['decided_by'], 'cso1');
    expect(entry['reason'], 'Estate electrician');

    expect(tester.takeException(), isNull);
    await finish(tester, c, store);
  });

  testWidgets('the CSO sets a PIN and gets the CSO view: Now, People, Shifts', (tester) async {
    final api = FakeApi()..state = sampleState();
    final (c, store) = await boot(tester, api, const Size(720, 1520));

    await tester.tap(find.text('Mr Bello'));
    await tester.pump();
    expect(find.text('Choose a 6-digit PIN'), findsOneWidget);
    await typeDigits(tester, '246810', c);
    expect(find.text('Enter the same PIN again'), findsOneWidget);
    await typeDigits(tester, '246811', c);
    expect(find.text('The two PINs were different. Start again.'), findsOneWidget);
    await typeDigits(tester, '246810', c);
    await typeDigits(tester, '246810', c);
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    await act(tester, c, find.text('Start shift'));
    // The Now tab fetches /cso when it opens; let that finish.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(c.isCso, isTrue);
    for (final tab in ['Gate', 'Now', 'People', 'Shifts', 'Numbers']) {
      expect(find.text(tab), findsWidgets);
    }
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.textContaining('Updated '), findsOneWidget);
    expect(find.text('Past their time (1)'), findsOneWidget);
    expect(find.text('Tunde Bakare'), findsOneWidget);
    expect(find.text('Gate phones not syncing (1)'), findsOneWidget);
    expect(api.csoShiftIds.last, c.shift!.id);

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    expect(find.text('Add a guest'), findsOneWidget);
    await tester.tap(find.text('Turned away'));
    await tester.pumpAndSettle();
    expect(find.text('Hawker'), findsOneWidget);

    await act(tester, c, find.text('Shifts'));
    expect(find.text('Handed over to Mr Bello'), findsOneWidget);
    expect(find.text('2 inside, 0 not sent, 1 on the night list'), findsOneWidget);

    await tester.tap(find.text('Gate'));
    await tester.pumpAndSettle();
    expect(find.text('No code'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await finish(tester, c, store);
  });
}
