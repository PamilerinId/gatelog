import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/card.dart';
import '../core/estate_time.dart';
import '../core/pin.dart';
import '../core/verify.dart';
import '../data/cso.dart';
import '../data/models.dart';
import '../data/secrets.dart';
import '../data/shuttle.dart';
import '../data/store.dart';
import '../sync/api.dart';
import '../sync/card_reader.dart';
import '../sync/outbox.dart';
import '../sync/push.dart';
import '../sync/selfies.dart';
import 'gate_view.dart';
import 'positions.dart';
import 'rides.dart';
import 'shift.dart';

/// unpaired: pairing screen. startShift: pick your name, PIN, selfie. ready: an open shift,
/// shown as the guard view, the CSO view or the rider view by the person's role.
enum Phase { loading, unpaired, startShift, ready }

const _uuid = Uuid();

class GateNotice {
  const GateNotice(this.message, this.undoId, this.at);
  final String message;
  final String? undoId;
  final DateTime at;
}

/// PIN hashing, swappable so tests run fast. The app hashes in an isolate.
class PinHasher {
  const PinHasher({this.background = true, this.iterations = pinIterations});
  final bool background;
  final int iterations;

  Future<String> hash(String pin) =>
      background && iterations == pinIterations ? hashPinInBackground(pin) : Future.value(makePinHash(pin, iterations: iterations));

  Future<bool> check(String pin, String hash) => background ? checkPinInBackground(pin, hash) : Future.value(checkPin(pin, hash));
}

/// App state and every action the guard or CSO can take. Everything is written to the outbox
/// first and pushed when there is a network; nothing here waits on the server.
class GateController extends ChangeNotifier {
  GateController({
    required this.store,
    required this.secrets,
    required this.api,
    PushService? push,
    Stream<bool>? connectivity,
    this.pollEvery = const Duration(minutes: 2),
    this.pins = const PinHasher(),
    DateTime Function()? clock,
    LocationSource? location,
    this.cardReader = const NoCardReader(),
  })  : push = push ?? NoPushService(),
        _connectivity = connectivity,
        _clock = clock ?? DateTime.now {
    _pusher = OutboxPusher(store, api, clock: _clock);
    _selfies = SelfieUploader(store, api, clock: _clock);
    positions = location == null ? null : PositionReporter(store, location, clock: _clock);
    positions?.onPoint = _flushPositionsSoon;
    positions?.onChange = notifyListeners;
  }

  final GateStore store;
  final Secrets secrets;
  final GateApi api;
  final PushService push;
  final Duration pollEvery;
  final PinHasher pins;
  final Stream<bool>? _connectivity;
  final DateTime Function() _clock;
  late final OutboxPusher _pusher;
  late final SelfieUploader _selfies;

  /// NFC for estate cards (rider pickups, the CSO issuing a card).
  final CardReader cardReader;

  /// Position reporting during a rider's open shift. Null when the phone has no location source
  /// (tests); then nothing is ever recorded.
  late final PositionReporter? positions;

  Phase phase = Phase.loading;
  String? _token;
  StateSnapshot? snapshot;
  Map<int, List<int>> keys = {};
  List<OutboxItem> _outbox = [];
  GateView view = GateView.empty;
  OpenShift? shift;
  PinTries _tries = PinTries();
  PinTries _houseTries = PinTries();

  /// The shuttle's rides with this phone's records laid over them.
  RideView rides = RideView.empty;

  /// "Taken by Musa": a ride this rider tapped first on the phone but another rider got.
  String? rideNotice;
  final Set<String> _lostRides = {};
  String? estateName;
  String? gateName;

  DateTime? lastSyncAt;
  bool syncing = false;
  bool online = true;
  String? lastError;

  /// The last CSO overview and when it was fetched (kept for offline use).
  CsoOverview? cso;
  DateTime? csoFetchedAt;
  String? csoError;
  bool csoLoading = false;

  /// The last thing recorded at the gate ("Let in: Tunde"), shown above the keypad with Undo,
  /// so no toast ever covers the dock buttons.
  GateNotice? notice;

  void showNotice(String message, {String? undoId}) {
    notice = GateNotice(message, undoId, _clock());
    notifyListeners();
  }

  void clearNotice() {
    if (notice == null) return;
    notice = null;
    notifyListeners();
  }

  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _poll;
  Future<void>? _running;
  Future<void>? _next;

  EstateTime get time => EstateTime(snapshot?.estate.timezone ?? 'Africa/Lagos', clock: _clock);
  DateTime now() => _clock();

  /// The person on the open shift.
  Guard? get guard => snapshot?.guard(shift?.guardId);
  String? get guardId => shift?.guardId;
  bool get isCso => guard?.isCso ?? false;
  bool get isRider => guard?.isRider ?? false;

  /// The estate shuttle, or null when the estate runs none: then none of it shows.
  ShuttleState? get shuttle => snapshot?.shuttle;

