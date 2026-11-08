import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/core/codes.dart';
import 'package:gatelog_guard/core/verify.dart';
import 'package:gatelog_guard/data/models.dart';

final k1 = List<int>.generate(32, (i) => i);
final k2 = List<int>.generate(32, (i) => 255 - i);
const home = '3f2b8a51-0c4e-4d1a-9a8e-5b7c1d2e3f40';
const start = 1792540800; // window: 8 hours
const end = start + 8 * 3600;

Visit visit(String id, {int keyVersion = 1, String state = 'expected', bool coded = true, int ws = start, int we = end}) => Visit(
      id: id,
      homeId: home,
      residentId: null,
      guestName: 'Tunde',
      windowStart: ws,
      windowEnd: we,
      keyVersion: coded ? keyVersion : null,
      codeIssued: coded,
      source: 'whatsapp',
      state: state,
      expectedUntil: null,
      entryId: state == 'inside' ? 'e1' : null,
      enteredAt: null,
    );

String codeOf(Visit v, List<int> key) => deriveCode(key, v.homeId, v.id, v.windowStart, v.windowEnd);

void main() {
  final keys = {1: k1, 2: k2};
  const id = '9d0e7c6b-5a49-4382-a716-2f5e4d3c2b1a';

  test('a code inside its window matches for admission', () {
    final v = visit(id);
    final r = checkCode(codeOf(v, k1), [v], keys, start + 60);
    expect(r, isA<AdmitMatch>());
    expect((r as AdmitMatch).visit.id, id);
  });

  test('window edges are inclusive', () {
    final v = visit(id);
    expect(checkCode(codeOf(v, k1), [v], keys, start), isA<AdmitMatch>());
    expect(checkCode(codeOf(v, k1), [v], keys, end), isA<AdmitMatch>());
  });

  test('before the window: not valid now, early', () {
    final v = visit(id);
    final r = checkCode(codeOf(v, k1), [v], keys, start - 1);
    expect(r, isA<NotValidNow>());
    expect((r as NotValidNow).early, isTrue);
  });

  test('after the window: not valid now, late', () {
    final v = visit(id);
    final r = checkCode(codeOf(v, k1), [v], keys, end + 1);
    expect(r, isA<NotValidNow>());
    expect((r as NotValidNow).early, isFalse);
  });

  test('a wrong code does not match', () {
    final v = visit(id);
    final good = codeOf(v, k1);
    final wrong = ((int.parse(good) + 1) % 1000000).toString().padLeft(6, '0');
    expect(checkCode(wrong, [v], keys, start + 60), isA<NoMatch>());
    expect(checkCode('12345', [v], keys, start + 60), isA<NoMatch>());
  });

  test('each visit is checked with its own key version', () {
    final v = visit(id, keyVersion: 2);
    expect(checkCode(codeOf(v, k2), [v], keys, start + 60), isA<AdmitMatch>());
    // Signed with the other key: no match.
    expect(checkCode(codeOf(v, k1), [v], keys, start + 60), isA<NoMatch>());
  });

  test('a visit whose key is missing cannot match', () {
    final v = visit(id, keyVersion: 3);
    final k3 = List<int>.filled(32, 7);
    expect(checkCode(codeOf(v, k3), [v], keys, start + 60), isA<NoMatch>());
    expect(checkCode(codeOf(v, k3), [v], {...keys, 3: k3}, start + 60), isA<AdmitMatch>());
  });

  test('visits without a code are never matched', () {
    final v = visit(id, coded: false);
    expect(checkCode(codeOf(visit(id), k1), [v], keys, start + 60), isA<NoMatch>());
  });

  test('a guest inside matches for exit, even after the window', () {
    final v = visit(id, state: 'inside');
    expect(checkCode(codeOf(v, k1), [v], keys, start + 60), isA<ExitMatch>());
    expect(checkCode(codeOf(v, k1), [v], keys, end + 86400), isA<ExitMatch>());
  });

  test('a guest marked as left here says so', () {
    final v = visit(id, state: 'left');
    expect(checkCode(codeOf(v, k1), [v], keys, start + 60), isA<AlreadyLeft>());
  });
}
