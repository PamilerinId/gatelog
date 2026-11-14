import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/caller.dart';
import 'app/controller.dart';
import 'core/estate_time.dart';
import 'data/open.dart';
import 'data/secrets.dart';
import 'data/store.dart';
import 'sync/api.dart';
import 'sync/card_reader.dart';
import 'sync/location.dart';
import 'sync/push.dart';
import 'ui/app.dart';
import 'ui/kit.dart' show Palette;

/// `--dart-define=API_BASE_URL=https://api.example.ng`. The default reaches a dev API on the
/// host machine from the Android emulator.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

/// `--dart-define=GATELOG_THEME=night|day` holds the look for screenshots and demos (debug
/// builds only). Otherwise it follows the estate's time of day.
const _theme = String.fromEnvironment('GATELOG_THEME');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  initTimeZones();
  if (kDebugMode && _theme.isNotEmpty) Palette.forceNight = _theme == 'night';

  final secrets = Secrets(SecureSecretStore());
  final db = await openGateDatabase(secrets);
  final push = await FirebasePushService.tryCreate();
  final connectivity = Connectivity().onConnectivityChanged.map((r) => r.any((x) => x != ConnectivityResult.none));

  final controller = GateController(
    store: GateStore(db),
    secrets: secrets,
    api: HttpGateApi(apiBaseUrl),
    push: push,
    connectivity: connectivity,
    // Rider shifts only: the position every 15 seconds (a foreground service with its
    // notification) and estate cards over NFC.
    location: GeolocatorLocationSource(),
    cardReader: NfcCardReader(),
    // Caller ID from Android's call screening (a hint only; the callback is the proof).
    callerId: const AndroidCallerId(),
  );
  await controller.init();
  controller.start();
  runApp(GuardApp(controller: controller));
}
