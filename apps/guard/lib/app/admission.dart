/// What the gate captures after "Let them in", and the fixed reasons the guard taps instead of
/// typing.
library;

/// The visitor's photo and the car's plate, taken after "Let them in". Never shown again.
class GatePhotos {
  const GatePhotos({this.visitor, this.plate, this.plateText, this.skipped});

  /// The visitor's photo (a JPEG under 400 KB), or null.
  final List<int>? visitor;

  /// The plate camera's photo, kept whatever the guard said about the text read from it.
  final List<int>? plate;

  /// The plate as read and confirmed ("Is this the plate?" Yes), or null.
  final String? plateText;

  /// Why there is no visitor photo when the estate wanted one: `no_camera` or `refused`.
  final String? skipped;

  static const none = GatePhotos();

  GatePhotos copyWith({List<int>? visitor, List<int>? plate, String? plateText, String? skipped}) => GatePhotos(
        visitor: visitor ?? this.visitor,
        plate: plate ?? this.plate,
        plateText: plateText ?? this.plateText,
        skipped: skipped ?? this.skipped,
      );

  @override
  String toString() => 'GatePhotos(visitor: ${visitor != null}, plate: ${plate != null}, skipped: $skipped)';
}

abstract final class PhotoSkipped {
  static const noCamera = 'no_camera';
  static const refused = 'refused';
}

/// Why the CSO let someone in on a description. The `reason` sent is the English text.
enum CsoReason {
  known('Known to the CSO'),
  described('Described the house well'),
  delivery('Delivery or service'),
  other('Other, said in a voice clip');

  const CsoReason(this.api);
  final String api;
}

/// Why the gate turned someone away.
enum TurnAwayReason {
  wrongPerson('Not the person expected'),
  homeSaidNo('The home said no'),
  behaviour('Behaved badly at the gate'),
  wouldNotWait('Would not wait'),
  other('Other');

  const TurnAwayReason(this.api);
  final String api;
}

/// The guest's name on a record: "Voice clip" when the guard said it (`name_clip_id`), or the
/// name the home gave.
const voiceClipName = 'Voice clip';