  /// The motorcycle on the rider's open shift.
  ShuttleBike? get bike => shuttle?.bike(shift?.shuttleId);

  /// Not null when the rider's location is off or refused.
  LocationAccess? get locationProblem => isRider ? positions?.problem : null;

  /// Rides waiting for a rider (without ones this rider just lost), and the rider's own.
  List<Ride> get waitingRides => rides.waiting(hidden: _lostRides);
  List<Ride> get myRides => rides.mine(guardId);

  void clearRideNotice() {
    if (rideNotice == null) return;
    rideNotice = null;
    notifyListeners();
  }

  /// People who can decide on a walk-in: everyone with role `cso`.
  List<Guard> get csos => [for (final g in snapshot?.guards ?? const <Guard>[]) if (g.isCso) g];

  // --- lifecycle --------------------------------------------------------------------------

  Future<void> init() async {
    _token = await secrets.token();
    if (_token == null) {
      phase = Phase.unpaired;
      notifyListeners();
      return;
    }
    snapshot = await store.loadSnapshot();
    keys = await secrets.hmacKeys();
    estateName = await store.meta('estate_name');
    gateName = await store.meta('gate_name');
    final last = await store.meta('last_sync_at');
    lastSyncAt = last == null ? null : DateTime.parse(last);
    final shiftRaw = await store.meta('shift');
    shift = shiftRaw == null ? null : OpenShift.fromJson(jsonDecode(shiftRaw) as Map<String, dynamic>);
    final triesRaw = await store.meta('pin_tries');
    _tries = PinTries(triesRaw == null ? null : jsonDecode(triesRaw) as Map<String, dynamic>);
    final houseRaw = await store.meta('house_code_tries');
    _houseTries = PinTries(houseRaw == null ? null : jsonDecode(houseRaw) as Map<String, dynamic>);
    await _loadCso();
    await _reloadOutbox();
    await _autoEndIfDue();
    _updatePhase();
    notifyListeners();
    unawaited(_trackIfRider());
  }

  /// Start syncing: now, every [pollEvery] in the foreground, when the network returns,
  /// and when a push says so.
  void start() {
    _subs.add(push.syncRequests.listen((_) => syncNow()));
    _subs.add(push.tokenRefresh.listen((t) async {
      final token = _token;
      if (token == null) return;
      try {
        await api.putFcmToken(token, t);
      } catch (_) {}
    }));
    final c = _connectivity;
    if (c != null) {
      _subs.add(c.listen((isOnline) {
        final cameBack = isOnline && !online;
        online = isOnline;
        notifyListeners();
        if (cameBack) syncNow();
      }));
    }
    setForeground(true);
  }

  void setForeground(bool fg) {
    _poll?.cancel();
    _poll = null;
    if (fg) {
      _poll = Timer.periodic(pollEvery, (_) => syncNow());
      syncNow();
    }
  }

  bool _disposed = false;

  /// A sync that finishes after the app (or a test) has let go of the controller is ignored.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    unawaited(positions?.stop());
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _updatePhase() {
    if (_token == null) {
      phase = Phase.unpaired;
    } else if (shift == null || snapshot == null) {
      phase = Phase.startShift;
    } else {
      phase = Phase.ready;
    }
  }

  Future<void> _reloadOutbox() async {
    _outbox = await store.outbox();
    view = GateView.build(snapshot, _outbox);
    rides = RideView.build(snapshot, _outbox);
  }

  // --- pairing ----------------------------------------------------------------------------

  /// "abcd 2345", "ABCD-2345" -> "ABCD-2345"; null unless 8 letters/digits.
  static String? normalizePairingCode(String raw) {
    final s = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return s.length == 8 ? '${s.substring(0, 4)}-${s.substring(4)}' : null;
  }

  /// Throws [ApiException] (wrong code, too many tries) or [NetworkException].
  Future<void> pair(String code) async {
    final res = await api.pair(code, fcmToken: await push.token());
    await store.wipe();
    await secrets.setToken(res.token);
    await store.setMeta('estate_name', res.estateName);
    await store.setMeta('gate_name', res.gateName);
    _token = res.token;
    estateName = res.estateName;
    gateName = res.gateName;
    _resetLocal();
    await _reloadOutbox();
    _updatePhase();
    notifyListeners();
    await syncNow();
  }

  void _resetLocal() {
    snapshot = null;
    keys = {};
    shift = null;
    _tries = PinTries();
    _houseTries = PinTries();
    rideNotice = null;
    _lostRides.clear();
    lastSyncAt = null;
    cso = null;
    csoFetchedAt = null;
    csoError = null;
  }

  Future<void> _forget() async {
    await positions?.stop();
    await store.wipe();
    await secrets.wipeSession();
    _token = null;
    estateName = null;
    gateName = null;
    _resetLocal();
    await _reloadOutbox();
    _updatePhase();
    notifyListeners();
  }

  // --- shift start: name, PIN, selfie -----------------------------------------------------

