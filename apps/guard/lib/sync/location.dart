import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../app/positions.dart';
import '../data/shuttle.dart';

/// geolocator, with its Android foreground service: while the stream is listened to, Android
/// shows the "Shuttle shift" notification and keeps the app's process (and the 15 second
/// reports) going with the screen off or another app in front. Cancelling the stream stops
/// the service and removes the notification.
class GeolocatorLocationSource implements LocationSource {
  static const _permissions = MethodChannel('ng.gatelog/permissions');

  @override
  Future<LocationAccess> ensureAccess() async {
    final LocationAccess access;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return LocationAccess.serviceOff;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      access = switch (p) {
        LocationPermission.always || LocationPermission.whileInUse => LocationAccess.granted,
        LocationPermission.deniedForever => LocationAccess.deniedForever,
        _ => LocationAccess.denied,
      };
    } catch (e) {
      debugPrint('location permission: ${e.runtimeType}');
      return LocationAccess.denied;
    }
    if (access == LocationAccess.granted) {
      // Asked after location (Android shows one prompt at a time). On Android 13+ the foreground
      // service notification needs it to be seen in the shade; the service runs either way.
      try {
        await _permissions.invokeMethod<bool>('requestNotifications');
      } catch (e) {
        debugPrint('notification permission: ${e.runtimeType}');
      }
    }
    return access;
  }

  @override
  Stream<PositionFix> watch(Duration every) {
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: every,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Shuttle shift',
        notificationText: 'The estate can see where the shuttle is until you end your shift.',
        notificationChannelName: 'Shuttle shift',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
    return Geolocator.getPositionStream(locationSettings: settings)
        .map((p) => PositionFix.clean(
              lat: p.latitude,
              lng: p.longitude,
              at: p.timestamp,
              accuracyM: p.accuracy,
              heading: p.heading,
              speed: p.speed,
            ))
        .where((p) => p != null)
        .cast<PositionFix>();
  }

  @override
  Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }
}
