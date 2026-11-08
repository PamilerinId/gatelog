import '../data/store.dart';
import 'api.dart';

class PushReport {
  int sent = 0;
  int rejected = 0;

  /// True when the network failed part way; what is left stays pending for the next try.
  bool interrupted = false;
}

/// Pushes the outbox to `POST /v1/device/sync` (and `/directory/report`), per the contract:
/// accepted and duplicates leave the queue, rejected items leave it too and go to
/// "needs attention", a network failure leaves everything pending to retry.
///
/// "Leave the queue" means status `sent`: the item is never pushed again, but it keeps
/// shaping what the gate shows until a state pull that started after it was acknowledged
/// (see [selectPurgeable]). Otherwise a guest admitted offline would vanish from
/// Inside now between the push and the next pull.
class OutboxPusher {
  OutboxPusher(this.store, this.api, {this.batchSize = 100, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final GateStore store;
  final GateApi api;
  final int batchSize;
  final DateTime Function() _clock;

  /// Throws [UnauthorizedException]; everything else is handled. [only] limits the push to some
  /// records (the controller sends shift ends after a rider's positions).
  Future<PushReport> push(String token, {bool Function(OutboxItem)? only}) async {
    final report = PushReport();
    final pending = [for (final i in await store.outbox(status: OutboxStatus.pending)) if (only == null || only(i)) i];
    final batchable = pending.where((i) => OutboxKind.syncKinds.contains(i.kind)).toList();
    try {
      for (var i = 0; i < batchable.length; i += batchSize) {
        final end = i + batchSize > batchable.length ? batchable.length : i + batchSize;
        await _sendBatch(token, batchable.sublist(i, end), report);
      }
      for (final item in pending.where((i) => i.kind == OutboxKind.directoryReport)) {
        await _sendReport(token, item, report);
      }
    } on NetworkException {
      report.interrupted = true;
    }
    return report;
  }

  static Map<String, dynamic> buildBody(List<OutboxItem> items) => {
        for (final k in OutboxKind.syncKinds) k: [for (final i in items.where((i) => i.kind == k)) i.payload],
      };

  Future<void> _sendBatch(String token, List<OutboxItem> items, PushReport report) async {
    final SyncResult res;
    try {
      res = await api.sync(token, buildBody(items));
    } on ApiException catch (e) {
      // The whole body was refused (422 validation). Split it so one bad record cannot
      // hold back the rest; a single record that is still refused goes to needs attention.
      if (items.length > 1) {
        final mid = items.length ~/ 2;
        await _sendBatch(token, items.sublist(0, mid), report);
        await _sendBatch(token, items.sublist(mid), report);
      } else {
        await store.markRejected(items.single.id, 'Server refused it: ${e.detail}');
        report.rejected++;
      }
      return;
    } on NetworkException {
      await store.bumpAttempts(items.map((i) => i.id));
      rethrow;
    }
    // The server answers with each record's server id. A shift's start and end share one, so
    // one answer can settle two local items.
    final byServerId = <String, List<String>>{};
    for (final i in items) {
      byServerId.putIfAbsent(i.serverId.toLowerCase(), () => []).add(i.id);
    }
    final rejected = {for (final r in res.rejected.entries) r.key.toLowerCase(): r.value};
    final ok = {
      for (final id in [...res.accepted, ...res.duplicates])
        if (!rejected.containsKey(id.toLowerCase())) ...?byServerId[id.toLowerCase()],
    };
    await store.markSent(ok, _clock());
    report.sent += ok.length;
    for (final r in rejected.entries) {
      for (final id in byServerId[r.key] ?? const <String>[]) {
        await store.markRejected(id, r.value);
        report.rejected++;
      }
    }
    final answered = {for (final id in [...res.accepted, ...res.duplicates, ...res.rejected.keys]) id.toLowerCase()};
    await store.bumpAttempts([
      for (final e in byServerId.entries)
        if (!answered.contains(e.key)) ...e.value,
    ]);
  }

  Future<void> _sendReport(String token, OutboxItem item, PushReport report) async {
    try {
      await api.reportNumber(token, entryId: item.payload['entry_id'] as String, guardId: item.payload['guard_id'] as String?);
      await store.markSent([item.id], _clock());
      report.sent++;
    } on ApiException catch (e) {
      await store.markRejected(item.id, e.status == 404 ? 'That number is no longer in the directory.' : e.detail);
      report.rejected++;
    } on NetworkException {
      await store.bumpAttempts([item.id]);
      rethrow;
    }
  }
}

/// Which `sent` items can be deleted after a successful state pull that started at [pullStartedAt].
///
/// An item acknowledged before the pull began is reflected in the pulled state, so it can go.
/// That includes entries with no visit (admitted on a callback, or a walk-in on the CSO's
/// decision): the server makes a visit for them, which comes back in the state with this
/// entry's id.
Set<String> selectPurgeable(List<OutboxItem> items, DateTime pullStartedAt) {
  bool acked(OutboxItem i) => i.isSent && i.sentAt != null && !i.sentAt!.isAfter(pullStartedAt);
  return {for (final i in items) if (acked(i)) i.id};
}
