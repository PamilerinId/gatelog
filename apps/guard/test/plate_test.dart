import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatelog_guard/core/plate_text.dart';
import 'package:gatelog_guard/data/models.dart';
import 'package:gatelog_guard/sync/capture.dart';
import 'package:gatelog_guard/ui/screens/admit_screens.dart';
import 'package:image/image.dart' as img;

import 'support.dart';

void main() {
  group('the plate in what the camera read', () {
    test('a modern plate, on one line or split', () {
      expect(plateFromText(['LAGOS', 'KJA 456 XY', 'Centre of Excellence']), 'KJA456XY');
      expect(plateFromText(['KJA', '456XY']), 'KJA456XY');
      expect(plateFromText(['ABC-123DE']), 'ABC123DE');
    });

    test('an older plate', () {
      expect(plateFromText(['AB 123 CDE']), 'AB123CDE');
    });

    test('letters and digits read the wrong way round are mended in their place', () {
      expect(plateFromText(['KJA 4S6 XY']), 'KJA456XY');
      expect(plateFromText(['KJA 456 X8']), 'KJA456XB');
    });

    test('a plate inside a longer line', () {
      expect(plateFromText(['LAGOSKJA456XYEXCELLENCE']), 'KJA456XY');
    });

    test('nothing like a plate: null', () {
      expect(plateFromText(['LAGOS', 'Centre of Excellence', '2024']), isNull);
      expect(plateFromText(const []), isNull);
    });

    test("the home's registered car wins", () {
      expect(plateFromText(['LND 1 EV'], known: const [Vehicle(plate: 'lnd 1 ev')]), 'LND1EV');
    });

    test('shown with spaces', () {
      expect(spacePlate('KJA456XY'), 'KJA 456 XY');
      expect(spacePlate('ODD'), 'ODD');
    });
  });

  group('reading a plate photo (the recognizer mocked)', () {
    final home = StateSnapshot.fromJson(sampleState()).homes.single;
    Uint8List jpeg() {
      final pic = img.Image(width: 1600, height: 1200);
      img.fill(pic, color: img.ColorRgb8(200, 200, 40));
      return Uint8List.fromList(img.encodeJpg(pic));
    }

    test('a plate read: the text and a JPEG under 400 KB, and a registered car is matched', () async {
      readText = (shot) async => ['LAGOS', 'KJA 456 XY'];
      final read = await readPlate(Shot(jpeg()), home);
      expect(read.plateText, 'KJA456XY');
      expect(read.plate, isNotNull);
      expect(read.plate!.length, lessThan(400 * 1024));
      final decoded = img.decodeJpg(Uint8List.fromList(read.plate!))!;
      expect(decoded.width, 1024, reason: 'long side 1024 px so the plate stays readable');
      expect(home.vehicleFor(read.plateText)?.description, 'Black Corolla');
    });

    test('nothing read: no text, the photo is still kept', () async {
      readText = (shot) async => ['Centre of Excellence'];
      final read = await readPlate(Shot(jpeg()), home);
      expect(read.plateText, isNull);
      expect(read.plate, isNotNull);
    });

    test('the recognizer fails: no text', () async {
      readText = (shot) async => const [];
      final read = await readPlate(Shot(jpeg()), home);
      expect(read.plateText, isNull);
    });
  });
}
