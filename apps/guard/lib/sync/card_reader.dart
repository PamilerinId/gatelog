import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

import '../core/card.dart';

enum CardReaderState { ready, off, none }

/// Reads an estate card's UID over NFC. The UID goes straight to [cardHash]; it is never
/// stored, shown or logged.
abstract class CardReader {
  /// ready: NFC is on. off: the phone has NFC but it is switched off. none: no NFC.
  Future<CardReaderState> state();

  /// Waits for one card and returns its UID as upper-case hex, or null if [cancel] was called.
  Future<String?> read();

  Future<void> cancel();
}

/// A phone without NFC (and the default in tests).
class NoCardReader implements CardReader {
  const NoCardReader();
  @override
  Future<CardReaderState> state() async => CardReaderState.none;
  @override
  Future<String?> read() async => null;
  @override
  Future<void> cancel() async {}
}

/// `package:nfc_manager`, Android only: the tag's identifier (`Tag.getId()`).
class NfcCardReader implements CardReader {
  Completer<String?>? _waiting;

  @override
  Future<CardReaderState> state() async {
    try {
      return switch (await NfcManager.instance.checkAvailability()) {
        NfcAvailability.enabled => CardReaderState.ready,
        NfcAvailability.disabled => CardReaderState.off,
        NfcAvailability.unsupported => CardReaderState.none,
      };
    } catch (e) {
      debugPrint('nfc check failed: ${e.runtimeType}');
      return CardReaderState.none;
    }
  }

  @override
  Future<String?> read() async {
    await cancel();
    final done = _waiting = Completer<String?>();
    try {
      await NfcManager.instance.startSession(
        pollingOptions: const {NfcPollingOption.iso14443, NfcPollingOption.iso15693, NfcPollingOption.iso18092},
        onDiscovered: (tag) async {
          final id = NfcTagAndroid.from(tag)?.id;
          if (id == null || id.isEmpty || done.isCompleted) return;
          done.complete(uidHex(id));
          await _stop();
        },
      );
    } catch (e) {
      debugPrint('nfc session failed: ${e.runtimeType}');
      if (!done.isCompleted) done.complete(null);
    }
    return done.future;
  }

  @override
  Future<void> cancel() async {
    final w = _waiting;
    _waiting = null;
    if (w != null && !w.isCompleted) w.complete(null);
    await _stop();
  }

  Future<void> _stop() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }
}
