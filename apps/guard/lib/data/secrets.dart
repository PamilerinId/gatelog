import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Key/value secrets: the device token, the HMAC keys, the database key.
/// Backed by flutter_secure_storage (Android Keystore) in the app, in memory in tests.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Typed access to the secrets the app keeps.
class Secrets {
  Secrets(this._store);
  final SecretStore _store;

  static const _token = 'device_token';
  static const _keys = 'hmac_keys';
  static const _dbKey = 'db_key';

  Future<String?> token() => _store.read(_token);
  Future<void> setToken(String token) => _store.write(_token, token);

  Future<Map<int, List<int>>> hmacKeys() async {
    final raw = await _store.read(_keys);
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {for (final e in m.entries) int.parse(e.key): base64.decode(e.value as String)};
  }

  Future<void> setHmacKeys(Map<int, List<int>> keys) =>
      _store.write(_keys, jsonEncode({for (final e in keys.entries) '${e.key}': base64.encode(e.value)}));

  /// The SQLCipher key, made on first launch. Hex, 32 random bytes.
  Future<String> databaseKey() async {
    final existing = await _store.read(_dbKey);
    if (existing != null) return existing;
    final rnd = Random.secure();
    final key = List.generate(32, (_) => rnd.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await _store.write(_dbKey, key);
    return key;
  }

  Future<bool> hasDatabaseKey() async => await _store.read(_dbKey) != null;

  /// Forget the pairing. The database key stays so the (now empty) database still opens.
  Future<void> wipeSession() async {
    await _store.delete(_token);
    await _store.delete(_keys);
  }
}
