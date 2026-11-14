/// The gate's view of the estate, as returned by `GET /v1/device/state`.
///
/// Phone numbers are held in full so callbacks work with no data. Nothing here may
/// print a full number: [PhoneNumber.toString] is masked on purpose.
library;

import 'dart:convert';

import 'shuttle.dart';

DateTime? _dt(Object? v) => v == null ? null : DateTime.parse(v as String);

class Estate {
  const Estate({
    required this.id,
    required this.name,
    required this.timezone,
    required this.walkInPolicy,
    required this.keyVersion,
    this.visitorPhotos = VisitorPhotos.phoneEntries,
  });

  final String id;
  final String name;
  final String timezone;
  final String walkInPolicy;
  final int keyVersion;

  /// When the gate photographs the visitor after "Let them in": all | phone_entries | off.
  final String visitorPhotos;

  /// Whether an entry by [method] gets a visitor photo under the estate's rule.
  bool photoFor(String method) => switch (visitorPhotos) {
        VisitorPhotos.all => true,
        VisitorPhotos.off => false,
        _ => method != 'code',
      };

  factory Estate.fromJson(Map<String, dynamic> j) => Estate(
        id: j['id'] as String,
        name: j['name'] as String,
        timezone: (j['timezone'] as String?) ?? 'Africa/Lagos',
        walkInPolicy: (j['walk_in_policy'] as String?) ?? '',
        keyVersion: (j['key_version'] as num?)?.toInt() ?? 1,
        visitorPhotos: (j['visitor_photos'] as String?) ?? VisitorPhotos.phoneEntries,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'timezone': timezone, 'walk_in_policy': walkInPolicy, 'key_version': keyVersion, 'visitor_photos': visitorPhotos};
}

abstract final class VisitorPhotos {
  static const all = 'all';
  static const phoneEntries = 'phone_entries';
  static const off = 'off';
}

class Gate {
  const Gate(this.id, this.name);
  final String id;
  final String name;
}

/// Anyone who can open a shift on the gate phone: a guard or the CSO.
class Guard {
  const Guard(this.id, this.name, {this.role = 'guard', this.pinHash, this.pinResetAt, this.consent = true});
  final String id;
  final String name;

  /// guard | cso | rider. Decides which view the shift gets.
  final String role;

  /// `pbkdf2-sha256$...`, or null when no PIN is set (first shift, or the admin reset it).
  final String? pinHash;
  final DateTime? pinResetAt;

  /// False until the admin records the guard's consent form; such a guard cannot start a shift.
  final bool consent;

  bool get isCso => role == 'cso';
  bool get isRider => role == 'rider';

  /// Never print the PIN hash.
  @override
  String toString() => 'Guard($id, $name, $role)';

  factory Guard.fromJson(Map<String, dynamic> j) => Guard(
        j['id'] as String,
        j['name'] as String,
        role: (j['role'] as String?) ?? 'guard',
        pinHash: j['pin_hash'] as String?,
        pinResetAt: _dt(j['pin_reset_at']),
        consent: (j['consent'] as bool?) ?? false,
      );
}

/// "lnd 123-ab" -> "LND123AB", the way the server stores plates.
String normalisePlate(String raw) => raw.replaceAll(RegExp(r'[\s\-.]'), '').toUpperCase();

class Vehicle {
  const Vehicle({required this.plate, this.description});
  final String plate;
  final String? description;

  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(plate: j['plate'] as String, description: j['description'] as String?);
}

class PhoneNumber {
  const PhoneNumber({required this.id, required this.e164, required this.last4, required this.isPrimary});

  final String id;

  /// Full number. Only ever used to build the `tel:` URI for a callback.
  final String e164;
  final String last4;
  final bool isPrimary;

  String get masked => '•••• $last4';

  @override
  String toString() => 'PhoneNumber($id, $masked)';

  factory PhoneNumber.fromJson(Map<String, dynamic> j) => PhoneNumber(
        id: j['id'] as String,
        e164: j['e164'] as String,
        last4: (j['last4'] as String?) ?? _last4(j['e164'] as String),
        isPrimary: (j['is_primary'] as bool?) ?? false,
      );

  static String _last4(String n) => n.length <= 4 ? n : n.substring(n.length - 4);
}

class Resident {
  const Resident({required this.id, required this.homeId, required this.name, required this.contactPref, required this.numbers});

  final String id;
  final String homeId;
  final String name;
  final String contactPref;
  final List<PhoneNumber> numbers;

  /// Last word of the name, for search ("Mrs Adeyemi" -> "adeyemi").
  String get surname => name.trim().split(RegExp(r'\s+')).last.toLowerCase();

  factory Resident.fromJson(String homeId, Map<String, dynamic> j) => Resident(
        id: j['id'] as String,
        homeId: homeId,
        name: j['name'] as String,
        contactPref: (j['contact_pref'] as String?) ?? '',
        numbers: [for (final n in (j['numbers'] as List? ?? const [])) PhoneNumber.fromJson(n as Map<String, dynamic>)]
          ..sort((a, b) => (b.isPrimary ? 1 : 0) - (a.isPrimary ? 1 : 0)),
      );
}