  /// The PIN hash to check against: one set on this phone and not yet synced wins over the
  /// state's, until it syncs. If the sync rejected it, the state's (null after a reset) applies.
  String? pinHashFor(String guardId) => view.localPins[guardId] ?? snapshot?.guard(guardId)?.pinHash;

  PinStep pinStepFor(Guard g) {
    if (!g.consent) return PinStep.noConsent;
    if (_tries.lockedUntil(g.id, _clock()) != null) return PinStep.locked;
    return pinHashFor(g.id) == null ? PinStep.setPin : PinStep.enterPin;
  }

  DateTime? lockedUntil(String guardId) => _tries.lockedUntil(guardId, _clock());

  /// Checks the PIN offline. Five wrong tries lock this person out on this phone for 5 minutes.
  Future<PinCheck> checkGuardPin(String guardId, String pin) async {
    final locked = _tries.lockedUntil(guardId, _clock());
    if (locked != null) return PinLocked(locked);
    final hash = pinHashFor(guardId);
    if (hash == null) return const PinWrong(pinMaxTries);
    if (await pins.check(pin, hash)) {
      _tries.clear(guardId);
      await _saveTries();
      return const PinOk();
    }
    final lockedNow = _tries.fail(guardId, _clock());
    await _saveTries();
    notifyListeners();
    return lockedNow != null ? PinLocked(lockedNow) : PinWrong(_tries.triesLeft(guardId));
  }

  Future<void> _saveTries() => store.setMeta('pin_tries', jsonEncode(_tries.toJson()));

  /// A first PIN, or a new one after the admin reset it. Only the hash is queued; the PIN
  /// never leaves the phone.
  Future<void> setGuardPin(String guardId, String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('A PIN is 6 digits.');
    final hash = await pins.hash(pin);
    final id = 'pin:$guardId:${_uuid.v4()}';
    await store.enqueue(OutboxKind.pin, id, {'guard_id': guardId, 'pin_hash': hash, 'set_at': isoNow(_clock())}, at: _clock());
    _tries.clear(guardId);
    await _saveTries();
    await _reloadOutbox();
    notifyListeners();
    unawaited(syncNow());
  }

  /// Opens the shift. [selfieJpeg] is null when the camera failed or was skipped: the shift
  /// still starts, marked `selfie_taken: false`. The selfie waits in the encrypted database and
  /// uploads after the shift has synced.
  ///
  /// A rider's shift carries the motorcycle they picked ([shuttleId], from `shuttle.shuttles`),
  /// and starts position reporting until the shift ends.
  Future<void> openShift(String guardId, {List<int>? selfieJpeg, String? shuttleId}) async {
    final g = snapshot?.guard(guardId);
    if (g == null || !g.consent) throw StateError('That person cannot start a shift.');
    if (shuttleId != null && (!g.isRider || shuttle?.bike(shuttleId) == null)) throw ArgumentError('Only a rider picks a motorcycle.');
    final id = _uuid.v4();
    final s = OpenShift(id: id, guardId: guardId, startedAt: _clock(), selfieTaken: selfieJpeg != null, shuttleId: shuttleId);
    await store.enqueue(OutboxKind.shift, id, {
      'id': id,
      'guard_id': guardId,
      'started_at': isoNow(s.startedAt),
      'selfie_taken': s.selfieTaken,
      'shuttle_id': ?shuttleId,
    }, at: _clock());
    if (selfieJpeg != null) await store.saveSelfie(id, selfieJpeg, _clock());
    shift = s;
    await store.setMeta('shift', jsonEncode(s.toJson()));
    cso = null;
    csoFetchedAt = null;
    csoError = null;
    await store.setMeta('cso', null);
    rideNotice = null;
    _lostRides.clear();
    await _reloadOutbox();
    _updatePhase();
    notifyListeners();
    unawaited(_trackIfRider());
    unawaited(syncNow());
  }

  /// Positions are recorded during an open rider shift, and only then.
  Future<void> _trackIfRider() async {
    final s = shift, p = positions;
    if (p == null) return;
    if (s == null || !isRider || shuttle == null) {
      await p.stop();
      return;
    }
    await p.start(s.id);
  }

  /// After "Turn on location": ask again, or open the settings if Android will not ask.
  Future<void> retryLocation() async {
    final p = positions;
    if (p == null) return;
    if (p.problem == LocationAccess.deniedForever || p.problem == LocationAccess.serviceOff) await p.source.openSettings();
    await p.stop();
    await _trackIfRider();
  }

  /// What the end-of-shift record reports: still inside, not yet sent, night list unchecked.
  Handover handoverNow() => Handover(
        inside: view.inside.length,
        unsynced: view.queued,
        nightListOpen: view.nightListOpen(snapshot?.rollup),
      );

  /// People who can take over: everyone with consent, other than the person ending. A rider
  /// hands over to another rider; a guard or the CSO to a guard or the CSO.
  List<Guard> get takeoverCandidates => [
        for (final g in snapshot?.guards ?? const <Guard>[])
          if (g.consent && g.id != guardId && g.isRider == isRider) g,
      ];

