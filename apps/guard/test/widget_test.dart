import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/caller.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/core/codes.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/core/pin.dart';
import 'package:gatelog_guard/data/secrets.dart';
import 'package:gatelog_guard/data/store.dart';
import 'package:gatelog_guard/sync/api.dart';
import 'package:gatelog_guard/sync/capture.dart';
import 'package:gatelog_guard/ui/app.dart';
import 'package:gatelog_guard/ui/kit.dart';
import 'package:gatelog_guard/ui/widgets.dart';

import 'support.dart';

const visitId = '9d0e7c6b-5a49-4382-a716-2f5e4d3c2b1a';
final key1 = List<int>.generate(32, (i) => i); // key_b64 in sampleState

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

/// A camera that opens (so the guard sees "Photo of the visitor" and Skip) but takes nothing.
class _Camera implements GateCamera {
  @override
  Widget preview() => const ColoredBox(color: Color(0xFF333333));
  @override
  Future<Shot?> take() async => null;
  @override
  Future<void> dispose() async {}
}

class _Recorder implements ClipRecorder {
  @override
  Future<bool> start() async => true;
  @override
  Future<VoiceClip?> stop() async => VoiceClip(Uint8List.fromList(List.filled(1500, 3)));
  @override
  Future<void> dispose() async {}
}

