import '../data/models.dart';
import 'codes.dart';

/// What a code typed at the gate means, decided with no network.
sealed class CodeCheck {
  const CodeCheck();
}

/// Nothing cached matches.
class NoMatch extends CodeCheck {
  const NoMatch();
}

/// An expected guest inside their entry window: Admit or Turn away.
class AdmitMatch extends CodeCheck {
  const AdmitMatch(this.visit);
  final Visit visit;
}

/// The code is right but the entry window is not now.
class NotValidNow extends CodeCheck {
  const NotValidNow(this.visit, {required this.early});
  final Visit visit;

  /// True if the window has not opened yet; false if it has closed.
  final bool early;
}

/// The guest is already inside: offer Confirm exit.
class ExitMatch extends CodeCheck {
  const ExitMatch(this.visit);
  final Visit visit;
}

/// The guest was already recorded as gone on this phone.
class AlreadyLeft extends CodeCheck {
  const AlreadyLeft(this.visit);
  final Visit visit;
}

/// Checks [code] against every cached coded visit.
///
/// The server keeps codes unique only among visits whose entry windows overlap, so a code can
/// match more than one cached visit (say, one inside from yesterday and one expected now).
/// Preference: an expected guest whose window is open, then a guest inside, then a window
/// that is not open, then one already marked as left. An inside guest matches whatever the
/// time: their entry window may have closed hours ago and they still need to get out.
CodeCheck checkCode(String code, Iterable<Visit> visits, Map<int, List<int>> keys, int nowUnix) {
  final clean = cleanCode(code);
  if (clean == null) return const NoMatch();
  AdmitMatch? admit;
  ExitMatch? exit;
  NotValidNow? notNow;
  AlreadyLeft? left;
  for (final v in visits) {
    if (!v.codeIssued || v.keyVersion == null) continue;
    final key = keys[v.keyVersion];
    if (key == null) continue;
    if (deriveCode(key, v.homeId, v.id, v.windowStart, v.windowEnd) != clean) continue;
    final inWindow = v.windowStart <= nowUnix && nowUnix <= v.windowEnd;
    if (v.isInside) {
      exit ??= ExitMatch(v);
    } else if (v.state == 'left') {
      left ??= AlreadyLeft(v);
    } else if (inWindow) {
      admit ??= AdmitMatch(v);
    } else {
      notNow ??= NotValidNow(v, early: nowUnix < v.windowStart);
    }
  }
  return admit ?? exit ?? notNow ?? left ?? const NoMatch();
}
