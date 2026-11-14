import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/shuttle.dart';

/// 401: the phone was revoked or re-paired. Wipe and show pairing.
class UnauthorizedException implements Exception {
  @override
  String toString() => 'This phone is no longer paired.';
}

/// No connection, a timeout, or a server error worth retrying.
class NetworkException implements Exception {
  NetworkException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The server answered and said no (4xx other than 401). Retrying the same request will not help.
class ApiException implements Exception {
  ApiException(this.status, this.detail);
  final int status;
  final String detail;
  @override
  String toString() => detail;
}

class PairResult {
  const PairResult({required this.token, required this.deviceId, required this.estateId, required this.estateName, required this.gateName});
  final String token;
  final String deviceId;
  final String estateId;
  final String estateName;
  final String gateName;
}

class StateResult {
  const StateResult.notModified(this.etag) : body = null;
  const StateResult(this.etag, this.body);
  final String? etag;

  /// Null on 304.
  final Map<String, dynamic>? body;
  bool get notModified => body == null;
}

class SyncResult {
  const SyncResult({required this.accepted, required this.duplicates, required this.rejected});
  final List<String> accepted;
  final List<String> duplicates;

  /// id -> reason
  final Map<String, String> rejected;

  factory SyncResult.fromJson(Map<String, dynamic> j) => SyncResult(
        accepted: [for (final i in (j['accepted'] as List? ?? const [])) (i as String).toLowerCase()],
        duplicates: [for (final i in (j['duplicates'] as List? ?? const [])) (i as String).toLowerCase()],
        rejected: {
          for (final r in (j['rejected'] as List? ?? const [])) (r['id'] as String).toLowerCase(): (r['reason'] as String?) ?? 'Rejected',
        },
      );
}

/// The gate phone's API (`apps/api/app/routers/device.py`).
abstract class GateApi {
  Future<PairResult> pair(String code, {String? fcmToken});
  Future<StateResult> fetchState(String token, {String? etag});
  Future<SyncResult> sync(String token, Map<String, dynamic> body);
  Future<void> reportNumber(String token, {required String entryId, String? guardId});
  Future<void> putFcmToken(String token, String fcmToken);

  /// `PUT /v1/device/shifts/{id}/selfie`. Throws [ApiException] 404 while the shift has not
  /// synced, 413 too large, 415 not a JPEG.
  Future<void> uploadSelfie(String token, String shiftId, List<int> jpeg);

  /// `PUT /v1/device/clips/{id}`: a visitor's name, said. Throws [ApiException] 400 empty,
  /// 413 too large, 415 not audio.
  Future<void> uploadClip(String token, String clipId, List<int> audio, String contentType);

  /// `PUT /v1/device/photos/{id}?kind=visitor|plate`. Throws [ApiException] 413 or 415.
  Future<void> uploadPhoto(String token, String photoId, String kind, List<int> jpeg);

  /// `GET /v1/device/cso` for the CSO's open shift. Throws [ApiException] 403 otherwise.
  Future<Map<String, dynamic>> fetchCso(String token, String shiftId);

  /// `POST /v1/device/positions` for a rider's open shift, at most 200 points. Returns how many
  /// the server stored. Throws [ApiException] 409 (shift not open on this phone) or 403 (not a rider).
  Future<int> postPositions(String token, String shiftId, List<PositionFix> points);
}

class HttpGateApi implements GateApi {
  HttpGateApi(this.baseUrl, {http.Client? client, this.timeout = const Duration(seconds: 20)}) : _client = client ?? http.Client();

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  Uri _u(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Map<String, String> _headers(String? token, {bool json = true}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    final http.Response r;
    try {
      r = await call().timeout(timeout);
    } on TimeoutException {
      throw NetworkException('No answer from the server.');
    } on SocketException {
      throw NetworkException('No connection.');
    } on http.ClientException {
      throw NetworkException('No connection.');
    } on HandshakeException {
      throw NetworkException('Secure connection failed.');
    }
    if (r.statusCode == 401) throw UnauthorizedException();
    if (r.statusCode >= 500 || r.statusCode == 429 && !r.request!.url.path.endsWith('/pair')) {
      throw NetworkException('Server busy (${r.statusCode}).');
    }
    if (r.statusCode >= 400) throw ApiException(r.statusCode, _detail(r));
    return r;
  }

  static String _detail(http.Response r) {
    try {
      final d = (jsonDecode(r.body) as Map<String, dynamic>)['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty) return (d.first as Map)['msg']?.toString() ?? 'Invalid request';
    } catch (_) {}
    return 'Request failed (${r.statusCode}).';
  }

  @override
  Future<PairResult> pair(String code, {String? fcmToken}) async {
    final r = await _send(() => _client.post(_u('/v1/device/pair'), headers: _headers(null), body: jsonEncode({'code': code, 'fcm_token': fcmToken})));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return PairResult(
      token: j['token'] as String,
      deviceId: j['device_id'] as String,
      estateId: j['estate_id'] as String,
      estateName: j['estate_name'] as String,
      gateName: j['gate_name'] as String,
    );
  }

  @override
  Future<StateResult> fetchState(String token, {String? etag}) async {
    final r = await _send(() => _client.get(_u('/v1/device/state'), headers: {..._headers(token, json: false), 'If-None-Match': ?etag}));
    if (r.statusCode == 304) return StateResult.notModified(r.headers['etag'] ?? etag);
    return StateResult(r.headers['etag'], jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  @override
  Future<SyncResult> sync(String token, Map<String, dynamic> body) async {
    final r = await _send(() => _client.post(_u('/v1/device/sync'), headers: _headers(token), body: jsonEncode(body)));
    return SyncResult.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  @override
  Future<void> reportNumber(String token, {required String entryId, String? guardId}) async {
    await _send(() => _client.post(_u('/v1/device/directory/report'), headers: _headers(token), body: jsonEncode({'entry_id': entryId, 'guard_id': guardId})));
  }

  @override
  Future<void> putFcmToken(String token, String fcmToken) async {
    await _send(() => _client.put(_u('/v1/device/fcm-token'), headers: _headers(token), body: jsonEncode({'fcm_token': fcmToken})));
  }

  @override
  Future<void> uploadSelfie(String token, String shiftId, List<int> jpeg) async {
    await _send(() => _client.put(
          _u('/v1/device/shifts/$shiftId/selfie'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'image/jpeg'},
          body: jpeg,
        ));
  }

  @override
  Future<void> uploadClip(String token, String clipId, List<int> audio, String contentType) async {
    await _send(() => _client.put(
          _u('/v1/device/clips/$clipId'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': contentType},
          body: audio,
        ));
  }

  @override
  Future<void> uploadPhoto(String token, String photoId, String kind, List<int> jpeg) async {
    await _send(() => _client.put(
          _u('/v1/device/photos/$photoId?kind=$kind'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'image/jpeg'},
          body: jpeg,
        ));
  }

  @override
  Future<Map<String, dynamic>> fetchCso(String token, String shiftId) async {
    final r = await _send(() => _client.get(_u('/v1/device/cso'), headers: {..._headers(token, json: false), 'X-Shift-Id': shiftId}));
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  @override
  Future<int> postPositions(String token, String shiftId, List<PositionFix> points) async {
    final r = await _send(() => _client.post(
          _u('/v1/device/positions'),
          headers: _headers(token),
          body: jsonEncode({'shift_id': shiftId, 'points': [for (final p in points) p.toJson()]}),
        ));
    return ((jsonDecode(r.body) as Map<String, dynamic>)['stored'] as num?)?.toInt() ?? 0;
  }
}
