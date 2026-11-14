import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:gatelog_guard/app/caller.dart';
import 'package:gatelog_guard/app/controller.dart';
import 'package:gatelog_guard/core/pin.dart';
import 'package:gatelog_guard/data/db.dart';
import 'package:gatelog_guard/data/shuttle.dart';
import 'package:gatelog_guard/data/store.dart';
import 'package:gatelog_guard/sync/api.dart';

GateStore memoryStore() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return GateStore(GateDatabase(NativeDatabase.memory()));
}

/// A scripted API. `onSync` decides each batch's answer; default accepts everything.
class FakeApi implements GateApi {
  final List<Map<String, dynamic>> syncBodies = [];
  final List<String> reports = [];
  SyncResult Function(Map<String, dynamic> body)? onSync;
  Object? syncError;
  Object? reportError;
  Object? stateError;
  Map<String, dynamic>? state;
  String etag = '"v1"';
  final List<String?> stateEtags = [];

  final List<(String, int)> selfies = [];
  final List<String> csoShiftIds = [];

  /// Status for the next selfie uploads, in order (204 when empty).
  final List<int> selfieStatuses = [];
  Object? selfieError;
  Map<String, dynamic>? csoBody;
  Object? csoError;

  /// Rider positions the server stored, by shift, and the status to answer (200 when empty).
  final List<(String, List<PositionFix>)> positionBatches = [];
  final List<int> positionStatuses = [];
  Object? positionError;

  /// How many sync bodies had gone up when each position batch was posted.
  final List<int> positionAfterSyncs = [];

  /// The server ids in a sync body, the way the server answers them.
  static List<String> idsIn(Map<String, dynamic> body) => [
        for (final i in (body['pins'] as List? ?? const [])) (i as Map)['guard_id'] as String,
        for (final k in ['shifts', 'cards', 'rides', 'ride_events', 'pin_checks', 'number_offers', 'visits', 'callbacks', 'entries', 'exits'])
          ...[for (final i in (body[k] as List? ?? const [])) (i as Map)['id'] as String],
        for (final i in body['rollup_checks'] as List) (i as Map)['item_id'] as String,
      ];

  @override
  Future<SyncResult> sync(String token, Map<String, dynamic> body) async {
    syncBodies.add(body);
    if (syncError != null) throw syncError!;
    return onSync?.call(body) ?? SyncResult(accepted: idsIn(body), duplicates: const [], rejected: const {});
  }

  @override
  Future<void> reportNumber(String token, {required String entryId, String? guardId}) async {
    if (reportError != null) throw reportError!;
    reports.add(entryId);
  }

  @override
  Future<StateResult> fetchState(String token, {String? etag}) async {
    stateEtags.add(etag);
    if (stateError != null) throw stateError!;
    if (etag == this.etag) return StateResult.notModified(etag);
    return StateResult(this.etag, state!);
  }

  @override
  Future<PairResult> pair(String code, {String? fcmToken}) async =>
      const PairResult(token: 'gld.dev.estate.secret', deviceId: 'dev', estateId: 'estate', estateName: 'Magodo Phase 2', gateName: 'Main gate');

  @override
  Future<void> putFcmToken(String token, String fcmToken) async {}

  @override
  Future<void> uploadSelfie(String token, String shiftId, List<int> jpeg) async {
    if (selfieError != null) throw selfieError!;
    final status = selfieStatuses.isEmpty ? 204 : selfieStatuses.removeAt(0);
    if (status == 404) throw ApiException(404, 'no such shift on this phone');
    if (status >= 400) throw ApiException(status, 'refused');
    selfies.add((shiftId, jpeg.length));
  }

  /// Clips and photos the server stored: (id, kind, bytes); and the status to answer next (204 when empty).
  final List<(String, String, int)> media = [];
  final List<int> mediaStatuses = [];
  Object? mediaError;

  Future<void> _media(String id, String kind, List<int> bytes) async {
    if (mediaError != null) throw mediaError!;
    final status = mediaStatuses.isEmpty ? 204 : mediaStatuses.removeAt(0);
    if (status >= 400) throw ApiException(status, 'refused');
    media.add((id, kind, bytes.length));
  }

  @override
  Future<void> uploadClip(String token, String clipId, List<int> audio, String contentType) => _media(clipId, 'clip', audio);

  @override
  Future<void> uploadPhoto(String token, String photoId, String kind, List<int> jpeg) => _media(photoId, kind, jpeg);

