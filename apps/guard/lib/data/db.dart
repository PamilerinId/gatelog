import 'package:drift/drift.dart';

part 'db.g.dart';

// --- the last state snapshot, replaced wholesale on every 200 from /v1/device/state ---

@DataClassName('HomeRow')
class HomesTable extends Table {
  @override
  String get tableName => 'homes';
  TextColumn get id => text()();
  TextColumn get label => text()();
  TextColumn get street => text()();
  TextColumn get zone => text()();
  TextColumn get address => text()();
  BoolColumn get callbackRequired => boolean()();

  /// The shuttle house code's PBKDF2 hash (never the code). Null when none was asked for.
  TextColumn get houseCodeHash => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ResidentRow')
class ResidentsTable extends Table {
  @override
  String get tableName => 'residents';
  TextColumn get id => text()();
  TextColumn get homeId => text()();
  TextColumn get name => text()();
  TextColumn get contactPref => text()();
  IntColumn get position => integer()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('NumberRow')
class NumbersTable extends Table {
  @override
  String get tableName => 'numbers';
  TextColumn get id => text()();
  TextColumn get residentId => text()();
  TextColumn get e164 => text()();
  TextColumn get last4 => text()();
  BoolColumn get isPrimary => boolean()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('VisitRow')
class VisitsTable extends Table {
  @override
  String get tableName => 'visits';
  TextColumn get id => text()();
  TextColumn get homeId => text()();
  TextColumn get residentId => text().nullable()();
  TextColumn get guestName => text()();
  IntColumn get windowStart => integer()();
  IntColumn get windowEnd => integer()();
  IntColumn get keyVersion => integer().nullable()();
  BoolColumn get codeIssued => boolean()();
  TextColumn get source => text()();
  TextColumn get state => text()();
  TextColumn get expectedUntil => text().nullable()();
  TextColumn get entryId => text().nullable()();
  TextColumn get enteredAt => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DirectoryRow')
class DirectoryTable extends Table {
  @override
  String get tableName => 'directory';
  TextColumn get id => text()();
  IntColumn get position => integer()();
  TextColumn get category => text()();
  TextColumn get name => text()();
  TextColumn get number => text()();
  TextColumn get verifiedAt => text().nullable()();
  BoolColumn get reportedNotWorking => boolean()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('GateRow')
class GatesTable extends Table {
  @override
  String get tableName => 'gates';
  TextColumn get id => text()();
  TextColumn get name => text()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Everyone who can open a shift. PIN hashes live here, inside the encrypted database.
@DataClassName('GuardRow')
class GuardsTable extends Table {
  @override
  String get tableName => 'guards';
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get role => text().withDefault(const Constant('guard'))();
  TextColumn get pinHash => text().nullable()();
  TextColumn get pinResetAt => text().nullable()();
  BoolColumn get consent => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('VehicleRow')
class VehiclesTable extends Table {
  @override
  String get tableName => 'vehicles';
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get homeId => text()();
  TextColumn get plate => text()();
  TextColumn get description => text().nullable()();
}

/// Shift-start selfies waiting to upload. Kept in the encrypted database, never shown, and
/// deleted as soon as the server has stored them.
@DataClassName('SelfieRow')
class SelfiesTable extends Table {
  @override
  String get tableName => 'selfies';
  TextColumn get shiftId => text()();
  BlobColumn get jpeg => blob()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {shiftId};
}

/// Voice clips (a visitor's name, said) and photos (the visitor, the car's plate) waiting to
/// upload. Kept in the encrypted database, never shown again, deleted once the server has them.
@DataClassName('MediaRow')
class MediaTable extends Table {
  @override
  String get tableName => 'media';

  /// The clip's or photo's own UUID, named on the record (`name_clip_id`, `visitor_photo_id`...).
  TextColumn get id => text()();

  /// clip | visitor | plate
  TextColumn get kind => text()();
  BlobColumn get bytes => blob()();
  TextColumn get contentType => text()();

  /// The record that names it (an entry or a visit), so Leaving can play a clip back.
  TextColumn get ref => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

/// Positions recorded during a rider's open shift, waiting to go to `POST /v1/device/positions`.
/// Kept 2 hours at most, sent oldest first, deleted once the server has them.
@DataClassName('PositionRow')
class PositionsTable extends Table {
  @override
  String get tableName => 'positions';
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get shiftId => text()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  RealColumn get accuracyM => real().nullable()();
  RealColumn get heading => real().nullable()();
  RealColumn get speed => real().nullable()();
  DateTimeColumn get at => dateTime()();
}

/// Small values: estate, device, rollup (JSON), etag, sync times, the open shift, PIN lockouts,
/// the last CSO overview.
@DataClassName('MetaRow')
class MetaTable extends Table {
  @override
  String get tableName => 'meta';
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

// --- the outbox: everything the guard records, until the server has it ---

@DataClassName('OutboxRow')
class OutboxTable extends Table {
  @override
  String get tableName => 'outbox';
  IntColumn get seq => integer().autoIncrement()();

  /// The client UUID sent to the server (for rollup checks: the rollup item id).
  TextColumn get itemId => text().unique()();

  /// pins | shifts | visits | callbacks | entries | exits | rollup_checks | directory_report
  TextColumn get kind => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// pending | sent | rejected
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get sentAt => dateTime().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

@DriftDatabase(tables: [
  HomesTable,
  ResidentsTable,
  NumbersTable,
  VisitsTable,
  DirectoryTable,
  GatesTable,
  GuardsTable,
  VehiclesTable,
  MetaTable,
  OutboxTable,
  SelfiesTable,
  PositionsTable,
  MediaTable,
])
class GateDatabase extends _$GateDatabase {
  GateDatabase(super.e);

  /// 2: guard roles, PIN hashes and consent; home vehicles; selfies (shifts with PIN and selfie).
  /// 3: the estate shuttle: house code hashes on homes, the rider's position queue.
  /// 4: voice clips and visitor and plate photos waiting to upload.
  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(guardsTable, guardsTable.role);
            await m.addColumn(guardsTable, guardsTable.pinHash);
            await m.addColumn(guardsTable, guardsTable.pinResetAt);
            await m.addColumn(guardsTable, guardsTable.consent);
            await m.addColumn(guardsTable, guardsTable.position);
            await m.createTable(vehiclesTable);
            await m.createTable(selfiesTable);
            // The guard list is a cache; force a full pull so the new columns fill in.
            await (delete(metaTable)..where((t) => t.key.equals('etag'))).go();
          }
          if (from < 3) {
            await m.addColumn(homesTable, homesTable.houseCodeHash);
            await m.createTable(positionsTable);
            // Force a full pull so the shuttle section and the house code hashes fill in.
            await (delete(metaTable)..where((t) => t.key.equals('etag'))).go();
          }
          if (from < 4) {
            await m.createTable(mediaTable);
            // Force a full pull so the estate's photo rule (`visitor_photos`) fills in.
            await (delete(metaTable)..where((t) => t.key.equals('etag'))).go();
          }
        },
      );
}