  /// Ends the open shift and goes back to the shift start screen. [handedTo] null = nobody.
  Future<void> endShift({String? handedTo, String? reason, DateTime? at}) async {
    final s = shift;
    if (s == null) return;
    // No position is recorded after the shift ends. Ones already queued were recorded during
    // it and go before the shift's end (see _runSync).
    await positions?.stop();
    final ended = at ?? _clock();
    final handover = handoverNow();
    await store.enqueue(OutboxKind.shift, '${s.id}:end', {
      'id': s.id,
      'guard_id': s.guardId,
      'started_at': isoNow(s.startedAt),
      'selfie_taken': s.selfieTaken,
      'ended_at': isoNow(ended),
      'end_reason': reason ?? (handedTo != null ? 'handover' : 'ended'),
      'handed_to': handedTo,
      'handover': handover.toJson(),
      'shuttle_id': ?s.shuttleId,
    }, at: _clock());
    shift = null;
    rideNotice = null;
    _lostRides.clear();
    await store.setMeta('shift', null);
    cso = null;
    csoFetchedAt = null;
    await store.setMeta('cso', null);
    await _reloadOutbox();
    _updatePhase();
    notifyListeners();
    unawaited(syncNow());
  }

  /// A shift nobody ended closes itself after 14 hours.
  Future<bool> _autoEndIfDue() async {
    final s = shift;
    if (s == null || _clock().isBefore(s.autoEndAt)) return false;
    await endShift(reason: 'auto', at: s.autoEndAt);
    return true;
  }

  /// Called by the UI's minute timer as well as every sync.
  Future<void> checkShiftExpiry() => _autoEndIfDue();

  // --- sync -------------------------------------------------------------------------------

  /// Push the outbox, then pull state, then upload selfies. A call made while a sync runs gets
  /// one more run after it (several such calls share that run), so a record made mid-sync is
  /// never left behind.
  Future<void> syncNow() {
    final running = _running;
    if (running == null) {
      final f = _runSync().whenComplete(() => _running = null);
      _running = f;
      return f;
    }
    return _next ??= running.then((_) {
      _next = null;
      return syncNow();
    });
  }

  /// True while a sync is running or queued.
  bool get busy => _running != null || _next != null;

  /// Completes when no sync is running or queued (tests, shutdown).
  Future<void> idle() async {
    while (_running != null || _next != null) {
      await (_next ?? _running);
    }
  }

  Future<void> _runSync() async {
    final token = _token;
    if (token == null) return;
    syncing = true;
    notifyListeners();
    try {
      await _autoEndIfDue();
      // With rider positions queued: everything but shift ends, then the positions (the server
      // takes them only while the shift is open), then the shift ends. Otherwise one push.
      final hold = positions != null && (await store.positions(limit: 1)).isNotEmpty;
      final report = await _pusher.push(token, only: hold ? (i) => !_isShiftEnd(i) : null);
      if (report.interrupted) throw NetworkException('No connection.');
      if (hold) {
        await positions!.flush(token, api, store.isPending);
        final ends = await _pusher.push(token, only: _isShiftEnd);
        if (ends.interrupted) throw NetworkException('No connection.');
      }
      await _settleLostRides();
      final pullStarted = _clock();
      final etag = snapshot == null ? null : await store.meta('etag');
      final res = await api.fetchState(token, etag: etag);
      if (!res.notModified) {
        final body = res.body!;
        final snap = StateSnapshot.fromJson(body);
        final newKeys = StateSnapshot.keysFromJson(body);
        await secrets.setHmacKeys(newKeys);
        await store.saveSnapshot(snap);
        await store.setMeta('etag', res.etag);
        snapshot = snap;
        keys = newKeys;
        _lostRides.clear(); // the pulled rides say who has them now
        unawaited(_trackIfRider());
      }
      await store.deleteItems(selectPurgeable(await store.outbox(), pullStarted));
      // After the push, so the shift has reached the server; a 404 waits for the next sync.
      await _selfies.upload(token);
      lastSyncAt = _clock();
      await store.setMeta('last_sync_at', lastSyncAt!.toIso8601String());
      lastError = null;
      online = true;
    } on UnauthorizedException {
      syncing = false;
      await _forget();
      return;
    } on NetworkException catch (e) {
      lastError = e.message;
    } on ApiException catch (e) {
      lastError = e.detail;
    } catch (e) {
      lastError = 'Sync failed.';
      debugPrint('sync failed: ${e.runtimeType}');
    }
    syncing = false;
    await _reloadOutbox();
    _updatePhase();
    notifyListeners();
  }

  static bool _isShiftEnd(OutboxItem i) => i.kind == OutboxKind.shift && i.payload['ended_at'] != null;

  bool _flushQueued = false;

