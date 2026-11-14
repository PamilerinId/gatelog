import 'dart:convert';

import 'package:drift/drift.dart';

import 'db.dart';
import 'models.dart';
import 'shuttle.dart';

/// Outbox kinds. [syncKinds] are the keys of the `POST /v1/device/sync` body.
abstract final class OutboxKind {
  static const pin = 'pins';
  static const shift = 'shifts';
  static const visit = 'visits';
  static const callback = 'callbacks';
  static const entry = 'entries';
  static const exit = 'exits';
  static const rollupCheck = 'rollup_checks';
  static const directoryReport = 'directory_report';

  /// The estate shuttle: cards issued by the CSO, rides booked on this phone, what happened to them.
  static const card = 'cards';
  static const ride = 'rides';
  static const rideEvent = 'ride_events';

  /// A home PIN checked on this phone, right or wrong (never the PIN).
  static const pinCheck = 'pin_checks';

  /// "Add this number for Mrs Adeyemi?": the only record that carries a full phone number.
  static const numberOffer = 'number_offers';

  /// PINs and shifts first: the server wants a shift before the records made during it. A ride
  /// goes before its events (a flagged-down ride and its pickup travel in the same batch).
  static const syncKinds = [pin, shift, card, ride, rideEvent, pinCheck, numberOffer, visit, callback, entry, exit, rollupCheck];
}

abstract final class OutboxStatus {
  static const pending = 'pending';
  static const sent = 'sent';
  static const rejected = 'rejected';
}

class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.status = OutboxStatus.pending,
    this.reason,
    this.sentAt,
    this.attempts = 0,
  });

  final String id;
  final String kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String status;
  final String? reason;
  final DateTime? sentAt;
  final int attempts;

  bool get isPending => status == OutboxStatus.pending;
  bool get isSent => status == OutboxStatus.sent;
  bool get isRejected => status == OutboxStatus.rejected;

  /// Counts toward what the gate shows (pending or acknowledged but not yet in a pulled state).
  bool get isLive => status != OutboxStatus.rejected;

  /// The id the server answers with in accepted, duplicates and rejected: the record's `id`,
  /// except `guard_id` for pins and `item_id` for rollup checks. Usually the same as [id]; a
  /// shift's end is queued as a second item (`<shift id>:end`) with the shift's id here.
  String get serverId => switch (kind) {
        OutboxKind.pin => payload['guard_id'] as String,
        OutboxKind.rollupCheck => payload['item_id'] as String,
        OutboxKind.directoryReport => id,
        _ => (payload['id'] as String?) ?? id,
      };

  factory OutboxItem.fromRow(OutboxRow r) => OutboxItem(
        id: r.itemId,
        kind: r.kind,
        payload: jsonDecode(r.payload) as Map<String, dynamic>,
        createdAt: r.createdAt,
        status: r.status,
        reason: r.reason,
        sentAt: r.sentAt,
        attempts: r.attempts,
      );
}

abstract final class MediaKind {
  static const clip = 'clip';
  static const visitor = 'visitor';
  static const plate = 'plate';
}

/// A clip or a photo to keep until it uploads.
class MediaItem {
  const MediaItem({required this.id, required this.kind, required this.bytes, required this.contentType, required this.createdAt, this.ref});
  final String id;
  final String kind;
  final List<int> bytes;
  final String contentType;
  final String? ref;
  final DateTime createdAt;

  /// Never print the bytes.
  @override
  String toString() => 'MediaItem($id, $kind, ${bytes.length} bytes)';
}

class MediaInfo {
  const MediaInfo({required this.id, required this.kind, required this.contentType, required this.createdAt, this.ref, this.attempts = 0});
  final String id;
  final String kind;
  final String contentType;
  final String? ref;
  final DateTime createdAt;
  final int attempts;
}

/// Local persistence: the last state snapshot, small meta values, and the outbox.
class GateStore {
  GateStore(this.db);
  final GateDatabase db;

  // --- meta -------------------------------------------------------------------------------

