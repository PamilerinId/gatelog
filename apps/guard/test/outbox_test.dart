import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/data/store.dart';
import 'package:gatelog_guard/sync/api.dart';
import 'package:gatelog_guard/sync/outbox.dart';

import 'support.dart';

Map<String, dynamic> entry(String id, {String? visitId, String method = 'code'}) =>
    {'id': id, 'home_id': 'h1', 'guest_name': 'Tunde', 'method': method, 'visit_id': visitId, 'guard_id': 'gu1', 'gate_id': 'g1', 'at': '2026-10-21T10:00:00Z'};

Map<String, dynamic> exit(String id, {String? entryId}) =>
    {'id': id, 'method': 'list_tap', 'entry_id': entryId, 'visit_id': null, 'guest_name': 'Tunde', 'guard_id': 'gu1', 'gate_id': 'g1', 'at': '2026-10-21T11:00:00Z'};

void main() {
  late GateStore store;
  late FakeApi api;
  late OutboxPusher pusher;
  final t0 = DateTime.utc(2026, 10, 21, 10);

  setUp(() {
    store = memoryStore();
    api = FakeApi();
    pusher = OutboxPusher(store, api, clock: () => t0);
  });

  tearDown(() => store.db.close());

  Future<Map<String, String>> statuses() async => {for (final i in await store.outbox()) i.id: i.status};

  test('accepted and duplicates leave the queue', () async {
    await store.enqueue(OutboxKind.entry, 'a', entry('a'));
    await store.enqueue(OutboxKind.entry, 'b', entry('b'));
    api.onSync = (_) => const SyncResult(accepted: ['a'], duplicates: ['b'], rejected: {});

    final r = await pusher.push('t');

    expect(r.sent, 2);
    expect(r.interrupted, isFalse);
    expect(await store.outbox(status: OutboxStatus.pending), isEmpty);
    expect(await statuses(), {'a': OutboxStatus.sent, 'b': OutboxStatus.sent});
    // Never pushed twice.
    await pusher.push('t');
    expect(api.syncBodies, hasLength(1));
  });

  test('the server answers IDs in any case', () async {
    await store.enqueue(OutboxKind.entry, 'abc-def', entry('abc-def'));
    api.onSync = (_) => const SyncResult(accepted: ['ABC-DEF'], duplicates: [], rejected: {});
    await pusher.push('t');
    expect(await statuses(), {'abc-def': OutboxStatus.sent});
  });

  test('rejected items are parked with their reason, the rest go through', () async {
    await store.enqueue(OutboxKind.entry, 'good', entry('good'));
    await store.enqueue(OutboxKind.entry, 'bad', entry('bad'));
    api.onSync = (_) => const SyncResult(accepted: ['good'], duplicates: [], rejected: {'bad': 'unknown home, guard or gate'});

    final r = await pusher.push('t');

    expect(r.rejected, 1);
    final bad = (await store.outbox()).firstWhere((i) => i.id == 'bad');
    expect(bad.status, OutboxStatus.rejected);
    expect(bad.reason, 'unknown home, guard or gate');
    // Not retried.
    await pusher.push('t');
    expect(api.syncBodies, hasLength(1));
  });

  test('a network failure keeps everything pending to retry', () async {
    await store.enqueue(OutboxKind.entry, 'a', entry('a'));
    await store.enqueue(OutboxKind.exit, 'x', exit('x', entryId: 'a'));
    api.syncError = NetworkException('No connection.');

    final r = await pusher.push('t');

    expect(r.interrupted, isTrue);
    final items = await store.outbox();
    expect(items.every((i) => i.isPending), isTrue);
    expect(items.every((i) => i.attempts == 1), isTrue);

    api.syncError = null;
    final r2 = await pusher.push('t');
    expect(r2.sent, 2);
    expect(await store.outbox(status: OutboxStatus.pending), isEmpty);
  });

  test('items the server did not mention stay pending', () async {
    await store.enqueue(OutboxKind.entry, 'a', entry('a'));
    await store.enqueue(OutboxKind.entry, 'b', entry('b'));
    api.onSync = (_) => const SyncResult(accepted: ['a'], duplicates: [], rejected: {});
    await pusher.push('t');
    expect(await statuses(), {'a': OutboxStatus.sent, 'b': OutboxStatus.pending});
  });

  test('a batch refused as a whole is split so one bad record cannot block the queue', () async {
    for (final id in ['a', 'b', 'c']) {
      await store.enqueue(OutboxKind.entry, id, entry(id));
    }
    api.onSync = (body) {
      final ids = FakeApi.idsIn(body);
      if (ids.contains('b')) throw ApiException(422, 'guest_name too long');
      return SyncResult(accepted: ids, duplicates: const [], rejected: const {});
    };

    await pusher.push('t');

    expect(await statuses(), {'a': OutboxStatus.sent, 'b': OutboxStatus.rejected, 'c': OutboxStatus.sent});
  });

  test('the sync body groups records by kind; rollup checks are keyed by item id', () async {
    await store.enqueue(OutboxKind.rollupCheck, 'item1', {'item_id': 'item1', 'result': 'left', 'guard_id': 'gu1', 'at': 'x'});
    await store.enqueue(OutboxKind.exit, 'x', exit('x'));
    api.onSync = (_) => const SyncResult(accepted: ['item1', 'x'], duplicates: [], rejected: {});
    await pusher.push('t');
    final body = api.syncBodies.single;
    expect((body['rollup_checks'] as List).single['item_id'], 'item1');
    expect((body['exits'] as List).single['id'], 'x');
    expect(body['entries'], isEmpty);
    expect(await statuses(), {'item1': OutboxStatus.sent, 'x': OutboxStatus.sent});
  });

  test('pins and shifts go first in the body; pins are answered by guard id', () async {
    await store.enqueue(OutboxKind.entry, 'a', entry('a'));
    await store.enqueue(OutboxKind.pin, 'pin:gu1:x', {'guard_id': 'gu1', 'pin_hash': 'h', 'set_at': 'x'});
    await store.enqueue(OutboxKind.shift, 's1', {'id': 's1', 'guard_id': 'gu1', 'started_at': 'x', 'selfie_taken': true});
    api.onSync = (_) => const SyncResult(accepted: ['gu1', 's1', 'a'], duplicates: [], rejected: {});
    await pusher.push('t');
    expect(api.syncBodies.single.keys.take(2), ['pins', 'shifts']);
    expect(await statuses(), {'a': OutboxStatus.sent, 'pin:gu1:x': OutboxStatus.sent, 's1': OutboxStatus.sent});
  });

  test("a shift's end shares the shift's id; one answer settles both, a rejection parks both", () async {
    await store.enqueue(OutboxKind.shift, 's1', {'id': 's1', 'guard_id': 'gu1', 'started_at': 'x', 'selfie_taken': false});
    await store.enqueue(OutboxKind.shift, 's1:end', {'id': 's1', 'guard_id': 'gu1', 'started_at': 'x', 'selfie_taken': false, 'ended_at': 'y'});
    api.onSync = (_) => const SyncResult(accepted: ['s1'], duplicates: ['s1'], rejected: {});
    await pusher.push('t');
    expect(await statuses(), {'s1': OutboxStatus.sent, 's1:end': OutboxStatus.sent});

    await store.enqueue(OutboxKind.shift, 's2', {'id': 's2', 'guard_id': 'gone', 'started_at': 'x', 'selfie_taken': false});
    await store.enqueue(OutboxKind.shift, 's2:end', {'id': 's2', 'guard_id': 'gone', 'started_at': 'x', 'selfie_taken': false, 'ended_at': 'y'});
    api.onSync = (_) => const SyncResult(accepted: [], duplicates: [], rejected: {'s2': 'unknown guard'});
    await pusher.push('t');
    expect((await statuses())['s2'], OutboxStatus.rejected);
    expect((await statuses())['s2:end'], OutboxStatus.rejected);
  });

  test('directory reports go to their own endpoint; a 404 is parked', () async {
    await store.enqueue(OutboxKind.directoryReport, 'r1', {'entry_id': 'dir1', 'guard_id': 'gu1'});
    await pusher.push('t');
    expect(api.reports, ['dir1']);
    expect(api.syncBodies, isEmpty);
    expect(await statuses(), {'r1': OutboxStatus.sent});

    await store.enqueue(OutboxKind.directoryReport, 'r2', {'entry_id': 'gone', 'guard_id': 'gu1'});
    api.reportError = ApiException(404, 'no such number');
    await pusher.push('t');
    expect((await statuses())['r2'], OutboxStatus.rejected);
  });

  test('401 propagates so the app can wipe and re-pair', () async {
    await store.enqueue(OutboxKind.entry, 'a', entry('a'));
    api.syncError = UnauthorizedException();
    expect(() => pusher.push('t'), throwsA(isA<UnauthorizedException>()));
  });

  test('enqueue ignores a second item with the same id', () async {
    expect(await store.enqueue(OutboxKind.rollupCheck, 'item1', {'item_id': 'item1', 'result': 'left'}), isTrue);
    expect(await store.enqueue(OutboxKind.rollupCheck, 'item1', {'item_id': 'item1', 'result': 'still_inside'}), isFalse);
    expect((await store.outbox()).single.payload['result'], 'left');
  });

  group('selectPurgeable', () {
    OutboxItem item(String id, String kind, Map<String, dynamic> p, {String status = OutboxStatus.sent, DateTime? sentAt, DateTime? created}) =>
        OutboxItem(id: id, kind: kind, payload: p, createdAt: created ?? t0, status: status, sentAt: status == OutboxStatus.sent ? (sentAt ?? t0) : null);

    final pull = t0.add(const Duration(seconds: 5));

    test('acknowledged before the pull: purged; after the pull or pending: kept', () {
      final items = [
        item('a', OutboxKind.entry, entry('a', visitId: 'v1')),
        item('b', OutboxKind.entry, entry('b', visitId: 'v2'), sentAt: pull.add(const Duration(seconds: 1))),
        item('c', OutboxKind.entry, entry('c', visitId: 'v3'), status: OutboxStatus.pending),
        item('d', OutboxKind.entry, entry('d', visitId: 'v4'), status: OutboxStatus.rejected),
      ];
      expect(selectPurgeable(items, pull), {'a'});
    });

    test('an entry with no visit is purged once acknowledged: the server made its visit', () {
      final flowB = item('b', OutboxKind.entry, entry('b', method: 'callback_confirmed'));
      final walkIn = item('w', OutboxKind.entry, entry('w', method: 'walk_in_admitted'));
      expect(selectPurgeable([flowB, walkIn], pull), {'b', 'w'});
    });

    test('refused entries are not walk-ins', () {
      final refused = item('r', OutboxKind.entry, entry('r', method: 'refused'));
      expect(selectPurgeable([refused], pull), {'r'});
    });
  });
}