  /// A new position: send it now if there is a network (a sync running sends it anyway).
  void _flushPositionsSoon() {
    final token = _token, p = positions;
    if (token == null || p == null || _flushQueued) return;
    _flushQueued = true;
    scheduleMicrotask(() async {
      _flushQueued = false;
      if (_running != null) return;
      try {
        await p.flush(token, api, store.isPending);
      } on UnauthorizedException {
        await _forget();
      } catch (e) {
        debugPrint('positions flush failed: ${e.runtimeType}');
      }
    });
  }

  /// A "take it" that lost to another rider is not something to fix later: say who has the
  /// ride, drop it from this rider's list, and take the record off the queue.
  Future<void> _settleLostRides() async {
    final lost = (await store.outbox(status: OutboxStatus.rejected))
        .where((i) => i.kind == OutboxKind.rideEvent && i.payload['event'] == 'accept')
        .toList();
    if (lost.isEmpty) return;
    for (final i in lost) {
      _lostRides.add((i.payload['ride_id'] as String).toLowerCase());
      final reason = (i.reason ?? '').trim();
      rideNotice = reason.isEmpty ? 'Another rider has this ride.' : '${reason[0].toUpperCase()}${reason.substring(1)}';
    }
    await store.deleteItems(lost.map((i) => i.id));
  }

  // --- the CSO overview -------------------------------------------------------------------

