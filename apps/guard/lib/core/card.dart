/// Estate cards: an NFC tap card identifies a resident on the shuttle, offline.
///
///     uid_hash = sha256("gatelog-card-v1|<estate_id>|<UID hex, upper case, no separators>"), hex
///
/// The card's UID is not secret (any reader gets it), so the hash only keeps raw UIDs off the
/// phone's disk and out of the server, and ties a card to one estate. The raw UID is never
/// stored, shown or logged; only its last 4 hex digits are shown, as the server does.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

const cardPrefix = 'gatelog-card-v1';

/// "04:a2:1b 7c-55-80" -> "04A21B7C5580". Anything that is not a hex digit goes.
String normaliseUid(String uid) => uid.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();

/// Bytes read from the tag, as upper-case hex with no separators.
String uidHex(List<int> bytes) => [for (final b in bytes) (b & 0xff).toRadixString(16).padLeft(2, '0')].join().toUpperCase();

String cardHash(String estateId, String uid) => sha256.convert(utf8.encode('$cardPrefix|${estateId.toLowerCase()}|${normaliseUid(uid)}')).toString();

/// The last 4 hex digits, which the server keeps to tell cards apart in the dashboard.
String uidLast4(String uid) {
  final u = normaliseUid(uid);
  return u.length <= 4 ? u.padLeft(4, '0') : u.substring(u.length - 4);
}

/// A UID worth hashing: at least 4 bytes (8 hex digits), at most 10 bytes.
bool isPlausibleUid(String uid) {
  final n = normaliseUid(uid).length;
  return n >= 8 && n <= 20 && n.isEven;
}
