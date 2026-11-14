/// The shift-start selfie as the server wants it: a JPEG about 640 px on the long side and
/// under 400 KB. Decoding and encoding run in an isolate so the gate never stutters.
library;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const selfieLongSide = 640;
const selfieMaxBytes = 400 * 1024;

/// Null if [raw] is not an image we can read (the shift then starts with no selfie).
Future<Uint8List?> shrinkSelfie(Uint8List raw) => compute(shrinkSelfieSync, raw);

Uint8List? shrinkSelfieSync(Uint8List raw) => _shrink(raw, selfieLongSide);

/// Visitor and plate photos: the same rules (a JPEG under 400 KB, never shown again), larger
/// so a plate stays readable.
const gatePhotoLongSide = 1024;

Future<Uint8List?> shrinkGatePhoto(Uint8List raw) => compute(shrinkGatePhotoSync, raw);

Uint8List? shrinkGatePhotoSync(Uint8List raw) => _shrink(raw, gatePhotoLongSide);

Uint8List? _shrink(Uint8List raw, int longSide) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return null;
  var pic = img.bakeOrientation(decoded);
  final long = pic.width > pic.height ? pic.width : pic.height;
  if (long > longSide) {
    pic = pic.width >= pic.height ? img.copyResize(pic, width: longSide) : img.copyResize(pic, height: longSide);
  }
  for (final quality in const [80, 65, 50, 35]) {
    final out = img.encodeJpg(pic, quality: quality);
    if (out.length < selfieMaxBytes) return out;
  }
  return null;
}
