import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/core/pin.dart';

List<int> hex(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

/// PBKDF2 straight from package:crypto's HMAC, to cross-check the fast version.
List<int> slowPbkdf2(List<int> pw, List<int> salt, int iterations, int length) {
  final h = Hmac(sha256, pw);
  final out = <int>[];
  for (var b = 1; out.length < length; b++) {
    var u = h.convert([...salt, b >> 24 & 0xff, b >> 16 & 0xff, b >> 8 & 0xff, b & 0xff]).bytes;
    final t = List<int>.of(u);
    for (var i = 1; i < iterations; i++) {
      u = h.convert(u).bytes;
      for (var j = 0; j < 32; j++) {
        t[j] ^= u[j];
      }
    }
    out.addAll(t);
  }
  return out.sublist(0, length);
}

void main() {
  // flutter test runs from apps/guard; the vectors live at the repo root.
  final file = File('../../docs/pin-hash-vectors.json');
  final vectors = (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['vectors'] as List;

  test('the vector file is there and not empty', () => expect(vectors, isNotEmpty));

  for (final (i, raw) in vectors.indexed) {
    final v = raw as Map<String, dynamic>;
    test('vector $i: the phone makes the same hash and checks it', () {
      final made = makePinHash(v['pin'] as String, salt: hex(v['salt_hex'] as String), iterations: v['iterations'] as int);
      expect(made, v['pin_hash']);
      expect(checkPin(v['pin'] as String, v['pin_hash'] as String), isTrue);
      expect(checkPin('999999', v['pin_hash'] as String), isFalse);
    });
  }

  test('matches package:crypto for odd salts, long passwords and lengths over one block', () {
    for (final (pw, salt, len) in [
      ('1', <int>[], 32),
      ('123456', List<int>.generate(70, (i) => i * 3), 32),
      ('x' * 80, List<int>.generate(16, (i) => 255 - i), 50),
    ]) {
      expect(pbkdf2Sha256(utf8.encode(pw), salt, 50, len), slowPbkdf2(utf8.encode(pw), salt, 50, len));
    }
  });

  test('a fresh hash uses 60,000 iterations and a new 16-byte salt each time', () {
    final a = makePinHash('482913', iterations: 1000), b = makePinHash('482913', iterations: 1000);
    expect(a, isNot(b));
    expect(base64.decode(a.split(r'$')[2]), hasLength(16));
    expect(checkPin('482913', a), isTrue);
    expect(makePinHash('482913').split(r'$')[1], '60000');
  });

  test('malformed hashes never match', () {
    for (final bad in ['', '482913', r'pbkdf2-sha1$1000$AAAA$AAAA', r'pbkdf2-sha256$x$AAAA$AAAA', r'pbkdf2-sha256$1000$***$AAAA', r'pbkdf2-sha256$1000$AAAA$']) {
      expect(checkPin('482913', bad), isFalse, reason: bad);
    }
  });

  test('only six digits make a PIN', () {
    expect(isValidPin('482913'), isTrue);
    for (final bad in ['48291', '4829134', '48291a', ' 482913', '']) {
      expect(isValidPin(bad), isFalse, reason: bad);
    }
  });

  test('runs off the UI thread', () async {
    final sw = Stopwatch()..start();
    final h = await hashPinInBackground('482913');
    expect(await checkPinInBackground('482913', h), isTrue);
    expect(await checkPinInBackground('482914', h), isFalse);
    // ignore: avoid_print
    print('three 60k-iteration hashes in an isolate: ${sw.elapsedMilliseconds} ms');
  });
}
