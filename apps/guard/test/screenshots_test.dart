/// Renders every guard and CSO screen, day and night, to PNGs with the bundled fonts, for review
/// against the handoff design. Skipped unless GATELOG_SHOTS names a folder:
///
///   GATELOG_SHOTS=/tmp/shots flutter test test/screenshots_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/app/caller.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/core/card.dart';
import 'package:gatelog_guard/core/codes.dart';
import 'package:gatelog_guard/core/estate_time.dart';
import 'package:gatelog_guard/core/pin.dart';
import 'package:gatelog_guard/data/secrets.dart';
import 'package:gatelog_guard/sync/api.dart';
import 'package:gatelog_guard/sync/capture.dart';
import 'package:gatelog_guard/ui/app.dart';
import 'package:gatelog_guard/ui/kit.dart';
import 'package:gatelog_guard/ui/widgets.dart';

import 'support.dart';

const visitId = '9d0e7c6b-5a49-4382-a716-2f5e4d3c2b1a';
final key1 = List<int>.generate(32, (i) => i);

class _Camera implements GateCamera {
  @override
  Widget preview() => ClipRRect(borderRadius: BorderRadius.circular(24), child: const ColoredBox(color: Color(0xFF3A3F44), child: SizedBox.expand()));
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

Future<void> _loadFonts() async {
  Future<ByteData> asset(String p) => rootBundle.load(p);
  final inter = FontLoader('Inter');
  for (final w in [400, 500, 600, 700, 800]) {
    inter.addFont(asset('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  final mono = FontLoader('JetBrainsMono');
  for (final w in [400, 500, 600]) {
    mono.addFont(asset('assets/fonts/JetBrainsMono-$w.ttf'));
  }
  await mono.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}

void main() {
  final out = Platform.environment['GATELOG_SHOTS'];
  final boundary = GlobalKey();

  setUp(() {
    dial = (n) async => true;
    speak = (s) async {};
    openCamera = ({required bool front}) async => front ? null : _Camera();
    newRecorder = _Recorder.new;
    playClip = (b, t) async {};
  });

  Future<void> snap(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final img = await ro.toImage(pixelRatio: 3);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> act(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> digits(WidgetTester tester, String d) async {
    for (final x in d.split('')) {
      await tester.tap(find.text(x).last);
      await tester.pump();
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Finder yes() => find.text('Yes').last;
  Finder no() => find.text('No').last;

  for (final night in [true, false]) {
    final t = night ? 'night' : 'day';
    testWidgets('screens, $t', (tester) async {
      Directory(out!).createSync(recursive: true);
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      Palette.forceNight = night;
      addTearDown(() => Palette.forceNight = null);
      initTimeZones();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final state = sampleState(
        visits: [
          {
            'id': visitId, 'home_id': 'h1', 'resident_id': 'r1', 'guest_name': 'Tunde Bakare', 'window_start': now - 3600,
            'window_end': now + 3600, 'key_version': 1, 'code_issued': true, 'source': 'whatsapp', 'state': 'expected',
            'expected_until': null, 'entry_id': null, 'entered_at': null,
          },
        ],
        houseCodeHash: makePinHash('4821', iterations: 1000),
        pinHashes: {'cso1': musaPinHash},
      );
      (state['guards'] as List).add({'id': 'gu4', 'name': 'Chidi Okafor', 'role': 'guard', 'pin_hash': null, 'pin_reset_at': null, 'consent': true});
      // Mr Bello has a shift open at the gate: ON SHIFT when a guard picks the CSO.
      state['on_duty'] = [
        {'guard_id': 'cso1', 'gate_id': 'g1', 'since': DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String()},
      ];
      final api = FakeApi()
        ..state = state
        ..csoBody = {
          ...sampleCso(),
          'needs': {
            ...(sampleCso()['needs'] as Map<String, dynamic>),
            'disputed_today': [
              {'entry_id': 'e9', 'guest_name': 'Voice clip', 'address': '14B Adeniyi Close, Block C', 'gate': 'Main gate', 'decided_by': 'Mr Bello',
               'at': '2026-10-21T09:00:00+00:00', 'disputed_at': '2026-10-21T09:05:00+00:00'},
            ],
            'walk_ins_today': [
              {'entry_id': 'e8', 'guest_name': 'Plumber', 'address': '14B Adeniyi Close, Block C', 'gate': 'Main gate', 'decided_by': 'Mr Bello',
               'reason': 'Known to the CSO', 'at': '2026-10-21T08:00:00+00:00', 'decided_alone': true},
            ],
          },
        };
      final store = memoryStore();
      final caller = FakeCallerId(IncomingCall('08099998888', DateTime.now()));
      final c = GateController(store: store, secrets: Secrets(MemorySecretStore()), api: api, pins: fastPins, callerId: caller);
      await tester.runAsync(() async {
        await c.init();
        await c.pair('ABCD-2345');
        await c.idle();
      });
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: GuardApp(controller: c)));
      await snap(tester, '${t}_01_tap_your_face');
      await act(tester, find.text('Musa Ibrahim'));
      await digits(tester, '48');
      await snap(tester, '${t}_02_pin');
      await digits(tester, '2913');
      api.syncError = NetworkException('offline');
      api.stateError = NetworkException('offline');
      await tester.runAsync(() => c.syncNow());
      await tester.pumpAndSettle();
      await snap(tester, '${t}_03_home_offline');

      // Visitor has code.
      await act(tester, find.text('Visitor has code'));
      final code = deriveCode(key1, 'h1', visitId, now - 3600, now + 3600);
      await digits(tester, code.substring(0, 4));
      await snap(tester, '${t}_04_code_keypad');
      await digits(tester, code.substring(4));
      await snap(tester, '${t}_05_code_is_correct');
      await act(tester, yes());
      await snap(tester, '${t}_06_car');
      await act(tester, yes());
      await snap(tester, '${t}_07_plate_camera');
      await act(tester, find.text('Skip'));
      await snap(tester, '${t}_08_let_in');
      await act(tester, find.text('Done'));
      await act(tester, find.text('Visitor has code'));
      await digits(tester, '000000');
      await snap(tester, '${t}_09_no_match');
      await act(tester, find.byTooltip('Back'));

      // Phone call: the callback, the name, yes, here now, the photo, the number offer.
      caller.call = IncomingCall('08099998888', DateTime.now());
      await act(tester, find.text('Phone call'));
      await snap(tester, '${t}_10_which_house');
      await act(tester, find.text('14B'));
      await snap(tester, '${t}_11_call_back');
      await act(tester, find.text('Call back').first);
      await tester.tap(find.text("Say the visitor's name"));
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: 3);
        File('$out/${t}_12_recording.png').writeAsBytesSync((await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
      });
      await tester.tap(find.text('Recording. Tap to stop'));
      await snap(tester, '${t}_13_did_they_say_yes');
      await act(tester, yes());
      await snap(tester, '${t}_14_here_now');
      await act(tester, yes());
      await snap(tester, '${t}_15_photo_of_visitor');
      await act(tester, find.text('Skip'));
      await snap(tester, '${t}_16_why_no_photo');
      await act(tester, find.text('They refused'));
      await act(tester, no());
      await snap(tester, '${t}_17_add_this_number');
      await act(tester, yes());
      await act(tester, find.text('Done'));

      // The caller is a resident: the hint, the home PIN, coming later.
      caller.call = IncomingCall('08031234567', DateTime.now());
      await act(tester, find.text('Phone call'));
      await snap(tester, '${t}_18_is_it_mrs_adeyemi');
      await act(tester, yes());
      await act(tester, find.text('They gave the home PIN'));
      await digits(tester, '0000');
      await snap(tester, '${t}_19_home_pin_wrong');
      await digits(tester, '4821');
      await act(tester, no());
      await snap(tester, '${t}_20_how_long');
      await act(tester, find.text('Overnight'));
      await snap(tester, '${t}_21_expected');
      await act(tester, find.text('Done'));

      // No answer twice: the CSO decides.
      caller.call = null;
      await act(tester, find.text('Phone call'));
      await act(tester, find.text('14B'));
      // The guest announced with the PIN a moment ago: not this one.
      await snap(tester, '${t}_22a_is_this_them');
      await act(tester, no());
      for (var i = 0; i < 2; i++) {
        await act(tester, find.text('Call back').first);
        await act(tester, find.text('No answer'));
      }
      await snap(tester, '${t}_22_which_cso');
      await act(tester, find.text('Mr Bello'));
      await snap(tester, '${t}_23_why_let_in');
      await act(tester, find.text('Described the house well'));
      await snap(tester, '${t}_24_cso_let_them_in');
      await act(tester, yes());
      await act(tester, find.text('Skip'));
      await act(tester, find.text('They refused'));
      await act(tester, no());
      await snap(tester, '${t}_25_home_gets_a_text');
      await act(tester, find.text('Done'));

      // Leaving.
      await act(tester, find.text('Visitor leaving'));
      await snap(tester, '${t}_26_who_is_leaving');
      await act(tester, find.text('Tunde Bakare'));
      await snap(tester, '${t}_27_leaving_now');
      await act(tester, no());
      await act(tester, find.byTooltip('Back'));

      // Emergency numbers, Sync, End shift.
      await act(tester, find.text('Emergency numbers'));
      await snap(tester, '${t}_28_emergency_numbers');
      await act(tester, find.byTooltip('Back'));
      await act(tester, find.byTooltip('Menu'));
      await snap(tester, '${t}_29_menu');
      await act(tester, find.text('End shift'));
      await act(tester, yes());
      await snap(tester, '${t}_30_who_takes_over');
      await act(tester, find.text('Nobody'));

      // The CSO on the gate.
      api.syncError = null;
      api.stateError = null;
      await act(tester, find.text('Mr Bello'));
      await digits(tester, '482913');
      await tester.runAsync(() async {
        await c.idle();
        await c.refreshCso();
      });
      await tester.pumpAndSettle();
      await snap(tester, '${t}_31_cso_home');
      await act(tester, find.byTooltip('CSO'));
      await snap(tester, '${t}_32_cso_now');
      await act(tester, find.text('People'));
      await snap(tester, '${t}_33_cso_people');
      await act(tester, find.text('Shifts'));
      await snap(tester, '${t}_34_cso_shifts');
      await act(tester, find.byTooltip('Back'));
      api.syncError = NetworkException('offline');
      await act(tester, find.text('Phone call'));
      await act(tester, find.text('14B'));
      if (find.text('Is this them?').evaluate().isNotEmpty) await act(tester, no());
      await act(tester, find.text('Call supervisor'));
      await act(tester, find.text('Known to the CSO'));
      await snap(tester, '${t}_35_cso_deciding_alone');

      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.runAsync(() => store.db.close());
    }, skip: out == null);

    testWidgets('pairing, rider and shuttle, $t', (tester) async {
      Directory(out!).createSync(recursive: true);
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      Palette.forceNight = night;
      addTearDown(() => Palette.forceNight = null);
      initTimeZones();
      final now = DateTime.now().toUtc();
      String ago(int min) => now.subtract(Duration(minutes: min)).toIso8601String();
      const rideA = '5b7a8f40-1c2d-4e5f-8a9b-0c1d2e3f4a5b';
      const rideB = '6c8b9051-2d3e-4f60-9bac-1d2e3f4a5b6c';
      const rideC = '7d9ca162-3e4f-4071-acbd-2e3f4a5b6c7d';
      final api = FakeApi()
        ..state = sampleState(
          shuttle: sampleShuttle(
            cardHash: cardHash('e1', cardUid),
            rides: [
              sampleRide(rideA, wantedAt: ago(12), note: 'Bring the helmet'),
              sampleRide(rideB, kind: 'delivery', source: 'gate', fromHome: false, passenger: 'Jumia parcel', wantedAt: ago(3)),
              sampleRide(rideC, state: 'accepted', riderId: 'ri2', rider: 'Ade Rider', wantedAt: ago(5)),
            ],
          ),
          houseCodeHash: makePinHash('4821', iterations: 1000),
          pinHashes: {'cso1': musaPinHash},
        )
        ..csoBody = {
          ...sampleCso(),
          'needs': {
            ...(sampleCso()['needs'] as Map<String, dynamic>),
            'rides_waiting': [
              {'ride_id': rideA, 'kind': 'resident', 'from': '14B Adeniyi Close, Block C', 'to': 'Main gate', 'wanted_at': ago(12)},
            ],
          },
        };
      final store = memoryStore();
      final c = GateController(store: store, secrets: Secrets(MemorySecretStore()), api: api, pins: fastPins, callerId: FakeCallerId());
      await tester.runAsync(c.init);
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: GuardApp(controller: c)));

      // Pairing, once, by the estate admin.
      await snap(tester, '${t}_40_pairing');
      await tester.enterText(find.byType(TextField), 'ABC');
      await act(tester, find.text('Pair phone'));
      await snap(tester, '${t}_41_pairing_wrong_code');
      await tester.runAsync(() async {
        await c.pair('ABCD-2345');
        await c.idle();
      });
      await tester.pumpAndSettle();

      // The rider: face, PIN, the motorcycle, one ride at a time.
      await act(tester, find.text('Kunle Rider'));
      await digits(tester, '482913');
      await snap(tester, '${t}_42_rider_which_motorcycle');
      await act(tester, find.text('S1'));
      await tester.runAsync(() => c.idle());
      await tester.pumpAndSettle();
      await snap(tester, '${t}_43_rider_take_it');
      api.syncError = NetworkException('offline');
      await act(tester, yes());
      await snap(tester, '${t}_44_rider_tap_their_card');
      await act(tester, find.text('No card'));
      await snap(tester, '${t}_45_rider_home_pin');
      await act(tester, find.byTooltip('Back'));
      await tester.enterText(find.byType(TextField), cardUid);
      await act(tester, find.text('Use'));
      await snap(tester, '${t}_46_rider_is_this_them');
      await act(tester, yes());
      await snap(tester, '${t}_47_rider_did_they_arrive');
      await act(tester, yes());
      await act(tester, no()); // not the parcel
      await snap(tester, '${t}_48_rider_no_more_rides');
      await act(tester, find.byTooltip('Menu'));
      await snap(tester, '${t}_49_rider_menu');
      await act(tester, find.text('End my shift'));
      await act(tester, yes());
      await act(tester, no());

      // The CSO's shuttle: the tab, booking a ride by Yes or No, issuing a card; then the gate's
      // "Shuttle to the home".
      api.syncError = null;
      await act(tester, find.text('Mr Bello'));
      await digits(tester, '482913');
      await tester.runAsync(() async {
        await c.idle();
        await c.refreshCso();
      });
      await tester.pumpAndSettle();
      await act(tester, find.byTooltip('CSO'));
      await act(tester, find.text('Shuttle'));
      await snap(tester, '${t}_50_cso_shuttle_tab');
      api.syncError = NetworkException('offline');
      await act(tester, find.text('Book a ride'));
      await snap(tester, '${t}_51_cso_which_house');
      await act(tester, find.text('14B'));
      await snap(tester, '${t}_52_cso_did_they_ring');
      await act(tester, yes());
      await act(tester, yes()); // pick up at home
      await act(tester, no()); // not the main gate
      await act(tester, yes()); // the clubhouse
      await act(tester, no()); // not now
      await act(tester, yes()); // in 30 minutes
      await snap(tester, '${t}_53_cso_book_this_ride');
      await act(tester, yes());
      await act(tester, find.text('Issue a card'));
      await snap(tester, '${t}_54_cso_issue_card');
      await act(tester, find.byTooltip('Back'));
      await act(tester, find.byTooltip('Back'));
      await act(tester, find.byTooltip('Menu'));
      await act(tester, find.text('Shuttle to the home'));
      await act(tester, find.text('14B'));
      await snap(tester, '${t}_55_parcel_or_guest');
      await act(tester, find.text('Parcel'));
      await snap(tester, '${t}_56_book_the_shuttle');
      await act(tester, yes());

      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.runAsync(() => store.db.close());
    }, skip: out == null);
  }
}