  @override
  Future<Map<String, dynamic>> fetchCso(String token, String shiftId) async {
    csoShiftIds.add(shiftId);
    if (csoError != null) throw csoError!;
    return csoBody ?? sampleCso();
  }

  @override
  Future<int> postPositions(String token, String shiftId, List<PositionFix> points) async {
    if (positionError != null) throw positionError!;
    final status = positionStatuses.isEmpty ? 200 : positionStatuses.removeAt(0);
    if (status >= 400) throw ApiException(status, 'refused');
    positionBatches.add((shiftId, points));
    positionAfterSyncs.add(syncBodies.length);
    return points.length;
  }
}

/// PIN 482913 for Musa (60k iterations would slow every test; the format is the same).
final musaPinHash = makePinHash('482913', iterations: 1000);

const fastPins = PinHasher(background: false, iterations: 1000);

Map<String, dynamic> sampleCso() => {
      'server_time': '2026-10-21T10:00:00+00:00',
      'needs': {
        'overdue': [
          {'visit_id': '9d0e7c6b-5a49-4382-a716-2f5e4d3c2b1a', 'guest_name': 'Tunde Bakare', 'home_id': 'h1', 'address': '14B Adeniyi Close, Block C', 'expected_until': '2026-10-21T09:00:00+00:00', 'resident_id': 'r1'},
        ],
        'refused_today': [
          {'entry_id': 'e5', 'guest_name': 'Hawker', 'address': '14B Adeniyi Close, Block C', 'gate': 'Main gate', 'by': 'Musa Ibrahim', 'reason': 'No answer twice', 'at': '2026-10-21T08:05:00+00:00'},
        ],
        'walk_ins_today': [],
        'quiet_phones': [
          {'device_id': 'd2', 'gate': 'Back gate', 'label': 'Back gate phone', 'last_sync_at': '2026-10-21T07:00:00+00:00', 'on_duty': 'Sunday Etim'},
        ],
        'night_list_unchecked': 0,
      },
      'on_duty': [
        {'gate': 'Main gate', 'guard': 'Mr Bello', 'role': 'cso', 'since': '2026-10-21T07:00:00+00:00', 'phone_last_sync_at': '2026-10-21T09:59:00+00:00'},
      ],
      'shifts_today': [
        {'id': 's0', 'gate': 'Main gate', 'guard': 'Musa Ibrahim', 'started_at': '2026-10-20T18:00:00+00:00', 'ended_at': '2026-10-21T06:00:00+00:00',
         'end_reason': 'handover', 'handed_to': 'Mr Bello', 'handover': {'inside': 2, 'unsynced': 0, 'night_list_open': 1}, 'selfie': true},
      ],
    };

