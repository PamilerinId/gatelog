import '../core/pin.dart';

/// The shift open on this phone. Every record made during it carries [id] and [guardId].
class OpenShift {
  const OpenShift({required this.id, required this.guardId, required this.startedAt, required this.selfieTaken, this.shuttleId});
  final String id;
  final String guardId;
  final DateTime startedAt;
  final bool selfieTaken;

  /// A rider's shift: the motorcycle they are on (`shuttle.shuttles`).
  final String? shuttleId;

  /// The phone ends a shift by itself after this long (`end_reason: auto`).
  static const maxLength = Duration(hours: 14);

  DateTime get autoEndAt => startedAt.add(maxLength);

  Map<String, dynamic> toJson() => {
        'id': id,
        'guard_id': guardId,
        'started_at': startedAt.toUtc().toIso8601String(),
        'selfie_taken': selfieTaken,
        'shuttle_id': ?shuttleId,
      };

  factory OpenShift.fromJson(Map<String, dynamic> j) => OpenShift(
        id: j['id'] as String,
        guardId: j['guard_id'] as String,
        startedAt: DateTime.parse(j['started_at'] as String),
        selfieTaken: (j['selfie_taken'] as bool?) ?? false,
        shuttleId: j['shuttle_id'] as String?,
      );
}

/// What the shift start screen asks of the person who picked their name.
enum PinStep {
  /// No consent form recorded: cannot start.
  noConsent,

  /// No PIN yet (first shift, or the admin reset it): choose one, twice.
  setPin,

  /// Enter the PIN; checked on the phone against the hash.
  enterPin,

  /// Five wrong tries: wait.
  locked,
}

sealed class PinCheck {
  const PinCheck();
}

class PinOk extends PinCheck {
  const PinOk();
}

class PinWrong extends PinCheck {
  const PinWrong(this.triesLeft);
  final int triesLeft;
}

class PinLocked extends PinCheck {
  const PinLocked(this.until);
  final DateTime until;
}

/// A house code checked on the rider's phone.
sealed class HouseCodeCheck {
  const HouseCodeCheck();
}

class HouseCodeOk extends HouseCodeCheck {
  const HouseCodeOk();
}

class HouseCodeWrong extends HouseCodeCheck {
  const HouseCodeWrong(this.triesLeft);
  final int triesLeft;
}

class HouseCodeLocked extends HouseCodeCheck {
  const HouseCodeLocked(this.until);
  final DateTime until;
}

/// The household has not asked for a code yet.
class HouseCodeNone extends HouseCodeCheck {
  const HouseCodeNone();
}

/// Wrong PIN tries per person on this phone. Five in a row lock that person out for five
/// minutes; a right PIN clears the count. Kept in the encrypted database.
class PinTries {
  PinTries([Map<String, dynamic>? json]) {
    for (final e in (json ?? const {}).entries) {
      final v = e.value as Map<String, dynamic>;
      _fails[e.key] = (v['fails'] as num?)?.toInt() ?? 0;
      final until = v['locked_until'] as String?;
      if (until != null) _lockedUntil[e.key] = DateTime.parse(until);
    }
  }

  final Map<String, int> _fails = {};
  final Map<String, DateTime> _lockedUntil = {};

  DateTime? lockedUntil(String guardId, DateTime now) {
    final until = _lockedUntil[guardId];
    return until != null && until.isAfter(now) ? until : null;
  }

  /// Records a wrong try. Returns the lock end when this try locks the person out.
  DateTime? fail(String guardId, DateTime now) {
    if (_lockedUntil[guardId] != null && !_lockedUntil[guardId]!.isAfter(now)) _lockedUntil.remove(guardId);
    final n = (_fails[guardId] ?? 0) + 1;
    if (n >= pinMaxTries) {
      _fails.remove(guardId);
      return _lockedUntil[guardId] = now.add(pinLockout);
    }
    _fails[guardId] = n;
    return null;
  }

  int triesLeft(String guardId) => pinMaxTries - (_fails[guardId] ?? 0);

  void clear(String guardId) {
    _fails.remove(guardId);
    _lockedUntil.remove(guardId);
  }

  Map<String, dynamic> toJson() => {
        for (final id in {..._fails.keys, ..._lockedUntil.keys})
          id: {'fails': _fails[id] ?? 0, 'locked_until': _lockedUntil[id]?.toUtc().toIso8601String()},
      };
}

/// What the end-of-shift record tells the next person and the CSO.
class Handover {
  const Handover({required this.inside, required this.unsynced, required this.nightListOpen});
  final int inside;
  final int unsynced;
  final int nightListOpen;

  Map<String, dynamic> toJson() => {'inside': inside, 'unsynced': unsynced, 'night_list_open': nightListOpen};
}
