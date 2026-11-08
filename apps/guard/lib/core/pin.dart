/// Shift PINs: PBKDF2-HMAC-SHA256, checked on the phone with no network.
///
///     pin_hash = "pbkdf2-sha256$<iterations>$<salt b64>$<hash b64>"
///
/// 16 random bytes of salt, 60,000 iterations, 32 bytes of output. The server only checks the
/// format; the phone makes and checks hashes. `docs/pin-hash-vectors.json` pins the output.
///
/// The PIN and the hash are never logged. Hashing takes a noticeable time on a cheap phone,
/// so the UI calls [hashPinInBackground] and [checkPinInBackground], which run in an isolate.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

const pinIterations = 60000;
const pinLength = 6;
const pinMaxTries = 5;

/// A home PIN (the shuttle's and the gate's): 3 wrong tries on one home, then the rider asks
/// them to call the gate (and offers the card, or vouches).
const homePinMaxTries = 3;
const pinLockout = Duration(minutes: 5);

/// Six digits, nothing else.
bool isValidPin(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);

String makePinHash(String pin, {List<int>? salt, int iterations = pinIterations}) {
  final s = salt ?? _randomSalt();
  final dk = pbkdf2Sha256(utf8.encode(pin), s, iterations, 32);
  return 'pbkdf2-sha256\$$iterations\$${base64.encode(s)}\$${base64.encode(dk)}';
}

/// True if [pin] matches [pinHash]. A malformed hash never matches.
bool checkPin(String pin, String pinHash) {
  final parts = pinHash.split(r'$');
  if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1 || iterations > 10000000) return false;
  final List<int> salt, expected;
  try {
    salt = base64.decode(parts[2]);
    expected = base64.decode(parts[3]);
  } on FormatException {
    return false;
  }
  if (expected.isEmpty) return false;
  final got = pbkdf2Sha256(utf8.encode(pin), salt, iterations, expected.length);
  var diff = 0;
  for (var i = 0; i < got.length; i++) {
    diff |= got[i] ^ expected[i];
  }
  return diff == 0;
}

Future<String> hashPinInBackground(String pin) => compute(_hashEntry, pin);

Future<bool> checkPinInBackground(String pin, String pinHash) => compute(_checkEntry, [pin, pinHash]);

String _hashEntry(String pin) => makePinHash(pin);
bool _checkEntry(List<String> a) => checkPin(a[0], a[1]);

List<int> _randomSalt() {
  final r = Random.secure();
  return List<int>.generate(16, (_) => r.nextInt(256));
}

// --- PBKDF2-HMAC-SHA256 ---------------------------------------------------------------------
//
// Written out rather than built on package:crypto's Hmac, which allocates per call and costs
// four SHA-256 compressions per iteration. Here the HMAC inner and outer pad states are
// computed once, so each iteration is two compressions on fixed buffers. About 8 times faster,
// which matters at 60,000 iterations on a cheap phone.

Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations, int length) {
  var key = password;
  if (key.length > 64) key = _sha256(key);
  final ipad = Uint8List(64), opad = Uint8List(64);
  for (var i = 0; i < 64; i++) {
    final k = i < key.length ? key[i] : 0;
    ipad[i] = k ^ 0x36;
    opad[i] = k ^ 0x5c;
  }
  final innerInit = Uint32List.fromList(_h0);
  _compress(innerInit, _words(ipad));
  final outerInit = Uint32List.fromList(_h0);
  _compress(outerInit, _words(opad));

  final out = Uint8List(length);
  final blocks = (length + 31) ~/ 32;
  final state = Uint32List(8);
  // One 64-byte block holding a 32-byte digest, padded for a 96-byte message (pad + digest).
  final block = Uint32List(16);
  final acc = Uint32List(8);
  for (var b = 1; b <= blocks; b++) {
    // U1 = HMAC(P, salt || INT(b))
    final msg = [...salt, (b >> 24) & 0xff, (b >> 16) & 0xff, (b >> 8) & 0xff, b & 0xff];
    final u = Uint32List(8);
    _hmacLong(innerInit, outerInit, msg, u);
    acc.setAll(0, u);
    for (var i = 1; i < iterations; i++) {
      // inner: H(ipad || u)
      for (var j = 0; j < 8; j++) {
        block[j] = u[j];
      }
      block[8] = 0x80000000;
      for (var j = 9; j < 15; j++) {
        block[j] = 0;
      }
      block[15] = (64 + 32) * 8;
      state.setAll(0, innerInit);
      _compress(state, block);
      // outer: H(opad || inner)
      for (var j = 0; j < 8; j++) {
        block[j] = state[j];
      }
      block[8] = 0x80000000;
      for (var j = 9; j < 15; j++) {
        block[j] = 0;
      }
      block[15] = (64 + 32) * 8;
      u.setAll(0, outerInit);
      _compress(u, block);
      for (var j = 0; j < 8; j++) {
        acc[j] ^= u[j];
      }
    }
    for (var j = 0; j < 8; j++) {
      final o = (b - 1) * 32 + j * 4;
      for (var k = 0; k < 4; k++) {
        if (o + k < length) out[o + k] = (acc[j] >> (24 - 8 * k)) & 0xff;
      }
    }
  }
  return out;
}