  Future<void> _loadCso() async {
    final raw = await store.meta('cso');
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      cso = CsoOverview.fromJson(j['body'] as Map<String, dynamic>);
      csoFetchedAt = DateTime.parse(j['fetched_at'] as String);
    } catch (_) {
      await store.setMeta('cso', null);
    }
  }

  /// `GET /v1/device/cso` with the CSO's open shift. Keeps the last copy when offline. A 404
  /// or 403 right after the shift opened means the shift has not synced yet: sync first.
  Future<void> refreshCso() async {
    final token = _token, s = shift;
    if (token == null || s == null || !isCso || csoLoading) return;
    csoLoading = true;
    notifyListeners();
    try {
      if (await store.isPending(s.id)) await syncNow();
      final body = await api.fetchCso(token, s.id);
      cso = CsoOverview.fromJson(body);
      csoFetchedAt = _clock();
      csoError = null;
      await store.setMeta('cso', jsonEncode({'fetched_at': csoFetchedAt!.toIso8601String(), 'body': body}));
    } on UnauthorizedException {
      csoLoading = false;
      await _forget();
      return;
    } on NetworkException {
      csoError = 'No connection. Showing the last copy.';
    } on ApiException catch (e) {
      csoError = e.status == 403 ? 'The CSO view needs this shift to reach the server first.' : e.detail;
    } catch (e) {
      csoError = 'Could not load.';
      debugPrint('cso fetch failed: ${e.runtimeType}');
    }
    csoLoading = false;
    notifyListeners();
  }

  // --- recording --------------------------------------------------------------------------

  String get _now => isoNow(_clock());
  String? get _gateId => snapshot?.deviceGateId;

  /// Who and which shift: on every record.
  Map<String, dynamic> get _who {
    final s = shift;
    if (s == null) throw StateError('No shift is open. Start a shift first.');
    return {'guard_id': s.guardId, 'shift_id': s.id};
  }

  Future<String> _record(String kind, Map<String, dynamic> payload, {String? id}) async {
    final itemId = id ?? payload['id'] as String;
    await store.enqueue(kind, itemId, payload, at: _clock());
    await _reloadOutbox();
    notifyListeners();
    unawaited(syncNow());
    return itemId;
  }

  static String? _plate(String? typed) {
    final p = typed?.trim();
    return p == null || p.isEmpty ? null : p;
  }

  /// Offline code check against the cached visits, with this phone's records laid over them.
  CodeCheck verifyCode(String code) => checkCode(code, view.visits.values, keys, _clock().millisecondsSinceEpoch ~/ 1000);

  Future<String> admitWithCode(Visit v, {String? plate}) =>
      _entry(homeId: v.homeId, guestName: v.guestName, method: 'code', visitId: v.id, plate: plate);

  /// A guest already confirmed by phone ("Coming later") has arrived.
  Future<String> admitExpected(Visit v, {String? plate}) =>
      _entry(homeId: v.homeId, guestName: v.guestName, method: 'callback_confirmed', visitId: v.id, plate: plate);

  /// No code, resident confirmed on the callback, guest is here: in now. The server makes the
  /// visit, which comes back in /state carrying this entry's id.
  Future<String> admitOnCallback(String homeId, String guestName, {String? plate}) =>
      _entry(homeId: homeId, guestName: guestName, method: 'callback_confirmed', plate: plate);

  /// Nobody at the home could be reached and the CSO (or guard on duty) decided to admit.
  /// Both who decided and the reason are required; the server rejects it without them.
  Future<String> admitWalkIn({required String homeId, required String guestName, required String decidedBy, required String reason, String? plate}) {
    if (decidedBy.trim().isEmpty) throw ArgumentError('Pick who decided.');
    if (reason.trim().isEmpty) throw ArgumentError('A walk-in needs a reason.');
    return _entry(homeId: homeId, guestName: guestName, method: 'walk_in_admitted', decidedBy: decidedBy, reason: reason.trim(), plate: plate);
  }

  Future<String> turnAway({required String homeId, required String guestName, String? visitId, String? reason, String? plate}) =>
      _entry(homeId: homeId, guestName: guestName, method: 'refused', visitId: visitId, reason: reason, plate: plate);

  Future<String> _entry({
    required String homeId,
    required String guestName,
    required String method,
    String? visitId,
    String? reason,
    String? decidedBy,
    String? plate,
  }) =>
      _record(OutboxKind.entry, {
        'id': _uuid.v4(),
        'home_id': homeId,
        'guest_name': guestName.trim(),
        'method': method,
        'visit_id': visitId,
        ..._who,
        'gate_id': _gateId,
        'plate': _plate(plate),
        'decided_by': decidedBy,
        'reason': (reason?.trim().isEmpty ?? true) ? null : reason!.trim(),
        'at': _now,
      });

  /// Exit by code or by tapping the name in the Leaving list.
  Future<String> recordExit(InsideGuest g, {required String method, String? plate}) => _record(OutboxKind.exit, {
        'id': _uuid.v4(),
        'method': method,
        'entry_id': g.entryId,
        'visit_id': g.visitId,
        'guest_name': g.guestName,
        ..._who,
        'gate_id': _gateId,
        'plate': _plate(plate),
        'at': _now,
      });

  Future<String> exitByCode(Visit v, {String? plate}) =>
      recordExit(InsideGuest(homeId: v.homeId, guestName: v.guestName, visitId: v.id, entryId: v.entryId), method: 'code', plate: plate);

  /// The CSO marks an overdue guest as gone (`list_tap`, as from the Leaving list).
  Future<String> markLeft(String visitId, String guestName) {
    final v = view.visits[visitId.toLowerCase()];
    return recordExit(
      InsideGuest(homeId: v?.homeId ?? '', guestName: v?.guestName ?? guestName, visitId: visitId.toLowerCase(), entryId: v?.entryId),
      method: 'list_tap',
    );
  }

  /// Someone leaving who is not on the list: name only.
  Future<String> exitUnlisted(String guestName, {String? plate}) => _record(OutboxKind.exit, {
        'id': _uuid.v4(),
        'method': 'list_tap',
        'entry_id': null,
        'visit_id': null,
        'guest_name': guestName.trim(),
        ..._who,
        'gate_id': _gateId,
        'plate': _plate(plate),
        'at': _now,
      });

  Future<String> recordCallback({required String homeId, required String numberId, required String outcome, String? visitId}) =>
      _record(OutboxKind.callback, _callback(homeId: homeId, numberId: numberId, outcome: outcome, visitId: visitId));

  Map<String, dynamic> _callback({required String homeId, required String numberId, required String outcome, String? visitId, String? id, String? at}) => {
        'id': id ?? _uuid.v4(),
        'home_id': homeId,
        'number_id': numberId,
        'outcome': outcome,
        'visit_id': visitId,
        ..._who,
        'at': at ?? _now,
      };

  /// The resident confirmed on the callback. Recorded at once, so the call is on file even if
  /// the guard never gets to choose in now or later.
  Future<ConfirmedCall> recordConfirmedCall({required String homeId, required String numberId}) async {
    final payload = _callback(homeId: homeId, numberId: numberId, outcome: 'confirmed');
    await _record(OutboxKind.callback, payload);
    return ConfirmedCall(payload);
  }

  /// Confirmed, "Coming later: expect them": the visit, then the confirming call again with the
  /// visit, so the server links them.
  Future<String> expectLater({
    required Home home,
    required String? residentId,
    required ConfirmedCall call,
    required String guestName,
    required Stay stay,
    DateTime? until,
  }) async {
    final who = _who;
    final plan = planVisit(time, stay, until: until);
    final id = _uuid.v4();
    await store.enqueue(OutboxKind.visit, id, {
      'id': id,
      'home_id': home.id,
      'resident_id': residentId,
      'guest_name': guestName.trim(),
      'window_start': isoNow(plan.windowStart),
      'window_end': isoNow(plan.windowEnd),
      'expected_until': isoNow(plan.expectedUntil),
      'stay_type': plan.stayType,
      'stay_minutes': plan.stayMinutes,
      'stay_given': true,
      ...who,
    }, at: _clock());
    await store.requeue(OutboxKind.callback, call.id, {...call.payload, 'visit_id': id}, at: _clock());
    await _reloadOutbox();
    notifyListeners();
    unawaited(syncNow());
    return id;
  }

  Future<void> rollupCheck(String itemId, String result) =>
      _record(OutboxKind.rollupCheck, {'item_id': itemId, 'result': result, ..._who, 'at': _now}, id: itemId);

  Future<void> reportNumber(String directoryEntryId) =>
      _record(OutboxKind.directoryReport, {'entry_id': directoryEntryId, 'guard_id': guardId}, id: _uuid.v4());

  // --- the shuttle ------------------------------------------------------------------------

  Future<String> _rideEvent(Ride r, String event, {RideConfirm? who}) {
    final here = positions?.last;
    return _record(OutboxKind.rideEvent, {
      'id': _uuid.v4(),
      'ride_id': r.id,
      'event': event,
      ..._who,
      ...?who?.toJson(),
      'lat': here?.lat,
      'lng': here?.lng,
      'at': _now,
    });
  }

  /// Take it. If another rider got there first, the sync says "taken by" and the ride goes.
  Future<String> acceptRide(Ride r) => _rideEvent(r, 'accept');

  /// Hand back: the ride goes back to the queue.
  Future<String> releaseRide(Ride r) => _rideEvent(r, 'release');
  Future<String> noShow(Ride r) => _rideEvent(r, 'no_show');

  /// Picked up, with who rode. A parcel's receiver is recorded at drop-off instead.
  Future<String> pickUp(Ride r, {RideConfirm? who}) => _rideEvent(r, 'pick_up', who: r.isDelivery ? null : who);
  Future<String> dropOff(Ride r, {RideConfirm? who}) => _rideEvent(r, 'drop_off', who: r.isDelivery ? who : null);

  Map<String, dynamic> _rideRecord({
    required String kind,
    required String source,
    required Home home,
    required RideStop pickup,
    required RideStop dropoff,
    String? residentId,
    String? passenger,
    DateTime? wantedAt,
    String? note,
  }) {
    if (shuttle == null) throw StateError('This estate runs no shuttle.');
    if (pickup.sameAs(dropoff)) throw ArgumentError('The pickup and the drop-off are the same place.');
    String? clean(String? v) => (v?.trim().isEmpty ?? true) ? null : v!.trim();
    return {
      'id': _uuid.v4(),
      'kind': kind,
      'source': source,
      'home_id': home.id,
      'resident_id': residentId,
      'passenger': clean(passenger),
      'pickup': pickup.toRef(),
      'dropoff': dropoff.toRef(),
      'wanted_at': wantedAt == null ? null : isoNow(wantedAt),
      'note': clean(note),
      ..._who,
      'at': _now,
    };
  }

  /// "Shuttle to the home" from the gate: a parcel (what it is) or a guest (their name), from
  /// this phone's gate to the home.
  Future<String> bookAtGate({required Home home, required String kind, required String passenger, String? note}) {
    if (kind != RideKind.delivery && kind != RideKind.guest) throw ArgumentError('A gate booking is a parcel or a guest.');
    final gate = _gateId;
    return _record(
      OutboxKind.ride,
      _rideRecord(
        kind: kind,
        source: 'gate',
        home: home,
        passenger: passenger,
        note: note,
        pickup: RideStop(kind: 'gate', ref: gate, label: snapshot?.gateName(gate) ?? 'Gate'),
        dropoff: RideStop(kind: 'home', ref: home.id, label: home.displayAddress),
      ),
    );
  }

  /// The CSO books a ride for a resident who rang.
  Future<String> bookDispatch({
    required Home home,
    required String residentId,
    required RideStop pickup,
    required RideStop dropoff,
    DateTime? wantedAt,
    String? note,
  }) =>
      _record(
        OutboxKind.ride,
        _rideRecord(
          kind: RideKind.resident,
          source: 'dispatch',
          home: home,
          residentId: residentId,
          pickup: pickup,
          dropoff: dropoff,
          wantedAt: wantedAt,
          note: note,
        ),
      );

  /// Flagged down: the ride and its pickup, in the same batch. Returns the ride id.
  Future<String> newFlagRide({required Home home, required RideStop pickup, required RideStop dropoff, required RideConfirm who}) async {
    final ride = _rideRecord(kind: RideKind.resident, source: 'flag', home: home, residentId: who.residentId, pickup: pickup, dropoff: dropoff);
    final id = ride['id'] as String;
    await store.enqueue(OutboxKind.ride, id, ride, at: _clock());
    final here = positions?.last;
    final ev = _uuid.v4();
    await store.enqueue(OutboxKind.rideEvent, ev, {
      'id': ev,
      'ride_id': id,
      'event': 'pick_up',
      ..._who,
      ...who.toJson(),
      'lat': here?.lat,
      'lng': here?.lng,
      'at': _now,
    }, at: _clock());
    await _reloadOutbox();
    notifyListeners();
    unawaited(syncNow());
    return id;
  }

  /// The card with this UID, from `shuttle.cards` (or issued on this phone and not yet synced).
  EstateCard? cardFor(String uid) {
    final estateId = snapshot?.estate.id;
    final s = shuttle;
    if (estateId == null || s == null || !isPlausibleUid(uid)) return null;
    final hash = cardHash(estateId, uid);
    final known = s.cardByHash(hash);
    if (known != null) return known;
    for (final i in _outbox.where((i) => i.kind == OutboxKind.card && i.isLive)) {
      if (i.payload['uid_hash'] == hash) {
        final r = snapshot?.resident(i.payload['resident_id'] as String?);
        if (r != null) return EstateCard(id: i.payload['id'] as String, uidHash: hash, residentId: r.id, homeId: r.homeId);
      }
    }
    return null;
  }

  /// The CSO issues a card: tapped, then given to [resident]. Only the hash and the last 4 hex
  /// digits leave the phone. The server refuses a card that is already someone else's.
  Future<String> issueCard({required String uid, required Resident resident}) {
    final estateId = snapshot?.estate.id;
    if (!isCso || estateId == null || shuttle == null) throw StateError('Only the CSO issues estate cards.');
    if (!isPlausibleUid(uid)) throw ArgumentError('That is not a card.');
    return _record(OutboxKind.card, {
      'id': _uuid.v4(),
      'resident_id': resident.id,
      'uid_hash': cardHash(estateId, uid),
      'uid_last4': uidLast4(uid),
      ..._who,
      'at': _now,
    });
  }

  /// A queued record by id (to see whether the server took it).
  Future<OutboxItem?> queuedItem(String id) async => (await store.outbox()).where((i) => i.id == id).firstOrNull;

  DateTime? houseCodeLockedUntil(String homeId) => _houseTries.lockedUntil(homeId, _clock());

  /// The resident says their home's 4 digits; checked offline against the home's hash, like a
  /// PIN. Five wrong tries on one home: wait 5 minutes. The code is never stored or logged.
  Future<HouseCodeCheck> checkHouseCode(String homeId, String code) async {
    final hash = snapshot?.home(homeId)?.houseCodeHash;
    if (hash == null) return const HouseCodeNone();
    final locked = _houseTries.lockedUntil(homeId, _clock());
    if (locked != null) return HouseCodeLocked(locked);
    if (RegExp(r'^\d{4}$').hasMatch(code) && await pins.check(code, hash)) {
      _houseTries.clear(homeId);
      await store.setMeta('house_code_tries', jsonEncode(_houseTries.toJson()));
      return const HouseCodeOk();
    }
    final lockedNow = _houseTries.fail(homeId, _clock());
    await store.setMeta('house_code_tries', jsonEncode(_houseTries.toJson()));
    notifyListeners();
    return lockedNow != null ? HouseCodeLocked(lockedNow) : HouseCodeWrong(_houseTries.triesLeft(homeId));
  }

  /// Undo a record that has not left the phone yet.
  Future<bool> undo(String id) async {
    final ok = await store.cancelPending(id);
    await _reloadOutbox();
    notifyListeners();
    return ok;
  }

  Future<void> dismissRejected(String id) async {
    await store.deleteItems([id]);
    await _reloadOutbox();
    notifyListeners();
  }

  /// One line describing a queued record, for the needs-attention list. No phone numbers.
  String describe(OutboxItem i) {
    final p = i.payload;
    String home(Object? id) => id == null ? '' : (snapshot?.home(id as String)?.displayAddress ?? 'unknown home');
    String person(Object? id) => snapshot?.guard(id as String?)?.name ?? 'someone';
    return switch (i.kind) {
      OutboxKind.entry => '${switch (p['method']) {
          'refused' => 'Turned away',
          'walk_in_admitted' => 'Walk-in',
          _ => 'Entry',
        }}: ${p['guest_name']}, ${home(p['home_id'])}',
      OutboxKind.exit => 'Exit: ${p['guest_name'] ?? 'guest'}',
      OutboxKind.visit => 'Expected guest: ${p['guest_name']}, ${home(p['home_id'])}',
      OutboxKind.callback => 'Callback (${p['outcome']}), ${home(p['home_id'])}',
      OutboxKind.rollupCheck => 'Night list check',
      OutboxKind.directoryReport => 'Number reported not working',
      OutboxKind.pin => 'New PIN for ${person(p['guard_id'])}. Set it again at the next shift.',
      OutboxKind.shift => '${p['ended_at'] == null ? 'Shift start' : 'Shift end'}: ${person(p['guard_id'])}',
      OutboxKind.card => 'Estate card for ${snapshot?.resident(p['resident_id'] as String?)?.name ?? 'a resident'}',
      OutboxKind.ride => 'Shuttle booking: ${rideKindLabel(p['kind'] as String? ?? '')}, ${home(p['home_id'])}',
      OutboxKind.rideEvent => 'Shuttle ride: ${switch (p['event']) {
          'accept' => 'take it',
          'release' => 'hand back',
          'pick_up' => 'picked up',
          'drop_off' => 'dropped off',
          'no_show' => 'no-show',
          _ => '${p['event']}',
        }}',
      _ => i.kind,
    };
  }
}

/// A confirmed callback already queued: its record, to send again once the visit it confirmed exists.
class ConfirmedCall {
  ConfirmedCall(this.payload);
  final Map<String, dynamic> payload;
  String get id => payload['id'] as String;
}
