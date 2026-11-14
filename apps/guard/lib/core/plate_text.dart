/// Picking the number plate out of what on-device text recognition read from a photo of a car.
///
/// Nigerian plates today read `ABC 123 DE` (three letters for the local government, three
/// digits, two letters); older ones `LND 123 AB` or `AB 123 CDE`. The camera also reads
/// "LAGOS", "Centre of Excellence", dealer stickers and so on, so a line is a plate only when it
/// mixes letters and digits in a plate's shape. The guard confirms it: "Is this the plate?"
library;

import '../data/models.dart';

final _modern = RegExp(r'^[A-Z]{3}\d{2,3}[A-Z]{2}$');
final _older = RegExp(r'^[A-Z]{2}\d{2,3}[A-Z]{3}$');

/// Letters and digits only, upper case, with the commonest misreads in each position fixed
/// when that makes a plate (O for 0 among the digits, 0 for O among the letters, and so on).
String _clean(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

const _toDigit = {'O': '0', 'Q': '0', 'D': '0', 'I': '1', 'L': '1', 'Z': '2', 'S': '5', 'B': '8', 'G': '6'};
const _toLetter = {'0': 'O', '1': 'I', '2': 'Z', '5': 'S', '8': 'B', '6': 'G'};

/// Tries the modern then the older shape, mending letters and digits read the wrong way round.
String? _asPlate(String s) {
  if (s.length < 7 || s.length > 8) return null;
  for (final shape in const [(3, 2), (2, 3)]) {
    final (lead, tail) = shape;
    final digits = s.length - lead - tail;
    if (digits < 2 || digits > 3) continue;
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      final wantDigit = i >= lead && i < lead + digits;
      final isDigit = RegExp(r'\d').hasMatch(ch);
      if (wantDigit == isDigit) {
        b.write(ch);
      } else {
        final fixed = wantDigit ? _toDigit[ch] : _toLetter[ch];
        if (fixed == null) {
          b.clear();
          break;
        }
        b.write(fixed);
      }
    }
    final out = b.toString();
    if (out.length == s.length && (_modern.hasMatch(out) || _older.hasMatch(out))) return out;
  }
  return null;
}

/// The plate in [lines] (what the recognizer read, line by line), or null. A line or two
/// neighbouring lines joined (plates often split over two) are tried. A home's registered
/// vehicle wins when one of them is there, even if the shape is unusual.
String? plateFromText(List<String> lines, {Iterable<Vehicle> known = const []}) {
  final cleaned = [for (final l in lines) _clean(l)].where((l) => l.isNotEmpty).toList();
  final candidates = <String>[
    ...cleaned,
    for (var i = 0; i + 1 < cleaned.length; i++) cleaned[i] + cleaned[i + 1],
    // A line can hold the plate and more ("LAGOS ABC123DE"): its words, and pairs of them.
    for (final l in lines)
      for (final w in l.toUpperCase().split(RegExp(r'[^A-Z0-9]+'))) w,
  ];
  for (final v in known) {
    final p = normalisePlate(v.plate);
    if (p.isNotEmpty && candidates.any((c) => c.contains(p))) return p;
  }
  for (final c in candidates) {
    final p = _asPlate(c);
    if (p != null) return p;
  }
  // Inside a longer run ("LAGOSABC123DE").
  for (final c in candidates) {
    for (final len in const [8, 7]) {
      for (var i = 0; i + len <= c.length; i++) {
        final p = _asPlate(c.substring(i, i + len));
        if (p != null && RegExp(r'\d').hasMatch(c.substring(i, i + len))) return p;
      }
    }
  }
  return null;
}

/// "ABC123DE" -> "ABC 123 DE", for the screen.
String spacePlate(String p) {
  final m = RegExp(r'^([A-Z]+)(\d+)([A-Z]+)$').firstMatch(p);
  return m == null ? p : '${m[1]} ${m[2]} ${m[3]}';
}