void main() {
  final dialled = <String>[];
  final spoken = <String>[];
  final played = <int>[];
  setUp(() {
    dialled.clear();
    spoken.clear();
    played.clear();
    dial = (n) async {
      dialled.add(n);
      return true;
    };
    speak = (s) async => spoken.add(s);
    openCamera = ({required bool front}) async => null;
    newRecorder = _Recorder.new;
    playClip = (bytes, type) async => played.add(bytes.length);
  });

  Future<(GateController, GateStore)> boot(WidgetTester tester, FakeApi api, Size size, {CallerId? callerId}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    initTimeZones();
    final store = memoryStore();
    final c = GateController(store: store, secrets: Secrets(MemorySecretStore()), api: api, pins: fastPins, callerId: callerId ?? FakeCallerId());
    await tester.runAsync(() async {
      await c.init();
      await c.pair('ABCD-2345');
      await c.idle();
    });
    await tester.pumpWidget(GuardApp(controller: c));
    await tester.pumpAndSettle();
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

  /// A tap that may record something: let the record, the sync and the pull finish.
  Future<void> act(WidgetTester tester, Finder target, {bool settle = true}) async {
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (settle) await tester.pumpAndSettle();
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

  Future<List<Map<String, dynamic>>> queued(WidgetTester tester, GateStore store, String kind) async => [
    for (final i in (await tester.runAsync(() => store.outbox()))!)
      if (i.kind == kind) i.payload,
  ];

  /// A shift opened through the screens: the face, the PIN. Then the gate goes offline, so
  /// what it records stays in the queue for the test to read.
  Future<void> startAs(WidgetTester tester, FakeApi api, [String name = 'Musa Ibrahim']) async {
    await act(tester, find.text(name));
    await tapDigits(tester, '482913');
    api.syncError = NetworkException('offline');
  }

  // 360dp and 320dp wide: common cheap Android phones.
  for (final size in const [Size(720, 1520), Size(640, 1136)]) {
    final dp = size.width ~/ 2;

    testWidgets('($dp dp) shift start, home, a code let in, the guest leaving, end of shift', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final api = FakeApi()..state = sampleState(visits: [visit(now - 3600, now + 3600)]);
      final (c, store) = await boot(tester, api, size);

      // Tap your face: everyone who can start, the CSO marked; no consent is dimmed and said.
      expect(find.text('Tap your face'), findsOneWidget);
      expect(find.text('CSO'), findsOneWidget);
      expect(find.text('Photo is taken when you start'), findsOneWidget);
      await act(tester, find.text('New Guard'));
      expect(find.text('Ask the estate admin to record your consent form first.'), findsOneWidget);
      expect(spoken.last, 'Ask the estate admin to record your consent form first.');

      // The PIN keypad: wrong, then right. No camera: the shift starts without a photo.
      await act(tester, find.text('Musa Ibrahim'));
      expect(find.text('Your PIN'), findsOneWidget);
      await tapDigits(tester, '111111');
      expect(find.text('Wrong PIN, try again'), findsOneWidget);
      await tapDigits(tester, '482913');
      expect(c.shift?.guardId, 'gu1');
      expect(c.shift!.selfieTaken, isFalse);
      expect(spoken, contains('Shift started.'));
      expect(spoken.join(' '), isNot(contains('482913')), reason: 'a PIN is never read aloud');
      // From here the gate works offline (the fake server's state would not change anyway).
      api.syncError = NetworkException('offline');

      // Home: the three jobs, always in the same place, and the emergency numbers.
      expect(find.text('Musa Ibrahim'), findsOneWidget);
      expect(find.text('MAIN GATE'), findsOneWidget);
      for (final t in ['Visitor has code', 'Phone call', 'Visitor leaving', '0 INSIDE', 'Emergency numbers']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      final top = [for (final t in ['Visitor has code', 'Phone call', 'Visitor leaving']) tester.getTopLeft(find.text(t)).dy];
      expect(top[0] < top[1] && top[1] < top[2], isTrue);
      expect(tester.getSize(find.ancestor(of: find.text('Phone call'), matching: find.byType(InkWell)).first).height, greaterThanOrEqualTo(96));

      // Visitor has code: the six digits, the house number huge, the name, "Let them in?".
      await act(tester, find.text('Visitor has code'));
      expect(find.text("Type the visitor's code"), findsOneWidget);
      final code = deriveCode(key1, 'h1', visitId, now - 3600, now + 3600);
      await tapDigits(tester, code);
      expect(find.text('Code is correct'), findsOneWidget);
      expect(find.text('14B'), findsOneWidget);
      expect(find.text('Tunde Bakare'), findsOneWidget);
      expect(find.text('Let them in?'), findsOneWidget);
      expect(spoken.last, 'Code is correct. 14B. Tunde Bakare. Let them in?');
      expect(spoken.join(' '), isNot(contains(code)), reason: 'the code is never read aloud');
      await act(tester, yes());
      // Code entries get no visitor photo by default ("phone_entries"); then the car.
      expect(find.text('Car?'), findsOneWidget);
      await act(tester, no());
      expect(find.text('Let in'), findsOneWidget);
      expect(spoken.last, 'Let in. 14B.');
      await act(tester, find.text('Done'));
      expect(find.text('1 INSIDE'), findsOneWidget);
      final entry = (await queued(tester, store, OutboxKind.entry)).single;
      expect(entry['method'], 'code');
      expect(entry['visit_id'], visitId);
      expect(entry['photo_skipped'], isNull);

      // A wrong code: "No match", said.
      await act(tester, find.text('Visitor has code'));
      await tapDigits(tester, '000000');
      expect(find.text('No match'), findsOneWidget);
      expect(spoken.last, 'No match. Check the code with the visitor.');
      await act(tester, find.byTooltip('Back'));

      // Visitor leaving: the tile, then "Leaving now?".
      await act(tester, find.text('Visitor leaving'));
      expect(find.text('Who is leaving?'), findsOneWidget);
      await act(tester, find.text('Tunde Bakare'));
      expect(find.text('Leaving now?'), findsOneWidget);
      await act(tester, yes());
      expect(find.text('Left'), findsOneWidget);
      await act(tester, find.text('Done'));
      expect(find.text('0 INSIDE'), findsOneWidget);
      final exit = (await queued(tester, store, OutboxKind.exit)).single;
      expect(exit['method'], 'list_tap');
      expect(exit['visit_id'], visitId);

      // The menu: End shift, Yes, then nobody takes over.
      await act(tester, find.byTooltip('Menu'));
      expect(find.text('Sync'), findsOneWidget);
      expect(find.text('Shuttle to the home'), findsNothing, reason: 'no shuttle at this estate');
      await act(tester, find.text('End shift'));
      expect(find.text('End your shift?'), findsOneWidget);
      await act(tester, yes());
      expect(find.text('Who is taking over?'), findsOneWidget);
      await act(tester, find.text('Nobody'));
      expect(find.text('Tap your face'), findsOneWidget);
      expect(c.shift, isNull);

      expect(tester.takeException(), isNull);
      await finish(tester, c, store);
    });

    testWidgets('($dp dp) phone call: call back, say the name, yes, here now, photo refused, add the new number', (tester) async {
      final api = FakeApi()
        ..state = sampleState()
        ..mediaError = NetworkException('offline'); // the clip stays on the phone, so Leaving can play it
      final caller = FakeCallerId(IncomingCall('08099998888', DateTime.now().subtract(const Duration(minutes: 1))));
      final (c, store) = await boot(tester, api, size, callerId: caller);
      openCamera = ({required bool front}) async => front ? null : _Camera();
      await startAs(tester, api);

      await act(tester, find.text('Phone call'));
      // Not a registered number: no hint; the house picker (one street: straight to the numbers).
      expect(find.text('Which house?'), findsOneWidget);
      await act(tester, find.text('14B'));
      expect(find.text('Call back'), findsWidgets);
      expect(find.textContaining('4567'), findsOneWidget);
      expect(find.textContaining('803123'), findsNothing, reason: 'only the last 4 digits on screen');
      await act(tester, find.text('Call back').first);
      expect(dialled, ['+2348031234567']);

      // Back from the dialler: called back, say the name, "Did they say yes?".
      expect(find.text('House called back'), findsOneWidget);
      expect(find.text('Did they say yes?'), findsOneWidget);
      expect(find.text('No answer'), findsOneWidget);
      expect(find.text('Call supervisor'), findsOneWidget);
      await tester.tap(find.text("Say the visitor's name"));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Recording. Tap to stop'), findsOneWidget);
      await tester.tap(find.text('Recording. Tap to stop'));
      await tester.pumpAndSettle();
      expect(find.text('Name recorded'), findsOneWidget);
      await act(tester, find.byTooltip('Play'));
      expect(played, [1500]);
      await act(tester, yes());

      expect(find.text('Are they here now?'), findsOneWidget);
      await act(tester, yes());
      // A phone entry: the visitor's photo. Skip asks why.
      expect(find.text('Photo of the visitor'), findsWidgets);
      await act(tester, find.text('Skip'));
      expect(find.text('Why no photo?'), findsWidgets);
      await act(tester, find.text('They refused'));
      expect(find.text('Car?'), findsOneWidget);
      await act(tester, no());
      // The call came from a number not on file and the home confirmed: offer it.
      expect(find.text('Add this number for Mrs Adeyemi?'), findsOneWidget);
      await act(tester, yes());
      expect(find.text('Let in'), findsOneWidget);
      await act(tester, find.text('Done'));

      final e = (await queued(tester, store, OutboxKind.entry)).single;
      expect(e['method'], 'callback_confirmed');
      expect(e['guest_name'], 'Voice clip');
      expect(e['name_clip_id'], isNotNull);
      expect(e['caller_masked'], '0809•••8888');
      expect(e['photo_skipped'], 'refused');
      expect((await queued(tester, store, OutboxKind.callback)).single['outcome'], 'confirmed');
      expect((await queued(tester, store, OutboxKind.numberOffer)).single['number'], '08099998888');
      expect(spoken.join(' '), isNot(contains('8888')), reason: 'a phone number is never read aloud');

      // Leaving: "Voice clip" with a play button while the clip is on the phone.
      await act(tester, find.text('Visitor leaving'));
      expect(find.text('Voice clip'), findsOneWidget);
      await act(tester, find.byTooltip('Play'));
      expect(played, [1500, 1500]);
      await act(tester, find.text('Voice clip'));
      await act(tester, yes());
      expect(find.text('Left'), findsOneWidget);
      await act(tester, find.text('Done'));

      expect(tester.takeException(), isNull);
      await finish(tester, c, store);
    });
  }

  testWidgets('(320dp) the caller is a resident: "Is it Mrs Adeyemi, 14B?", the home PIN, coming later', (tester) async {
    final api = FakeApi()..state = sampleState(houseCodeHash: makePinHash('4821', iterations: 1000));
    final caller = FakeCallerId(IncomingCall('08031234567', DateTime.now()));
    final (c, store) = await boot(tester, api, const Size(640, 1136), callerId: caller);
    await startAs(tester, api);

    await act(tester, find.text('Phone call'));
    expect(find.text('Is it Mrs Adeyemi, 14B?'), findsOneWidget);
    await act(tester, yes());
    await act(tester, find.text('They gave the home PIN'));
    expect(find.text('Home PIN'), findsWidgets);
    await tapDigits(tester, '0000');
    expect(find.text('Wrong PIN. 2 left'), findsOneWidget);
    await tapDigits(tester, '4821');
    expect(find.text('PIN is correct'), findsOneWidget);
    expect(find.text('Are they here now?'), findsOneWidget);
    await act(tester, no());
    expect(find.text('How long are they staying?'), findsOneWidget);
    await act(tester, find.text('Overnight'));
    expect(find.text('They are expected'), findsOneWidget);
    await act(tester, find.text('Done'));

    final checks = await queued(tester, store, OutboxKind.pinCheck);
    expect(checks.map((x) => (x['ok'], x['caller_masked'])), [(false, '0803•••4567'), (true, '0803•••4567')]);
    expect((await queued(tester, store, OutboxKind.visit)).single['trust'], 'pin_verified');
    expect(spoken.join(' '), isNot(contains('4821')));
    expect(await queued(tester, store, OutboxKind.numberOffer), isEmpty, reason: 'a registered number');

    expect(tester.takeException(), isNull);
    await finish(tester, c, store);
  });

  testWidgets('(320dp) no answer twice: a guard picks the CSO (on shift first), the reason, let in; the home gets a text', (tester) async {
    // /state lists Mr Bello's open shift at the back gate.
    final state = sampleState()
      ..['on_duty'] = [
        {'guard_id': 'cso1', 'gate_id': 'g2', 'since': DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String()},
      ];
    final api = FakeApi()..state = state;
    final (c, store) = await boot(tester, api, const Size(640, 1136));
    await startAs(tester, api);

    await act(tester, find.text('Phone call'));
    await act(tester, find.text('14B'));
    for (var i = 0; i < 2; i++) {
      await act(tester, find.text('Call back').first);
      await act(tester, find.text('No answer'));
    }
    expect(find.text('Which CSO decided?'), findsOneWidget);
    expect(find.text('ON SHIFT'), findsOneWidget);
    await act(tester, find.text('Mr Bello'));
    expect(find.text('Why let them in?'), findsOneWidget);
    await act(tester, find.text('Delivery or service'));
    expect(find.text('Let them in?'), findsOneWidget);
    expect(find.text('You are deciding alone. The home will get a text.'), findsNothing, reason: 'the guard is not the CSO');
    await act(tester, yes());
    // No camera on this phone: the photo step goes on at once, as no_camera.
    expect(find.text('Car?'), findsOneWidget);
    await act(tester, no());
    expect(find.text('Let in'), findsOneWidget);
    expect(find.text('The home will get a text'), findsOneWidget);
    expect(spoken.last, 'Let in. 14B. The home will get a text.');
    await act(tester, find.text('Done'));

    final e = (await queued(tester, store, OutboxKind.entry)).single;
    expect(e['method'], 'walk_in_admitted');
    expect(e['decided_by'], 'cso1');
    expect(e['reason'], 'Delivery or service');
    expect(e['photo_skipped'], 'no_camera');
    expect((await queued(tester, store, OutboxKind.callback)).map((x) => x['outcome']), ['no_answer', 'no_answer']);

    expect(tester.takeException(), isNull);
    await finish(tester, c, store);
  });

  testWidgets('(320dp) the CSO on the gate: same home, CSO extras with a red count, decides alone', (tester) async {
    final api = FakeApi()
      ..state = sampleState(pinHashes: {'cso1': musaPinHash})
      ..csoBody = {
        ...sampleCso(),
        'needs': {
          ...(sampleCso()['needs'] as Map<String, dynamic>),
          'disputed_today': [
            {
              'entry_id': 'e9',
              'guest_name': 'Voice clip',
              'address': '14B Adeniyi Close, Block C',
              'gate': 'Main gate',
              'decided_by': 'Mr Bello',
              'at': '2026-10-21T09:00:00+00:00',
              'disputed_at': '2026-10-21T09:05:00+00:00',
            },
          ],
          'walk_ins_today': [
            {
              'entry_id': 'e8',
              'guest_name': 'Plumber',
              'address': '14B Adeniyi Close, Block C',
              'gate': 'Main gate',
              'decided_by': 'Mr Bello',
              'reason': 'Known to the CSO',
              'at': '2026-10-21T08:00:00+00:00',
              'decided_alone': true,
            },
          ],
        },
      };
    final (c, store) = await boot(tester, api, const Size(640, 1136));
    await startAs(tester, api, 'Mr Bello');
    expect(c.isCso, isTrue);

    // The same three jobs first; the CSO's extras one tap away, with a count.
    for (final t in ['Visitor has code', 'Phone call', 'Visitor leaving']) {
      expect(find.text(t), findsOneWidget);
    }
    await tester.runAsync(() => c.refreshCso());
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget, reason: 'the home said NO, a guest past their time, a quiet phone');
    await act(tester, find.byTooltip('CSO'));
    // "Home said NO" first, in red.
    final said = find.text('HOME SAID NO');
    expect(said, findsOneWidget);
    expect(tester.getTopLeft(said).dy, lessThan(tester.getTopLeft(find.text('PAST THEIR TIME')).dy));
    expect(tester.widget<Text>(said).style!.color, Palette.of(tester.element(said)).noText);
    await tester.scrollUntilVisible(find.text('DECIDED ALONE'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('DECIDED ALONE'), findsOneWidget);
    await act(tester, find.text('People'));
    expect(find.text('Add a guest'), findsOneWidget);
    await act(tester, find.text('Shifts'));
    expect(find.text("TODAY'S SHIFTS"), findsOneWidget);
    await act(tester, find.byTooltip('Back'));

    // A walk-in on the CSO's own word: no "pick the CSO", the note, decided_by is the CSO.
    await act(tester, find.text('Phone call'));
    await act(tester, find.text('14B'));
    await act(tester, find.text('Call supervisor'));
    expect(find.text('Which CSO decided?'), findsNothing);
    await act(tester, find.text('Known to the CSO'));
    expect(find.text('You are deciding alone. The home will get a text.'), findsOneWidget);
    await act(tester, yes());
    if (find.text('Car?').evaluate().isNotEmpty) await act(tester, no());
    await act(tester, find.text('Done'));
    final e = (await queued(tester, store, OutboxKind.entry)).single;
    expect(e['decided_by'], 'cso1');
    expect(e['guard_id'], 'cso1');

    expect(tester.takeException(), isNull);
    await finish(tester, c, store);
  });

  testWidgets('day and night: charcoal with the fabric at night, white by day, on the home', (tester) async {
    final api = FakeApi()..state = sampleState();
    final (c, store) = await boot(tester, api, const Size(720, 1520));
    await startAs(tester, api);
    for (final night in [true, false]) {
      Palette.forceNight = night;
      await tester.pumpWidget(GuardApp(key: ValueKey(night), controller: c));
      await tester.pumpAndSettle();
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
      expect(scaffold.backgroundColor, night ? const Color(0xFF111111) : const Color(0xFFF2F2F0));
      expect(find.text('Visitor has code'), findsOneWidget);
    }
    Palette.forceNight = null;
    await finish(tester, c, store);
  });

  testWidgets('(320dp) pairing in the kit look: a bad code says why, a good one pairs and goes to shift start', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    initTimeZones();
    final api = FakeApi()..state = sampleState();
    final store = memoryStore();
    final c = GateController(store: store, secrets: Secrets(MemorySecretStore()), api: api, pins: fastPins, callerId: FakeCallerId());
    await tester.runAsync(c.init);
    for (final night in [true, false]) {
      Palette.forceNight = night;
      await tester.pumpWidget(GuardApp(key: ValueKey(night), controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Pair this phone'), findsOneWidget);
      expect(tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor, night ? const Color(0xFF111111) : const Color(0xFFF2F2F0));
    }
    Palette.forceNight = null;

    await tester.enterText(find.byType(TextField), 'abc');
    await act(tester, find.text('Pair phone'));
    expect(find.text('The code has 8 letters and numbers, like ABCD-2345.'), findsOneWidget);
    expect(c.phase, Phase.unpaired);

    await tester.enterText(find.byType(TextField), 'abcd 2345');
    await tester.tap(find.text('Pair phone'));
    for (var i = 0; i < 200 && (c.phase == Phase.unpaired || c.busy); i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    await tester.pumpAndSettle();
    expect(c.phase, Phase.startShift);
    expect(find.text('Tap your face'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester, c, store);
  });
}
