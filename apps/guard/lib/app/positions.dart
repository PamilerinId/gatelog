import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/shuttle.dart';
import '../data/store.dart';
import '../sync/api.dart';

/// Whether the phone can report where it is.
enum LocationAccess { granted, denied, deniedForever, serviceOff }

/// Where the phone is. The app's is geolocator with its Android foreground service (and its
/// notification); tests use a fake.
abstract class LocationSource {
  /// Asks for location (and, on Android 13 and up, notification) permission if needed.
  Future<LocationAccess> ensureAccess();

  /// Position fixes about every [every]. Listening starts the foreground service; cancelling
  /// the subscription stops it and removes its notification.
  Stream<PositionFix> watch(Duration every);

  /// Opens the phone's settings for this app (after "don't ask again").
  Future<void> openSettings();
}

/// Records the phone's position every 15 seconds during an open rider shift, and only then.
/// Points wait in the encrypted database (2 hours at most) and go to `POST /v1/device/positions`
/// oldest first, in batches of up to 200. Where the phone was is never logged.
class PositionReporter {
  PositionReporter(this.store, this.source, {DateTime Function()? clock, this.every = const Duration(seconds: 15)}) : _clock = clock ?? DateTime.now;

  final GateStore store;
  final LocationSource source;
  final Duration every;
  final DateTime Function() _clock;

  static const keep = Duration(hours: 2);
  static const batch = 200;

  String? _shiftId;
  StreamSubscription<PositionFix>? _sub;
  DateTime? _lastAt;
  bool _flushing = false;
  bool _starting = false;
  int _gen = 0;

  /// The last fix recorded in this shift, so a pickup or drop-off can carry where it happened.
  PositionFix? last;

  /// Not null when location is off or refused: what to tell the rider.
  LocationAccess? problem;

  /// Called after each point is queued (the controller sends it).
  VoidCallback? onPoint;

  /// Called when [problem] changes.
  VoidCallback? onChange;

  String? get shiftId => _shiftId;
  bool get running => _sub != null;

  /// Starts recording for [shiftId], a rider's open shift.
  Future<void> start(String shiftId) async {
    // Already running, or already asked this shift and refused (asked again only on "Turn on").
    if (_shiftId == shiftId && (_sub != null || problem != null || _starting)) return;
    final gen = ++_gen;
    final old = _sub;
    _sub = null;
    _shiftId = shiftId;
    _starting = true;
    problem = null;
    last = null;
    _lastAt = null;
    await old?.cancel();
    final LocationAccess access;
    try {
      access = await source.ensureAccess();
    } finally {
      if (gen == _gen) _starting = false;
    }
    if (gen != _gen) return; // ended (or restarted) while the permission prompt was up
    problem = access == LocationAccess.granted ? null : access;
    onChange?.call();
    if (problem != null) return;
    _sub = source.watch(every).listen((fix) => _record(shiftId, fix), onError: (Object e) {
      debugPrint('location stream error: ${e.runtimeType}');
    });
  }

  /// Stops at once: no point is recorded after this returns.
  Future<void> stop() async {
    _gen++;
    _starting = false;
    _shiftId = null;
    problem = null;
    last = null;
    _lastAt = null;
    final s = _sub;
    _sub = null;
    await s?.cancel();
  }

  Future<void> _record(String shiftId, PositionFix fix) async {
    if (_shiftId != shiftId) return;
    // The fused provider can deliver faster than asked when another app wants location.
    final prev = _lastAt;
    if (prev != null && fix.at.difference(prev) < every - const Duration(seconds: 1)) return;
    _lastAt = fix.at;
    last = fix;
    await store.addPosition(shiftId, fix);
    await store.trimPositions(_clock().subtract(keep));
    onPoint?.call();
  }

  /// Sends what is queued, oldest first, up to 200 points a call, until the queue is empty or
  /// the network fails. [shiftPending]: whether that shift's start has not reached the server
  /// yet (then a 409 means "not yet", not "closed"). Throws [UnauthorizedException].
  Future<int> flush(String token, GateApi api, Future<bool> Function(String shiftId) shiftPending) async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      await store.trimPositions(_clock().subtract(keep));
      final skip = <String>{};
      while (true) {
        final queued = [for (final q in await store.positions(limit: batch * 4)) if (!skip.contains(q.shiftId)) q];
        if (queued.isEmpty) break;
        final shift = queued.first.shiftId;
        final chunk = queued.where((q) => q.shiftId == shift).take(batch).toList();
        try {
          await api.postPositions(token, shift, [for (final q in chunk) q.fix]);
          await store.deletePositions(chunk.map((q) => q.seq));
          sent += chunk.length;
        } on NetworkException {
          break;
        } on ApiException catch (e) {
          if (e.status == 409 && await shiftPending(shift)) {
            skip.add(shift); // the shift has not synced yet: try after the next sync
          } else if (e.status == 409 || e.status == 403) {
            await store.deletePositionsForShift(shift); // closed, or not a rider's shift
          } else {
            await store.deletePositions(chunk.map((q) => q.seq)); // refused as malformed
          }
        }
      }
    } finally {
      _flushing = false;
    }
    return sent;
  }
}
