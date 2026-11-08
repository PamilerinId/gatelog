import 'package:flutter/foundation.dart';

import '../data/store.dart';
import 'api.dart';

class SelfieReport {
  int uploaded = 0;

  /// Still on the phone: the shift has not synced yet (404, or not sent), or no network.
  int waiting = 0;

  /// The server will never take it (413, 415, or its shift was rejected).
  int dropped = 0;
}

/// Uploads shift-start selfies once their shift has reached the server, per the contract:
/// `PUT /v1/device/shifts/{id}/selfie`, 204 stored (delete the local copy), 404 the shift has
/// not synced yet (keep it, try again after the next sync). Selfies are never shown and never
/// logged; a selfie the server refuses is deleted rather than kept.
class SelfieUploader {
  SelfieUploader(this.store, this.api, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final GateStore store;
  final GateApi api;
  final DateTime Function() _clock;

  /// The server deletes selfies after 30 days; one that never got there goes after the same time.
  static const keepFor = Duration(days: 30);

  /// Throws [UnauthorizedException]; everything else is handled.
  Future<SelfieReport> upload(String token) async {
    final report = SelfieReport();
    // The shift's opening record (its end is a second item with the same server id).
    final shiftRecords = {
      for (final i in await store.outbox())
        if (i.kind == OutboxKind.shift && i.id == i.serverId) i.id: i,
    };
    for (final shiftId in await store.selfieShiftIds()) {
      final record = shiftRecords[shiftId];
      if (record != null && record.isRejected) {
        await store.deleteSelfie(shiftId);
        report.dropped++;
        continue;
      }
      if (record != null && record.isPending) {
        report.waiting++;
        continue;
      }
      final jpeg = await store.selfie(shiftId);
      if (jpeg == null) continue;
      try {
        await api.uploadSelfie(token, shiftId, jpeg);
        await store.deleteSelfie(shiftId);
        report.uploaded++;
      } on ApiException catch (e) {
        if (e.status == 404) {
          await store.bumpSelfieAttempts(shiftId);
          report.waiting++;
        } else {
          debugPrint('selfie refused (${e.status}); deleted');
          await store.deleteSelfie(shiftId);
          report.dropped++;
        }
      } on NetworkException {
        await store.bumpSelfieAttempts(shiftId);
        report.waiting++;
        break;
      }
    }
    await _dropStale(report);
    return report;
  }

  Future<void> _dropStale(SelfieReport report) async {
    final cutoff = _clock().subtract(keepFor);
    for (final row in await store.db.select(store.db.selfiesTable).get()) {
      if (row.createdAt.isBefore(cutoff)) {
        await store.deleteSelfie(row.shiftId);
        report.dropped++;
      }
    }
  }
}