/// HMAC of an arbitrary-length message, from the precomputed pad states, into [out].
void _hmacLong(Uint32List innerInit, Uint32List outerInit, List<int> msg, Uint32List out) {
  final inner = Uint32List.fromList(innerInit);
  _absorb(inner, msg, 64);
  final digest = Uint8List(32);
  _store(inner, digest);
  out.setAll(0, outerInit);
  _absorb(out, digest, 64);
}

/// SHA-256 of [data] continuing from [state], which has already absorbed [prefixLen] bytes.
void _absorb(Uint32List state, List<int> data, int prefixLen) {
  final total = prefixLen + data.length;
  final padded = Uint8List(((data.length + 9 + 63) ~/ 64) * 64)..setAll(0, data);
  padded[data.length] = 0x80;
  final bits = total * 8;
  final n = padded.length;
  // Message length in bits, big-endian, in the last 8 bytes.
  for (var i = 0; i < 8; i++) {
    padded[n - 1 - i] = (bits >> (8 * i)) & 0xff;
  }
  for (var o = 0; o < n; o += 64) {
    _compress(state, _words(Uint8List.sublistView(padded, o, o + 64)));
  }
}

Uint8List _sha256(List<int> data) {
  final s = Uint32List.fromList(_h0);
  _absorb(s, data, 0);
  final out = Uint8List(32);
  _store(s, out);
  return out;
}

void _store(Uint32List s, Uint8List out) {
  for (var j = 0; j < 8; j++) {
    out[j * 4] = s[j] >> 24;
    out[j * 4 + 1] = (s[j] >> 16) & 0xff;
    out[j * 4 + 2] = (s[j] >> 8) & 0xff;
    out[j * 4 + 3] = s[j] & 0xff;
  }
}

Uint32List _words(Uint8List block) {
  final w = Uint32List(16);
  for (var i = 0; i < 16; i++) {
    w[i] = (block[i * 4] << 24) | (block[i * 4 + 1] << 16) | (block[i * 4 + 2] << 8) | block[i * 4 + 3];
  }
  return w;
}

final _w = Uint32List(64);

void _compress(Uint32List h, Uint32List block) {
  final w = _w;
  for (var i = 0; i < 16; i++) {
    w[i] = block[i];
  }
  for (var i = 16; i < 64; i++) {
    final x = w[i - 15], y = w[i - 2];
    final s0 = _rotr(x, 7) ^ _rotr(x, 18) ^ (x >> 3);
    final s1 = _rotr(y, 17) ^ _rotr(y, 19) ^ (y >> 10);
    w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
  }
  var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
  for (var i = 0; i < 64; i++) {
    final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
    final ch = (e & f) ^ ((~e & 0xffffffff) & g);
    final t1 = (hh + s1 + ch + _k[i] + w[i]) & 0xffffffff;
    final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
    final maj = (a & b) ^ (a & c) ^ (b & c);
    final t2 = (s0 + maj) & 0xffffffff;
    hh = g;
    g = f;
    f = e;
    e = (d + t1) & 0xffffffff;
    d = c;
    c = b;
    b = a;
    a = (t1 + t2) & 0xffffffff;
  }
  h[0] = (h[0] + a) & 0xffffffff;
  h[1] = (h[1] + b) & 0xffffffff;
  h[2] = (h[2] + c) & 0xffffffff;
  h[3] = (h[3] + d) & 0xffffffff;
  h[4] = (h[4] + e) & 0xffffffff;
  h[5] = (h[5] + f) & 0xffffffff;
  h[6] = (h[6] + g) & 0xffffffff;
  h[7] = (h[7] + hh) & 0xffffffff;
}

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

const _h0 = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];

final _k = Uint32List.fromList(const [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);