class Home {
  const Home({
    required this.id,
    required this.label,
    required this.street,
    required this.zone,
    required this.address,
    required this.callbackRequired,
    required this.residents,
    this.vehicles = const [],
    this.houseCodeHash,
  });

  final String id;
  final String label;
  final String street;
  final String zone;
  final String address;
  final bool callbackRequired;
  final List<Resident> residents;
  final List<Vehicle> vehicles;

  /// The home's shuttle house code, hashed like a guard PIN. Null until the household asks for
  /// one (and always null when the estate runs no shuttle). Never the code itself.
  final String? houseCodeHash;

  /// The registered vehicle this typed plate belongs to, if any.
  Vehicle? vehicleFor(String? typed) {
    final p = typed == null ? '' : normalisePlate(typed);
    if (p.isEmpty) return null;
    for (final v in vehicles) {
      if (normalisePlate(v.plate) == p) return v;
    }
    return null;
  }

  /// "14B Adeniyi Close, Block C".
  String get displayAddress => address.trim().isNotEmpty ? address : '${label.toUpperCase()} $street, $zone';

  factory Home.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    return Home(
      id: id,
      label: (j['label'] as String?) ?? '',
      street: (j['street'] as String?) ?? '',
      zone: (j['zone'] as String?) ?? '',
      address: (j['address'] as String?) ?? '',
      callbackRequired: (j['callback_required'] as bool?) ?? false,
      residents: [for (final r in (j['residents'] as List? ?? const [])) Resident.fromJson(id, r as Map<String, dynamic>)],
      vehicles: [for (final v in (j['vehicles'] as List? ?? const [])) Vehicle.fromJson(v as Map<String, dynamic>)],
      houseCodeHash: j['house_code_hash'] as String?,
    );
  }
}

class Visit {
  const Visit({
    required this.id,
    required this.homeId,
    required this.residentId,
    required this.guestName,
    required this.windowStart,
    required this.windowEnd,
    required this.keyVersion,
    required this.codeIssued,
    required this.source,
    required this.state,
    required this.expectedUntil,
    required this.entryId,
    required this.enteredAt,
  });

  final String id;
  final String homeId;
  final String? residentId;
  final String guestName;

  /// Unix seconds.
  final int windowStart;
  final int windowEnd;
  final int? keyVersion;
  final bool codeIssued;
  final String source;

  /// expected | inside | overstay (from the server); `left` only exists locally.
  final String state;
  final DateTime? expectedUntil;
  final String? entryId;
  final DateTime? enteredAt;

  bool get isInside => state == 'inside' || state == 'overstay';

  Visit copyWith({String? state, String? entryId, DateTime? enteredAt}) => Visit(
        id: id,
        homeId: homeId,
        residentId: residentId,
        guestName: guestName,
        windowStart: windowStart,
        windowEnd: windowEnd,
        keyVersion: keyVersion,
        codeIssued: codeIssued,
        source: source,
        state: state ?? this.state,
        expectedUntil: expectedUntil,
        entryId: entryId ?? this.entryId,
        enteredAt: enteredAt ?? this.enteredAt,
      );

  factory Visit.fromJson(Map<String, dynamic> j) => Visit(
        id: (j['id'] as String).toLowerCase(),
        homeId: (j['home_id'] as String).toLowerCase(),
        residentId: j['resident_id'] as String?,
        guestName: j['guest_name'] as String,
        windowStart: (j['window_start'] as num).toInt(),
        windowEnd: (j['window_end'] as num).toInt(),
        keyVersion: (j['key_version'] as num?)?.toInt(),
        codeIssued: (j['code_issued'] as bool?) ?? false,
        source: (j['source'] as String?) ?? '',
        state: (j['state'] as String?) ?? 'expected',
        expectedUntil: _dt(j['expected_until']),
        entryId: j['entry_id'] as String?,
        enteredAt: _dt(j['entered_at']),
      );
}

class RollupItem {
  const RollupItem({
    required this.id,
    required this.visitId,
    required this.checkedAt,
    required this.checkResult,
    this.guestName,
    this.homeId,
    this.address,
  });
  final String id;
  final String visitId;
  final DateTime? checkedAt;
  final String? checkResult;
  // Sent with each item so the list reads right even if the visit is not in visits[].
  final String? guestName;
  final String? homeId;
  final String? address;

  factory RollupItem.fromJson(Map<String, dynamic> j) => RollupItem(
        id: j['id'] as String,
        visitId: (j['visit_id'] as String).toLowerCase(),
        checkedAt: _dt(j['checked_at']),
        checkResult: j['check_result'] as String?,
        guestName: j['guest_name'] as String?,
        homeId: j['home_id'] as String?,
        address: j['address'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'visit_id': visitId,
        'checked_at': checkedAt?.toIso8601String(),
        'check_result': checkResult,
        'guest_name': guestName,
        'home_id': homeId,
        'address': address,
      };
}

class Rollup {
  const Rollup({required this.id, required this.forDate, required this.items});
  final String id;
  final String forDate;
  final List<RollupItem> items;

