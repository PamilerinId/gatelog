/// Six-digit gate codes, signed per visit. Mirror of `apps/api/app/codes.py`.
///
///     code = truncate(HMAC-SHA256(key, "gatelog-code-v1|<home_id>|<visit_id>|<start>|<end>"))
///
/// home_id and visit_id are lowercase hyphenated UUIDs; start and end are Unix seconds.
/// Truncation is RFC 4226 dynamic truncation, mod 10^6, zero-padded to 6 digits.
/// `docs/code-test-vectors.json` pins the output; change this and the server together.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

const codePrefix = 'gatelog-code-v1';
const codeDigits = 6;

String codeMessage(String homeId, String visitId, int windowStart, int windowEnd) =>
    '$codePrefix|${homeId.toLowerCase()}|${visitId.toLowerCase()}|$windowStart|$windowEnd';

String deriveCode(List<int> key, String homeId, String visitId, int windowStart, int windowEnd) {
  final mac = Hmac(sha256, key).convert(utf8.encode(codeMessage(homeId, visitId, windowStart, windowEnd))).bytes;
  final offset = mac[mac.length - 1] & 0x0f;
  final value = ((mac[offset] << 24) | (mac[offset + 1] << 16) | (mac[offset + 2] << 8) | mac[offset + 3]) & 0x7fffffff;
  return (value % 1000000).toString().padLeft(codeDigits, '0');
}

/// Keeps the digits; returns null unless there are exactly six.
String? cleanCode(String entered) {
  final digits = entered.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length == codeDigits ? digits : null;
}

/// '482917' -> '482 917', the way residents read it out.
String displayCode(String code) => code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