  Future<String?> meta(String key) async =>
      (await (db.select(db.metaTable)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setMeta(String key, String? value) async {
    if (value == null) {
      await (db.delete(db.metaTable)..where((t) => t.key.equals(key))).go();
    } else {
      await db.into(db.metaTable).insertOnConflictUpdate(MetaRow(key: key, value: value));
    }
  }

  // --- snapshot ---------------------------------------------------------------------------

  Future<void> saveSnapshot(StateSnapshot s) => db.transaction(() async {
        for (final TableInfo<Table, dynamic> t in [
          db.homesTable,
          db.residentsTable,
          db.numbersTable,
          db.visitsTable,
          db.directoryTable,
          db.gatesTable,
          db.guardsTable,
          db.vehiclesTable,
        ]) {
          await db.delete(t).go();
        }
        await db.batch((b) {
          b.insertAll(db.gatesTable, [for (final g in s.gates) GateRow(id: g.id, name: g.name)]);
          var gpos = 0;
          b.insertAll(db.guardsTable, [
            for (final g in s.guards)
              GuardRow(
                id: g.id,
                name: g.name,
                role: g.role,
                pinHash: g.pinHash,
                pinResetAt: g.pinResetAt?.toIso8601String(),
                consent: g.consent,
                position: gpos++,
              ),
          ]);
          b.insertAll(db.vehiclesTable, [
            for (final h in s.homes)
              for (final v in h.vehicles) VehiclesTableCompanion.insert(homeId: h.id, plate: v.plate, description: Value(v.description)),
          ]);
          b.insertAll(db.homesTable, [
            for (final h in s.homes)
              HomeRow(
                id: h.id,
                label: h.label,
                street: h.street,
                zone: h.zone,
                address: h.address,
                callbackRequired: h.callbackRequired,
                houseCodeHash: h.houseCodeHash,
              ),
          ]);
          var pos = 0;
          b.insertAll(db.residentsTable, [
            for (final h in s.homes)
              for (final r in h.residents) ResidentRow(id: r.id, homeId: h.id, name: r.name, contactPref: r.contactPref, position: pos++),
          ]);
          b.insertAll(db.numbersTable, [
            for (final h in s.homes)
              for (final r in h.residents)
                for (final n in r.numbers) NumberRow(id: n.id, residentId: r.id, e164: n.e164, last4: n.last4, isPrimary: n.isPrimary),
          ]);
          b.insertAll(db.visitsTable, [
            for (final v in s.visits)
              VisitRow(
                id: v.id,
                homeId: v.homeId,
                residentId: v.residentId,
                guestName: v.guestName,
                windowStart: v.windowStart,
                windowEnd: v.windowEnd,
                keyVersion: v.keyVersion,
                codeIssued: v.codeIssued,
                source: v.source,
                state: v.state,
                expectedUntil: v.expectedUntil?.toIso8601String(),
                entryId: v.entryId,
                enteredAt: v.enteredAt?.toIso8601String(),
              ),
          ]);
          var dpos = 0;
          b.insertAll(db.directoryTable, [
            for (final d in s.directory)
              DirectoryRow(
                id: d.id,
                position: dpos++,
                category: d.category,
                name: d.name,
                number: d.number,
                verifiedAt: d.verifiedAt?.toIso8601String(),
                reportedNotWorking: d.reportedNotWorking,
              ),
          ]);
        });
        await setMeta('estate', jsonEncode(s.estate.toJson()));
        await setMeta('device', jsonEncode({'id': s.deviceId, 'gate_id': s.deviceGateId}));
        await setMeta('rollup', s.rollup == null ? null : jsonEncode(s.rollup!.toJson()));
        await setMeta('shuttle', s.shuttle == null ? null : jsonEncode(s.shuttle!.toJson()));
        await setMeta('on_duty', jsonEncode([for (final d in s.onDuty) d.toJson()]));
      });

  Future<StateSnapshot?> loadSnapshot() async {
    final estateRaw = await meta('estate');
    final deviceRaw = await meta('device');
    if (estateRaw == null || deviceRaw == null) return null;
    final device = jsonDecode(deviceRaw) as Map<String, dynamic>;
    final rollupRaw = await meta('rollup');
    final shuttleRaw = await meta('shuttle');
    // A list of open shifts. Anything else (nothing yet, or the map an older build kept here) is none.
    final onDutyRaw = await meta('on_duty');
    var onDuty = const <DutyShift>[];
    try {
      if (onDutyRaw != null) onDuty = DutyShift.listFromJson(jsonDecode(onDutyRaw));
    } on FormatException {
      onDuty = const [];
    }

    final numbers = await db.select(db.numbersTable).get();
    final numbersByResident = <String, List<PhoneNumber>>{};
    for (final n in numbers) {
      numbersByResident.putIfAbsent(n.residentId, () => []).add(PhoneNumber(id: n.id, e164: n.e164, last4: n.last4, isPrimary: n.isPrimary));
    }
    for (final list in numbersByResident.values) {
      list.sort((a, b) => (b.isPrimary ? 1 : 0) - (a.isPrimary ? 1 : 0));
    }
    final residents = await (db.select(db.residentsTable)..orderBy([(t) => OrderingTerm(expression: t.position)])).get();
    final residentsByHome = <String, List<Resident>>{};
    for (final r in residents) {
      residentsByHome
          .putIfAbsent(r.homeId, () => [])
          .add(Resident(id: r.id, homeId: r.homeId, name: r.name, contactPref: r.contactPref, numbers: numbersByResident[r.id] ?? const []));
    }
    DateTime? dt(String? s) => s == null ? null : DateTime.parse(s);
    final vehiclesByHome = <String, List<Vehicle>>{};
    for (final v in await (db.select(db.vehiclesTable)..orderBy([(t) => OrderingTerm(expression: t.seq)])).get()) {
      vehiclesByHome.putIfAbsent(v.homeId, () => []).add(Vehicle(plate: v.plate, description: v.description));
    }

    return StateSnapshot(
      estate: Estate.fromJson(jsonDecode(estateRaw) as Map<String, dynamic>),
      deviceId: device['id'] as String,
      deviceGateId: device['gate_id'] as String,
      gates: [for (final g in await db.select(db.gatesTable).get()) Gate(g.id, g.name)],
      guards: [
        for (final g in await (db.select(db.guardsTable)..orderBy([(t) => OrderingTerm(expression: t.position)])).get())
          Guard(g.id, g.name, role: g.role, pinHash: g.pinHash, pinResetAt: dt(g.pinResetAt), consent: g.consent),
      ],
      homes: [
        for (final h in await db.select(db.homesTable).get())
          Home(
            id: h.id,
            label: h.label,
            street: h.street,
            zone: h.zone,
            address: h.address,
            callbackRequired: h.callbackRequired,
            residents: residentsByHome[h.id] ?? const [],
            vehicles: vehiclesByHome[h.id] ?? const [],
            houseCodeHash: h.houseCodeHash,
          ),
      ],
      visits: [
        for (final v in await db.select(db.visitsTable).get())
          Visit(
            id: v.id,
            homeId: v.homeId,
            residentId: v.residentId,
            guestName: v.guestName,
            windowStart: v.windowStart,
            windowEnd: v.windowEnd,
            keyVersion: v.keyVersion,
            codeIssued: v.codeIssued,
            source: v.source,
            state: v.state,
            expectedUntil: dt(v.expectedUntil),
            entryId: v.entryId,
            enteredAt: dt(v.enteredAt),
          ),
      ],
      rollup: rollupRaw == null ? null : Rollup.fromJson(jsonDecode(rollupRaw) as Map<String, dynamic>),
      directory: [
        for (final d in await (db.select(db.directoryTable)..orderBy([(t) => OrderingTerm(expression: t.position)])).get())
          DirectoryEntry(
            id: d.id,
            category: d.category,
            name: d.name,
            number: d.number,
            verifiedAt: dt(d.verifiedAt),
            reportedNotWorking: d.reportedNotWorking,
          ),
      ],
      shuttle: shuttleRaw == null ? null : ShuttleState.fromJson(jsonDecode(shuttleRaw) as Map<String, dynamic>),
      onDuty: onDuty,
    );
  }

  // --- outbox -----------------------------------------------------------------------------

  /// Queues a record. Returns false if an item with this id is already queued.
  Future<bool> enqueue(String kind, String id, Map<String, dynamic> payload, {DateTime? at}) => db.transaction(() async {
        final exists = await (db.select(db.outboxTable)..where((t) => t.itemId.equals(id))).getSingleOrNull();
        if (exists != null) return false;
        await db.into(db.outboxTable).insert(
              OutboxTableCompanion.insert(itemId: id, kind: kind, payload: jsonEncode(payload), createdAt: at ?? DateTime.now()),
            );
        return true;
      });

  /// Queues a record again with a new payload, at the back of the queue, whether or not it was
  /// already sent or purged. The server fills in what the first copy left out (a confirmed
  /// call's visit) and treats the rest as a duplicate.
  Future<void> requeue(String kind, String id, Map<String, dynamic> payload, {DateTime? at}) => db.transaction(() async {
        await (db.delete(db.outboxTable)..where((t) => t.itemId.equals(id))).go();
        await db.into(db.outboxTable).insert(
              OutboxTableCompanion.insert(itemId: id, kind: kind, payload: jsonEncode(payload), createdAt: at ?? DateTime.now()),
            );
      });

  Future<List<OutboxItem>> outbox({String? status}) async {
    final q = db.select(db.outboxTable)..orderBy([(t) => OrderingTerm(expression: t.seq)]);
    if (status != null) q.where((t) => t.status.equals(status));
    return [for (final r in await q.get()) OutboxItem.fromRow(r)];
  }

  Future<void> markSent(Iterable<String> ids, DateTime at) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (db.update(db.outboxTable)..where((t) => t.itemId.isIn(list) & t.status.equals(OutboxStatus.pending)))
        .write(OutboxTableCompanion(status: const Value(OutboxStatus.sent), sentAt: Value(at), reason: const Value(null)));
  }

  Future<void> markRejected(String id, String reason) async {
    await (db.update(db.outboxTable)..where((t) => t.itemId.equals(id)))
        .write(OutboxTableCompanion(status: const Value(OutboxStatus.rejected), reason: Value(reason)));
  }

  Future<void> bumpAttempts(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await db.customUpdate(
      'UPDATE outbox SET attempts = attempts + 1 WHERE item_id IN (${List.filled(list.length, '?').join(',')})',
      variables: [for (final id in list) Variable.withString(id)],
      updates: {db.outboxTable},
    );
  }

  Future<void> deleteItems(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (db.delete(db.outboxTable)..where((t) => t.itemId.isIn(list))).go();
  }

  /// True while the item has not been sent yet.
  Future<bool> isPending(String id) async =>
      (await (db.select(db.outboxTable)..where((t) => t.itemId.equals(id) & t.status.equals(OutboxStatus.pending))).getSingleOrNull()) != null;

  /// Removes a queued item only if it has not been sent yet (used by Undo).
  Future<bool> cancelPending(String id) async =>
      await (db.delete(db.outboxTable)..where((t) => t.itemId.equals(id) & t.status.equals(OutboxStatus.pending))).go() > 0;

  // --- selfies ----------------------------------------------------------------------------

  Future<void> saveSelfie(String shiftId, List<int> jpeg, DateTime at) =>
      db.into(db.selfiesTable).insertOnConflictUpdate(SelfieRow(shiftId: shiftId, jpeg: Uint8List.fromList(jpeg), createdAt: at, attempts: 0));

  /// Shift ids with a selfie waiting to upload, oldest first. The bytes are read one at a time.
  Future<List<String>> selfieShiftIds() async =>
      [for (final r in await (db.select(db.selfiesTable)..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get()) r.shiftId];

  Future<Uint8List?> selfie(String shiftId) async =>
      (await (db.select(db.selfiesTable)..where((t) => t.shiftId.equals(shiftId))).getSingleOrNull())?.jpeg;

  Future<void> bumpSelfieAttempts(String shiftId) => db.customUpdate(
        'UPDATE selfies SET attempts = attempts + 1 WHERE shift_id = ?',
        variables: [Variable.withString(shiftId)],
        updates: {db.selfiesTable},
      );

  Future<void> deleteSelfie(String shiftId) => (db.delete(db.selfiesTable)..where((t) => t.shiftId.equals(shiftId))).go();

  // --- voice clips and gate photos --------------------------------------------------------

  Future<void> saveMedia(MediaItem m) => db.into(db.mediaTable).insertOnConflictUpdate(
        MediaRow(id: m.id, kind: m.kind, bytes: Uint8List.fromList(m.bytes), contentType: m.contentType, ref: m.ref, createdAt: m.createdAt, attempts: 0),
      );

  /// What waits to upload, oldest first, without the bytes (read one at a time).
  Future<List<MediaInfo>> mediaWaiting() async {
    final t = db.mediaTable;
    final q = db.selectOnly(t)
      ..addColumns([t.id, t.kind, t.contentType, t.ref, t.createdAt, t.attempts])
      ..orderBy([OrderingTerm(expression: t.createdAt)]);
    return [
      for (final r in await q.get())
        MediaInfo(
          id: r.read(t.id)!,
          kind: r.read(t.kind)!,
          contentType: r.read(t.contentType)!,
          ref: r.read(t.ref),
          createdAt: r.read(t.createdAt)!,
          attempts: r.read(t.attempts) ?? 0,
        ),
    ];
  }

  Future<Uint8List?> mediaBytes(String id) async => (await (db.select(db.mediaTable)..where((t) => t.id.equals(id))).getSingleOrNull())?.bytes;

  /// The voice clip still on the phone for a record (an entry or a visit), if any.
  /// Record id -> the id of its voice clip, for clips still on the phone.
  Future<Map<String, String>> clipRefs() async => {
        for (final m in await mediaWaiting())
          if (m.kind == MediaKind.clip && m.ref != null) m.ref!: m.id,
      };

  /// Deletes what a record named, if it has not uploaded yet (Undo).
  Future<void> deleteMediaFor(String ref) => (db.delete(db.mediaTable)..where((t) => t.ref.equals(ref))).go();

  Future<void> bumpMediaAttempts(String id) => db.customUpdate(
        'UPDATE media SET attempts = attempts + 1 WHERE id = ?',
        variables: [Variable.withString(id)],
        updates: {db.mediaTable},
      );

  Future<void> deleteMedia(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (db.delete(db.mediaTable)..where((t) => t.id.isIn(list))).go();
  }

  // --- rider positions --------------------------------------------------------------------

  Future<void> addPosition(String shiftId, PositionFix p) => db.into(db.positionsTable).insert(PositionsTableCompanion.insert(
        shiftId: shiftId,
        lat: p.lat,
        lng: p.lng,
        accuracyM: Value(p.accuracyM),
        heading: Value(p.heading),
        speed: Value(p.speed),
        at: p.at,
      ));

  /// Queued positions, oldest first.
  Future<List<QueuedPosition>> positions({int? limit}) async {
    final q = db.select(db.positionsTable)..orderBy([(t) => OrderingTerm(expression: t.seq)]);
    if (limit != null) q.limit(limit);
    return [
      for (final r in await q.get())
        QueuedPosition(r.seq, r.shiftId, PositionFix(lat: r.lat, lng: r.lng, accuracyM: r.accuracyM, heading: r.heading, speed: r.speed, at: r.at)),
    ];
  }

  Future<int> positionCount() async => (await db.select(db.positionsTable).get()).length;

  Future<void> deletePositions(Iterable<int> seqs) async {
    final list = seqs.toList();
    if (list.isEmpty) return;
    await (db.delete(db.positionsTable)..where((t) => t.seq.isIn(list))).go();
  }

  Future<void> deletePositionsForShift(String shiftId) => (db.delete(db.positionsTable)..where((t) => t.shiftId.equals(shiftId))).go();

  /// Keeps the last 2 hours at most.
  Future<void> trimPositions(DateTime before) => (db.delete(db.positionsTable)..where((t) => t.at.isSmallerThanValue(before))).go();

  /// 401: the phone was revoked or re-paired. Forget everything.
  Future<void> wipe() => db.transaction(() async {
        for (final t in db.allTables) {
          await db.delete(t).go();
        }
      });
}
