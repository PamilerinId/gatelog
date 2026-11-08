import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'secrets.dart';

const _dbName = 'gatelog';

Future<String> _dbPath() async => p.join((await getApplicationSupportDirectory()).path, '$_dbName.sqlite');

/// Opens the SQLCipher-encrypted database. The key is 32 random bytes kept in secure storage.
///
/// If the key is gone (Keystore reset, app data partly cleared) the old file cannot be read:
/// delete it and start empty. The token went with the key, so the phone is re-paired anyway.
Future<GateDatabase> openGateDatabase(Secrets secrets) async {
  final path = await _dbPath();
  final file = File(path);
  if (!await secrets.hasDatabaseKey() && await file.exists()) {
    await file.delete();
  }
  final hexKey = await secrets.databaseKey();
  final db = GateDatabase(_connect(path, hexKey));
  try {
    await db.customSelect('SELECT count(*) FROM sqlite_master').get();
    return db;
  } catch (_) {
    // Wrong key or a corrupt file: start again.
    await db.close();
    if (await file.exists()) await file.delete();
    return GateDatabase(_connect(path, hexKey));
  }
}

QueryExecutor _connect(String path, String hexKey) => driftDatabase(
      name: _dbName,
      native: DriftNativeOptions(
        databasePath: () async => path,
        setup: (raw) {
          // The key must be the first statement on the connection.
          raw.execute("PRAGMA key = \"x'$hexKey'\"");
          // Fail closed: a plain SQLite build ignores the key and would write resident
          // phone numbers to disk unencrypted.
          if (raw.select('PRAGMA cipher_version').isEmpty) {
            throw StateError('SQLCipher is not available; refusing to open an unencrypted database.');
          }
          raw.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
