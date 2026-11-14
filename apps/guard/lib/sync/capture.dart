/// The phone's camera, microphone and on-device text recognition, behind small seams the tests
/// replace (there is no camera, microphone or ML Kit in a widget test).
///
/// Nothing captured here is logged. Photos and clips go to the encrypted database and leave
/// the phone only to the API; the files the camera and the recorder write are deleted at once.
library;

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

// --- camera ---------------------------------------------------------------------------------------

/// One photo as the camera wrote it. [discard] deletes the file.
class Shot {
  Shot(this.raw, {this.path});
  final Uint8List raw;
  final String? path;

  Future<void> discard() async {
    final p = path;
    if (p == null) return;
    try {
      await File(p).delete();
    } catch (_) {}
  }

  @override
  String toString() => 'Shot(${raw.length} bytes)';
}

abstract class GateCamera {
  /// The live view, for aiming at a plate or a visitor. Never a photo already taken.
  Widget preview();

  /// One photo, or null if the camera failed.
  Future<Shot?> take();
  Future<void> dispose();
}

class _DeviceCamera implements GateCamera {
  _DeviceCamera(this.c);
  final CameraController c;

  @override
  Widget preview() => ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(width: c.value.previewSize?.height ?? 480, height: c.value.previewSize?.width ?? 640, child: CameraPreview(c)),
        ),
      );

  @override
  Future<Shot?> take() async {
    try {
      final f = await c.takePicture().timeout(const Duration(seconds: 6));
      return Shot(await f.readAsBytes(), path: f.path);
    } catch (e) {
      debugPrint('photo failed: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Future<void> dispose() => c.dispose();
}

/// Opens the front camera (the shift selfie) or the back one (the visitor, the plate). Null
/// when there is none or it fails: the caller goes on without a photo. Replaced in tests.
Future<GateCamera?> Function({required bool front}) openCamera = ({required bool front}) async {
  try {
    final cams = await availableCameras().timeout(const Duration(seconds: 6));
    if (cams.isEmpty) return null;
    final want = front ? CameraLensDirection.front : CameraLensDirection.back;
    final cam = cams.firstWhere((c) => c.lensDirection == want, orElse: () => cams.first);
    final c = CameraController(cam, front ? ResolutionPreset.medium : ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    await c.initialize().timeout(const Duration(seconds: 6));
    return _DeviceCamera(c);
  } catch (e) {
    debugPrint('camera unavailable: ${e.runtimeType}');
    return null;
  }
};

// --- plate text -------------------------------------------------------------------------------------

/// What on-device text recognition (ML Kit, Latin script, bundled: it works with no network)
/// reads in a photo, line by line. Replaced in tests.
Future<List<String>> Function(Shot shot) readText = (shot) async {
  final path = shot.path;
  if (path == null) return const [];
  final r = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final text = await r.processImage(InputImage.fromFilePath(path)).timeout(const Duration(seconds: 8));
    return [
      for (final b in text.blocks)
        for (final l in b.lines) l.text,
    ];
  } catch (e) {
    debugPrint('text recognition failed: ${e.runtimeType}');
    return const [];
  } finally {
    await r.close();
  }
};

// --- voice clips ------------------------------------------------------------------------------------

/// A visitor's name, said: AAC in an MP4 container, mono, 32 kbit/s (about 120 KB for the
/// 30 seconds at most the gate allows; the server takes up to 300 KB).
class VoiceClip {
  const VoiceClip(this.bytes, {this.contentType = 'audio/mp4'});
  final Uint8List bytes;
  final String contentType;

  @override
  String toString() => 'VoiceClip(${bytes.length} bytes)';
}

const clipMaxLength = Duration(seconds: 30);

abstract class ClipRecorder {
  /// False when the microphone is refused or missing.
  Future<bool> start();

  /// The clip, or null if nothing was recorded.
  Future<VoiceClip?> stop();
  Future<void> dispose();
}

class _DeviceRecorder implements ClipRecorder {
  final _r = AudioRecorder();
  String? _path;

  @override
  Future<bool> start() async {
    try {
      if (!await _r.hasPermission()) return false;
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/clip-${const Uuid().v4()}.m4a';
      await _r.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 16000, numChannels: 1), path: path);
      _path = path;
      return true;
    } catch (e) {
      debugPrint('recorder failed: ${e.runtimeType}');
      return false;
    }
  }

  @override
  Future<VoiceClip?> stop() async {
    try {
      final path = await _r.stop() ?? _path;
      if (path == null) return null;
      final f = File(path);
      final bytes = await f.readAsBytes();
      try {
        await f.delete();
      } catch (_) {}
      return bytes.isEmpty ? null : VoiceClip(bytes);
    } catch (e) {
      debugPrint('recorder stop failed: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _r.dispose();
    } catch (_) {}
  }
}

/// A new recorder for one clip. Replaced in tests.
ClipRecorder Function() newRecorder = _DeviceRecorder.new;

AudioPlayer? _player;

/// Plays a clip still on the phone (the Leaving list, the call flow). Replaced in tests.
Future<void> Function(Uint8List bytes, String contentType) playClip = (bytes, contentType) async {
  try {
    final p = _player ??= AudioPlayer();
    await p.stop();
    await p.play(BytesSource(bytes, mimeType: contentType));
  } catch (e) {
    debugPrint('playback failed: ${e.runtimeType}');
  }
};
