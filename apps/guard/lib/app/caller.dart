/// Caller ID at the gate: the last incoming call, as Android's call screening saw it.
///
/// An inbound caller ID is a hint, never proof (spec, "Call-the-gate verification"). The phone
/// uses it for three things only: to offer the home whose resident rang ("Is it Mrs Adeyemi,
/// 14B?"), to send `caller_masked` on the records of that call, and for a number offer after
/// the callback confirmed it. The full number stays in memory; it is never stored, shown,
/// spoken or logged.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';

/// How long the last incoming call counts as "the call about this visitor".
const callerHintFor = Duration(minutes: 10);

class IncomingCall {
  const IncomingCall(this.number, this.at);

  /// As the network gave it (`08031234567`, `+2348031234567`). Never print it.
  final String number;
  final DateTime at;

  String? get masked => maskCaller(number);

  @override
  String toString() => 'IncomingCall(${masked ?? 'hidden'}, $at)';
}

/// "+234 803 123 4567" -> "+2348031234567". Nigerian numbers only get the country code; other
/// forms are kept as digits with their plus. Null when there are too few digits to be a number.
String? toE164(String raw) {
  final plus = raw.trim().startsWith('+');
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length < 7) return null;
  if (!plus && d.startsWith('00')) return '+${d.substring(2)}';
  if (!plus && d.startsWith('0') && d.length == 11) return '+234${d.substring(1)}';
  if (!plus && d.startsWith('234') && d.length == 13) return '+$d';
  return plus ? '+$d' : d;
}

/// The caller as the contract allows it on a record: at most the first 4 and the last 4
/// digits (`0803•••1234`). Nigerian numbers are shown the local way (0803...), as residents
/// know them. Null when the number is too short to mask.
String? maskCaller(String raw) {
  final e = toE164(raw);
  if (e == null) return null;
  final local = e.startsWith('+234') && e.length == 14 ? '0${e.substring(4)}' : e;
  final plus = local.startsWith('+');
  final digits = local.replaceAll('+', '');
  if (digits.length < 8) return '•••${digits.substring(digits.length - 4)}';
  return '${plus ? '+' : ''}${digits.substring(0, 4)}•••${digits.substring(digits.length - 4)}';
}

/// The resident of a home whose registered number is [raw], if any.
(Home, Resident)? whoCalled(String raw, Iterable<Home> homes) {
  final e = toE164(raw);
  if (e == null) return null;
  for (final h in homes) {
    for (final r in h.residents) {
      for (final n in r.numbers) {
        if (toE164(n.e164) == e) return (h, r);
      }
    }
  }
  return null;
}

/// True when [raw] is one of [home]'s registered numbers.
bool isRegisteredTo(String raw, Home home) {
  final e = toE164(raw);
  return e != null && home.residents.any((r) => r.numbers.any((n) => toE164(n.e164) == e));
}

/// The phone's caller ID. Replaced in tests.
abstract class CallerId {
  /// The last incoming call the screening service saw, if any (in memory only).
  Future<IncomingCall?> lastIncoming();

  /// Asks Android to make this app the call-screening app (`RoleManager.ROLE_CALL_SCREENING`).
  /// True if the app holds the role afterwards. Refused or unavailable: false, and nothing else
  /// changes; every flow works without it.
  Future<bool> requestRole();

  Future<bool> hasRole();
}

class NoCallerId implements CallerId {
  const NoCallerId();
  @override
  Future<IncomingCall?> lastIncoming() async => null;
  @override
  Future<bool> requestRole() async => false;
  @override
  Future<bool> hasRole() async => false;
}

/// `GateCallScreeningService` in the Android app notes each incoming call's number and time in
/// memory and never blocks or changes a call; this reads it over a method channel.
class AndroidCallerId implements CallerId {
  const AndroidCallerId();
  static const _ch = MethodChannel('ng.gatelog/caller');

  @override
  Future<IncomingCall?> lastIncoming() async {
    try {
      final m = await _ch.invokeMapMethod<String, Object?>('lastIncoming');
      final n = m?['number'] as String?;
      final at = m?['at'] as int?;
      if (n == null || at == null) return null;
      return IncomingCall(n, DateTime.fromMillisecondsSinceEpoch(at));
    } catch (e) {
      debugPrint('caller id unavailable: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Future<bool> requestRole() async {
    try {
      return await _ch.invokeMethod<bool>('requestRole') ?? false;
    } catch (e) {
      debugPrint('call screening role request failed: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<bool> hasRole() async {
    try {
      return await _ch.invokeMethod<bool>('hasRole') ?? false;
    } catch (_) {
      return false;
    }
  }
}
