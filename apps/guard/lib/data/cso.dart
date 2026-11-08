/// `GET /v1/device/cso`: what needs the CSO, who is on duty, today's shifts. Read live; the
/// phone keeps the last copy so the Now tab still shows something with no network.
library;

DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v as String);
List<Map<String, dynamic>> _list(Object? v) => [for (final i in (v as List? ?? const [])) i as Map<String, dynamic>];

class OverdueGuest {
  const OverdueGuest({required this.visitId, required this.guestName, required this.homeId, this.address, this.expectedUntil, this.residentId});
  final String visitId;
  final String guestName;
  final String homeId;
  final String? address;
  final DateTime? expectedUntil;
  final String? residentId;

  factory OverdueGuest.fromJson(Map<String, dynamic> j) => OverdueGuest(
        visitId: (j['visit_id'] as String).toLowerCase(),
        guestName: j['guest_name'] as String,
        homeId: (j['home_id'] as String).toLowerCase(),
        address: j['address'] as String?,
        expectedUntil: _dt(j['expected_until']),
        residentId: j['resident_id'] as String?,
      );
}

/// A refusal or a walk-in decision made today at any gate.
class GateDecision {
  const GateDecision({required this.entryId, required this.guestName, this.address, this.gate, this.who, this.reason, this.at});
  final String entryId;
  final String guestName;
  final String? address;
  final String? gate;

  /// Who turned them away (refusals) or who decided to admit (walk-ins).
  final String? who;
  final String? reason;
  final DateTime? at;

  factory GateDecision.fromJson(Map<String, dynamic> j, String whoKey) => GateDecision(
        entryId: j['entry_id'] as String,
        guestName: j['guest_name'] as String,
        address: j['address'] as String?,
        gate: j['gate'] as String?,
        who: j[whoKey] as String?,
        reason: j['reason'] as String?,
        at: _dt(j['at']),
      );
}

class QuietPhone {
  const QuietPhone({required this.deviceId, this.gate, this.label, this.lastSyncAt, this.onDuty});
  final String deviceId;
  final String? gate;
  final String? label;
  final DateTime? lastSyncAt;
  final String? onDuty;

  factory QuietPhone.fromJson(Map<String, dynamic> j) => QuietPhone(
        deviceId: j['device_id'] as String,
        gate: j['gate'] as String?,
        label: j['label'] as String?,
        lastSyncAt: _dt(j['last_sync_at']),
        onDuty: j['on_duty'] as String?,
      );
}

class OnDuty {
  const OnDuty({this.gate, this.guard, this.role, this.since, this.phoneLastSyncAt});
  final String? gate;
  final String? guard;
  final String? role;
  final DateTime? since;
  final DateTime? phoneLastSyncAt;

  factory OnDuty.fromJson(Map<String, dynamic> j) => OnDuty(
        gate: j['gate'] as String?,
        guard: j['guard'] as String?,
        role: j['role'] as String?,
        since: _dt(j['since']),
        phoneLastSyncAt: _dt(j['phone_last_sync_at']),
      );
}

class ShiftToday {
  const ShiftToday({
    required this.id,
    this.gate,
    this.guard,
    this.startedAt,
    this.endedAt,
    this.endReason,
    this.handedTo,
    this.handover,
    this.selfie = false,
  });
  final String id;
  final String? gate;
  final String? guard;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? endReason;
  final String? handedTo;
  final Map<String, dynamic>? handover;

  /// Whether a selfie is on file. The phone never shows the selfie itself.
  final bool selfie;

  factory ShiftToday.fromJson(Map<String, dynamic> j) => ShiftToday(
        id: j['id'] as String,
        gate: j['gate'] as String?,
        guard: j['guard'] as String?,
        startedAt: _dt(j['started_at']),
        endedAt: _dt(j['ended_at']),
        endReason: j['end_reason'] as String?,
        handedTo: j['handed_to'] as String?,
        handover: j['handover'] as Map<String, dynamic>?,
        selfie: (j['selfie'] as bool?) ?? false,
      );
}

/// A shuttle ride nobody has taken 10 minutes after it was wanted.
class WaitingRide {
  const WaitingRide({required this.rideId, required this.kind, this.from, this.to, this.wantedAt});
  final String rideId;
  final String kind;
  final String? from;
  final String? to;
  final DateTime? wantedAt;

  factory WaitingRide.fromJson(Map<String, dynamic> j) => WaitingRide(
        rideId: (j['ride_id'] as String).toLowerCase(),
        kind: (j['kind'] as String?) ?? 'resident',
        from: j['from'] as String?,
        to: j['to'] as String?,
        wantedAt: _dt(j['wanted_at']),
      );
}

class CsoOverview {
  const CsoOverview({
    required this.serverTime,
    required this.overdue,
    required this.refusedToday,
    required this.walkInsToday,
    required this.quietPhones,
    required this.nightListUnchecked,
    required this.onDuty,
    required this.shiftsToday,
    this.ridesWaiting = const [],
  });

  final DateTime? serverTime;
  final List<OverdueGuest> overdue;
  final List<GateDecision> refusedToday;
  final List<GateDecision> walkInsToday;
  final List<QuietPhone> quietPhones;
  final int nightListUnchecked;
  final List<OnDuty> onDuty;
  final List<ShiftToday> shiftsToday;

  /// Shuttle rides waiting over 10 minutes (empty when the estate runs no shuttle).
  final List<WaitingRide> ridesWaiting;

  factory CsoOverview.fromJson(Map<String, dynamic> j) {
    final needs = (j['needs'] as Map<String, dynamic>?) ?? const {};
    return CsoOverview(
      serverTime: _dt(j['server_time']),
      overdue: [for (final o in _list(needs['overdue'])) OverdueGuest.fromJson(o)],
      refusedToday: [for (final o in _list(needs['refused_today'])) GateDecision.fromJson(o, 'by')],
      walkInsToday: [for (final o in _list(needs['walk_ins_today'])) GateDecision.fromJson(o, 'decided_by')],
      quietPhones: [for (final o in _list(needs['quiet_phones'])) QuietPhone.fromJson(o)],
      nightListUnchecked: (needs['night_list_unchecked'] as num?)?.toInt() ?? 0,
      onDuty: [for (final o in _list(j['on_duty'])) OnDuty.fromJson(o)],
      shiftsToday: [for (final o in _list(j['shifts_today'])) ShiftToday.fromJson(o)],
      ridesWaiting: [for (final o in _list(needs['rides_waiting'])) WaitingRide.fromJson(o)],
    );
  }
}
