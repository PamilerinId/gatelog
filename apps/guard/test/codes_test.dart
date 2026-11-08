import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/core/codes.dart';

List<int> hex(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

void main() {
  // flutter test runs from apps/guard; the vectors live at the repo root.
  final file = File('../../docs/code-test-vectors.json');
  final vectors = (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['vectors'] as List;

  test('the vector file is there and not empty', () {
    expect(vectors, isNotEmpty);
  });

  for (final (i, raw) in vectors.indexed) {
    final v = raw as Map<String, dynamic>;
    test('vector $i: message and code match the server', () {
      final ws = v['window_start'] as int, we = v['window_end'] as int;
      expect(codeMessage(v['home_id'] as String, v['visit_id'] as String, ws, we), v['message']);
      expect(deriveCode(hex(v['key_hex'] as String), v['home_id'] as String, v['visit_id'] as String, ws, we), v['code']);
    });
  }

  test('UUIDs are lowercased before signing', () {
    final v = vectors.first as Map<String, dynamic>;
    final upper = deriveCode(hex(v['key_hex'] as String), (v['home_id'] as String).toUpperCase(), (v['visit_id'] as String).toUpperCase(),
        v['window_start'] as int, v['window_end'] as int);
    expect(upper, v['code']);
  });

  test('cleanCode and displayCode', () {
    expect(cleanCode('482 917'), '482917');
    expect(cleanCode('48291'), isNull);
    expect(cleanCode('4829170'), isNull);
    expect(displayCode('482917'), '482 917');
  });
}