/// Guards' PIN hashes by id. Musa has PIN 482913 unless overridden; the others have none.
Map<String, dynamic> sampleState({
  List<Map<String, dynamic>> visits = const [],
  Map<String, dynamic>? rollup,
  Map<String, String?> pinHashes = const {},
  bool callbackRequired = false,
  Map<String, dynamic>? shuttle,
  String? houseCodeHash,
}) =>
    {
      'server_time': '2026-10-21T10:00:00+00:00',
      'estate': {'id': 'e1', 'name': 'Magodo Phase 2', 'timezone': 'Africa/Lagos', 'walk_in_policy': 'Do not admit.', 'key_version': 1},
      'device': {'id': 'd1', 'gate_id': 'g1'},
      'keys': [
        {'version': 1, 'key_b64': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8='},
      ],
      'gates': [
        {'id': 'g1', 'name': 'Main gate'},
      ],
      'guards': [
        {'id': 'gu1', 'name': 'Musa Ibrahim', 'role': 'guard', 'pin_hash': pinHashes.containsKey('gu1') ? pinHashes['gu1'] : musaPinHash, 'pin_reset_at': null, 'consent': true},
        {'id': 'gu2', 'name': 'Sunday Etim', 'role': 'guard', 'pin_hash': pinHashes['gu2'], 'pin_reset_at': null, 'consent': true},
        {'id': 'gu3', 'name': 'New Guard', 'role': 'guard', 'pin_hash': null, 'pin_reset_at': null, 'consent': false},
        {'id': 'cso1', 'name': 'Mr Bello', 'role': 'cso', 'pin_hash': pinHashes['cso1'], 'pin_reset_at': null, 'consent': true},
        if (shuttle != null) ...[
          {'id': 'ri1', 'name': 'Kunle Rider', 'role': 'rider', 'pin_hash': pinHashes.containsKey('ri1') ? pinHashes['ri1'] : musaPinHash, 'pin_reset_at': null, 'consent': true},
          {'id': 'ri2', 'name': 'Ade Rider', 'role': 'rider', 'pin_hash': pinHashes['ri2'], 'pin_reset_at': null, 'consent': true},
        ],
      ],
      'homes': [
        {
          'id': 'h1',
          'label': '14b',
          'street': 'Adeniyi Close',
          'zone': 'Block C',
          'address': '14B Adeniyi Close, Block C',
          'callback_required': callbackRequired,
          'residents': [
            {
              'id': 'r1',
              'name': 'Mrs Adeyemi',
              'contact_pref': 'whatsapp',
              'numbers': [
                {'id': 'n1', 'e164': '+2348031234567', 'last4': '4567', 'is_primary': true},
              ],
            },
          ],
          'vehicles': [
            {'plate': 'KJA456XY', 'description': 'Black Corolla'},
          ],
          'house_code_hash': houseCodeHash,
        },
      ],
      'visits': visits,
      'rollup': rollup,
      'directory': [
        {'id': 'dir1', 'category': 'crime', 'name': 'Police', 'number': '112', 'verified_at': null, 'reported_not_working': false},
      ],
      'shuttle': shuttle,
    };

/// The estate card in [sampleShuttle]: UID 04:A2:1B:7C:55:80, Mrs Adeyemi's (estate e1).
const cardUid = '04:A2:1B:7C:55:80';

/// A ride as `/state` sends it: from the main gate to 14B unless told otherwise.
Map<String, dynamic> sampleRide(
  String id, {
  String kind = 'resident',
  String source = 'whatsapp',
  String state = 'requested',
  String? riderId,
  String? rider,
  String wantedAt = '2026-10-21T09:50:00+00:00',
  String? passenger,
  String? note,
  bool fromHome = true,
}) =>
    {
      'id': id,
      'kind': kind,
      'source': source,
      'state': state,
      'home_id': 'h1',
      'resident_id': kind == 'resident' ? 'r1' : null,
      'passenger': passenger,
      'pickup': fromHome
          ? {'kind': 'home', 'ref': 'h1', 'label': '14B Adeniyi Close, Block C', 'lat': null, 'lng': null}
          : {'kind': 'gate', 'ref': 'g1', 'label': 'Main gate', 'lat': 6.6005, 'lng': 3.39},
      'dropoff': fromHome
          ? {'kind': 'gate', 'ref': 'g1', 'label': 'Main gate', 'lat': 6.6005, 'lng': 3.39}
          : {'kind': 'home', 'ref': 'h1', 'label': '14B Adeniyi Close, Block C', 'lat': null, 'lng': null},
      'wanted_at': wantedAt,
      'note': note,
      'rider_id': riderId,
      'rider': rider,
      'shuttle_id': riderId == null ? null : 'bike1',
      'accepted_at': null,
      'picked_up_at': null,
      'created_at': '2026-10-21T09:45:00+00:00',
    };

Map<String, dynamic> sampleShuttle({List<Map<String, dynamic>> rides = const [], String cardHash = ''}) => {
      'shuttles': [
        {'id': 'bike1', 'label': 'S1', 'plate': 'LND1EV'},
        {'id': 'bike2', 'label': 'S2', 'plate': 'LND2EV'},
      ],
      'places': [
        {'id': 'pl1', 'name': 'Clubhouse', 'kind': 'amenity', 'lat': 6.61, 'lng': 3.39},
      ],
      'cards': [
        if (cardHash.isNotEmpty) {'id': 'card1', 'uid_hash': cardHash, 'resident_id': 'r1', 'home_id': 'h1', 'uid_last4': '5580'},
      ],
      'rides': rides,
    };

/// A paired controller with Musa's shift open (PIN 482913, no selfie).
Future<void> pairAndOpenShift(GateController c, {String guardId = 'gu1', List<int>? selfie}) async {
  await c.pair('ABCD-2345');
  await c.idle();
  await c.openShift(guardId, selfieJpeg: selfie);
  await c.idle();
}

/// Caller ID as the call-screening service would give it.
class FakeCallerId implements CallerId {
  FakeCallerId([this.call]);
  IncomingCall? call;
  bool role = false;
  int asked = 0;

  @override
  Future<IncomingCall?> lastIncoming() async => call;

  @override
  Future<bool> requestRole() async {
    asked++;
    return role;
  }

  @override
  Future<bool> hasRole() async => role;
}
