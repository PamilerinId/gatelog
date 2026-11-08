/// The shift-start selfie as the server wants it: a JPEG about 640 px on the long side and
/// under 400 KB. Decoding and encoding run in an isolate so the gate never stutters.
library;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const selfieLongSide = 640;
const selfieMaxBytes = 400 * 1024;

/// Null if [raw] is not an image we can read (the shift then starts with no selfie).
Future<Uint8List?> shrinkSelfie(Uint8List raw) => compute(shrinkSelfieSync, raw);

Uint8List? shrinkSelfieSync(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return null;
  var pic = img.bakeOrientation(decoded);
  final long = pic.width > pic.height ? pic.width : pic.height;
  if (long > selfieLongSide) {
    pic = pic.width >= pic.height ? img.copyResize(pic, width: selfieLongSide) : img.copyResize(pic, height: selfieLongSide);
  }
  for (final quality in const [80, 65, 50, 35]) {
    final out = img.encodeJpg(pic, quality: quality);
    if (out.length < selfieMaxBytes) return out;
  }
  return null;
}
