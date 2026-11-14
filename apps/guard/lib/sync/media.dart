import 'package:flutter/foundation.dart';

import '../data/store.dart';
import 'api.dart';

class MediaReport {
  int uploaded = 0;

  /// Still on the phone: no network.
  int waiting = 0;

  /// The server will never take it (empty, too large, wrong type), or it was too old.
  int dropped = 0;
}

/// Uploads voice clips (`PUT /v1/device/clips/{id}`) and gate photos
/// (`PUT /v1/device/photos/{id}?kind=visitor|plate`) when there is data. The record that names
/// one and the file itself can reach the server in either order, so nothing waits for the
/// outbox. 204 deletes the local copy; a refusal (400, 413, 415) deletes it too rather than
/// keeping it; a network failure keeps it for the next sync. Nothing here is ever logged but
/// the kind and the status.
class MediaUploader {
  MediaUploader(this.store, this.api, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final GateStore store;
  final GateApi api;
  final DateTime Function() _clock;

  /// The server deletes clips after 7 days and photos after 30: one that never got there by
  /// then goes from the phone too.
  static const keepClips = Duration(days: 7);
  static const keepPhotos = Duration(days: 30);

  /// Throws [UnauthorizedException]; everything else is handled.
  Future<MediaReport> upload(String token) async {
    final report = MediaReport();
    final now = _clock();
    for (final m in await store.mediaWaiting()) {
      final keep = m.kind == MediaKind.clip ? keepClips : keepPhotos;
      if (now.difference(m.createdAt) > keep) {
        await store.deleteMedia([m.id]);
        report.dropped++;
        continue;
      }
      final bytes = await store.mediaBytes(m.id);
      if (bytes == null) continue;
      try {
        if (m.kind == MediaKind.clip) {
          await api.uploadClip(token, m.id, bytes, m.contentType);
        } else {
          await api.uploadPhoto(token, m.id, m.kind, bytes);
        }
        await store.deleteMedia([m.id]);
        report.uploaded++;
      } on ApiException catch (e) {
        debugPrint('${m.kind} refused (${e.status}); deleted');
        await store.deleteMedia([m.id]);
        report.dropped++;
      } on NetworkException {
        await store.bumpMediaAttempts(m.id);
        report.waiting++;
        break;
      }
    }
    return report;
  }
}