  factory Rollup.fromJson(Map<String, dynamic> j) => Rollup(
        id: j['id'] as String,
        forDate: j['for_date'] as String,
        items: [for (final i in (j['items'] as List? ?? const [])) RollupItem.fromJson(i as Map<String, dynamic>)],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'for_date': forDate,
        'items': [for (final i in items) i.toJson()],
      };
}

class DirectoryEntry {
  const DirectoryEntry({
    required this.id,
    required this.category,
    required this.name,
    required this.number,
    required this.verifiedAt,
    required this.reportedNotWorking,
  });
  final String id;
  final String category;
  final String name;
  final String number;
  final DateTime? verifiedAt;
  final bool reportedNotWorking;

  factory DirectoryEntry.fromJson(Map<String, dynamic> j) => DirectoryEntry(
        id: j['id'] as String,
        category: (j['category'] as String?) ?? 'other',
        name: j['name'] as String,
        number: j['number'] as String,
        verifiedAt: _dt(j['verified_at']),
        reportedNotWorking: (j['reported_not_working'] as bool?) ?? false,
      );
}

/// An open shift somewhere in the estate (`on_duty[]` in `/state`). The name and role come from
/// `guards[]` by [guardId].
class DutyShift {
  const DutyShift({required this.guardId, this.gateId, this.since});
  final String guardId;
  final String? gateId;
  final DateTime? since;

  factory DutyShift.fromJson(Map<String, dynamic> j) =>
      DutyShift(guardId: j['guard_id'] as String, gateId: j['gate_id'] as String?, since: _dt(j['since']));

  Map<String, dynamic> toJson() => {'guard_id': guardId, 'gate_id': gateId, 'since': since?.toIso8601String()};

  /// `on_duty` as `/state` sends it. Absent or null (an older server): nobody listed.
  static List<DutyShift> listFromJson(Object? v) => [
        if (v is List)
          for (final o in v)
            if (o is Map<String, dynamic> && o['guard_id'] is String) DutyShift.fromJson(o),
      ];
}

/// Everything the gate needs to work offline, minus the HMAC keys (those live in secure storage).
class StateSnapshot {
  const StateSnapshot({
    required this.estate,
    required this.deviceId,
    required this.deviceGateId,
    required this.gates,
    required this.guards,
    required this.homes,
    required this.visits,
    required this.rollup,
    required this.directory,
    this.shuttle,
    this.onDuty = const [],
  });

  final Estate estate;
  final String deviceId;
  final String deviceGateId;
  final List<Gate> gates;
  final List<Guard> guards;
  final List<Home> homes;
  final List<Visit> visits;
  final Rollup? rollup;
  final List<DirectoryEntry> directory;

  /// The estate shuttle, or null when the estate runs none (then none of it shows).
  final ShuttleState? shuttle;

  /// Every open shift in the estate when the state was pulled (who is on shift, by guard id).
  final List<DutyShift> onDuty;

  String? gateName(String? id) => gates.where((g) => g.id == id).firstOrNull?.name;

  Home? home(String id) {
    for (final h in homes) {
      if (h.id == id) return h;
    }
    return null;
  }

  Guard? guard(String? id) {
    for (final g in guards) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Residents' numbers by resident id (the CSO calls a resident about an overdue guest).
  Resident? resident(String? id) {
    for (final h in homes) {
      for (final r in h.residents) {
        if (r.id == id) return r;
      }
    }
    return null;
  }

  factory StateSnapshot.fromJson(Map<String, dynamic> j) {
    final device = j['device'] as Map<String, dynamic>;
    return StateSnapshot(
      estate: Estate.fromJson(j['estate'] as Map<String, dynamic>),
      deviceId: device['id'] as String,
      deviceGateId: device['gate_id'] as String,
      gates: [for (final g in (j['gates'] as List? ?? const [])) Gate(g['id'] as String, g['name'] as String)],
      guards: [for (final g in (j['guards'] as List? ?? const [])) Guard.fromJson(g as Map<String, dynamic>)],
      homes: [for (final h in (j['homes'] as List? ?? const [])) Home.fromJson(h as Map<String, dynamic>)],
      visits: [for (final v in (j['visits'] as List? ?? const [])) Visit.fromJson(v as Map<String, dynamic>)],
      rollup: j['rollup'] == null ? null : Rollup.fromJson(j['rollup'] as Map<String, dynamic>),
      directory: [for (final d in (j['directory'] as List? ?? const [])) DirectoryEntry.fromJson(d as Map<String, dynamic>)],
      shuttle: j['shuttle'] == null ? null : ShuttleState.fromJson(j['shuttle'] as Map<String, dynamic>),
      onDuty: DutyShift.listFromJson(j['on_duty']),
    );
  }

  /// `keys[]` from the state payload: version -> raw key bytes.
  static Map<int, List<int>> keysFromJson(Map<String, dynamic> j) => {
        for (final k in (j['keys'] as List? ?? const []))
          (k['version'] as num).toInt(): base64.decode(k['key_b64'] as String),
      };
}
