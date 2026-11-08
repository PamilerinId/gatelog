import '../data/models.dart';
import '../data/store.dart';

/// Someone inside the estate right now, as far as this phone knows.
class InsideGuest {
  const InsideGuest({required this.homeId, required this.guestName, this.visitId, this.entryId, this.enteredAt, this.expectedUntil, this.overstay = false});
  final String homeId;
  final String guestName;
  final String? visitId;
  final String? entryId;
  final DateTime? enteredAt;
  final DateTime? expectedUntil;
  final bool overstay;
}

/// The last pulled state with this phone's not-yet-reflected records laid over it, so the
/// gate is right while offline: a guest admitted a minute ago is inside, one who left is not.
/// Each overlay step is idempotent, so a record the server already has changes nothing.
class GateView {
  GateView._({
    required this.visits,
    required this.inside,
    required this.expected,
    required this.expectedByPhone,
    required this.rollupResults,
    required this.localPins,
    required this.reportedNumbers,
    required this.needsAttention,
    required this.queued,
  });

  /// visit id -> visit, including visits created on this phone and local state changes.
  final Map<String, Visit> visits;
  final List<InsideGuest> inside;

  /// Every guest expected and not yet in (coded or confirmed by phone), soonest first.
  final List<Visit> expected;

  /// Phone-announced visits waiting at the gate (confirmed by callback, "Coming later").
  final List<Visit> expectedByPhone;

  /// PIN hashes set on this phone and not yet replaced by a pulled state: guard id -> hash.
  /// They win over the state's `pin_hash` until they sync. A rejected one does not count.
  final Map<String, String> localPins;

  /// rollup item id -> left | still_inside
  final Map<String, String> rollupResults;

  /// directory entry ids reported as not working from this phone.
  final Set<String> reportedNumbers;
  final List<OutboxItem> needsAttention;

  /// Records not yet accepted by the server.
  final int queued;

  /// Phone-announced guests already confirmed for [homeId] ("Already confirmed" in No code).
  List<Visit> confirmedFor(String homeId) => [for (final v in expectedByPhone) if (v.homeId == homeId) v];

  /// Night list items nobody has checked yet.
  int nightListOpen(Rollup? rollup) => rollup == null ? 0 : rollup.items.where((i) => !rollupResults.containsKey(i.id)).length;

  static final empty = GateView._(
    visits: const {},
    inside: const [],
    expected: const [],
    expectedByPhone: const [],
    rollupResults: const {},
    localPins: const {},
    reportedNumbers: const {},
    needsAttention: const [],
    queued: 0,
  );

  factory GateView.build(StateSnapshot? snap, List<OutboxItem> outbox) {
    final visits = <String, Visit>{for (final v in snap?.visits ?? const <Visit>[]) v.id: v};
    final live = outbox.where((i) => i.isLive).toList();
    DateTime? dt(Object? s) => s == null ? null : DateTime.tryParse(s as String);

    // Visits created here (flow A).
    for (final i in live.where((i) => i.kind == OutboxKind.visit)) {
      final p = i.payload;
      final id = (p['id'] as String).toLowerCase();
      visits.putIfAbsent(
        id,
        () => Visit(
          id: id,
          homeId: p['home_id'] as String,
          residentId: p['resident_id'] as String?,
          guestName: p['guest_name'] as String,
          windowStart: dt(p['window_start'])!.millisecondsSinceEpoch ~/ 1000,
          windowEnd: dt(p['window_end'])!.millisecondsSinceEpoch ~/ 1000,
          keyVersion: null,
          codeIssued: false,
          source: 'phone_announced',
          state: 'expected',
          expectedUntil: dt(p['expected_until']),
          entryId: null,
          enteredAt: null,
        ),
      );
    }

    // Entries. Ones with a visit move it inside. Ones without (flow B) show as walk-ins until
    // the server's visit for them arrives in the state, carrying this entry's id.
    final serverEntryIds = {for (final v in visits.values) if (v.entryId != null) v.entryId!};
    final walkIns = <String, InsideGuest>{};
    for (final i in live.where((i) => i.kind == OutboxKind.entry)) {
      if (serverEntryIds.contains(i.id)) continue;
      final p = i.payload;
      if (p['method'] == 'refused') continue;
      final visitId = (p['visit_id'] as String?)?.toLowerCase();
      final v = visitId == null ? null : visits[visitId];
      if (v != null) {
        if (v.state == 'expected') visits[v.id] = v.copyWith(state: 'inside', entryId: i.id, enteredAt: dt(p['at']));
      } else if (visitId == null) {
        walkIns[i.id] = InsideGuest(homeId: p['home_id'] as String, guestName: p['guest_name'] as String, entryId: i.id, enteredAt: dt(p['at']));
      }
    }

    // Exits close the visit (by visit id or entry id) or the walk-in.
    for (final i in live.where((i) => i.kind == OutboxKind.exit)) {
      final p = i.payload;
      final visitId = (p['visit_id'] as String?)?.toLowerCase();
      final entryId = p['entry_id'] as String?;
      if (entryId != null) walkIns.remove(entryId);
      for (final v in visits.values.toList()) {
        if ((visitId != null && v.id == visitId) || (entryId != null && v.entryId == entryId)) {
          visits[v.id] = v.copyWith(state: 'left');
        }
      }
    }

    // Night list checks marked here.
    final rollupResults = <String, String>{
      for (final item in snap?.rollup?.items ?? const <RollupItem>[])
        if (item.checkResult != null) item.id: item.checkResult!,
    };
    for (final i in live.where((i) => i.kind == OutboxKind.rollupCheck)) {
      rollupResults[i.id] = i.payload['result'] as String;
      if (i.payload['result'] == 'left') {
        final item = snap?.rollup?.items.where((r) => r.id == i.id).firstOrNull;
        final v = item == null ? null : visits[item.visitId];
        if (v != null && v.isInside) visits[v.id] = v.copyWith(state: 'left');
      }
    }

    String homeKey(String homeId) => snap?.home(homeId)?.displayAddress.toLowerCase() ?? homeId;
    final inside = [
      for (final v in visits.values)
        if (v.isInside)
          InsideGuest(
            homeId: v.homeId,
            guestName: v.guestName,
            visitId: v.id,
            entryId: v.entryId,
            enteredAt: v.enteredAt,
            expectedUntil: v.expectedUntil,
            overstay: v.state == 'overstay',
          ),
      ...walkIns.values,
    ]..sort((a, b) {
        final c = _natural(homeKey(a.homeId), homeKey(b.homeId));
        return c != 0 ? c : a.guestName.toLowerCase().compareTo(b.guestName.toLowerCase());
      });

    final expected = [
      for (final v in visits.values)
        if (v.state == 'expected') v,
    ]..sort((a, b) => a.windowStart.compareTo(b.windowStart));
    final expectedByPhone = [
      for (final v in expected)
        if (!v.codeIssued && v.source == 'phone_announced') v,
    ];

    return GateView._(
      visits: visits,
      inside: inside,
      expected: expected,
      expectedByPhone: expectedByPhone,
      rollupResults: rollupResults,
      localPins: {
        for (final i in live.where((i) => i.kind == OutboxKind.pin)) i.payload['guard_id'] as String: i.payload['pin_hash'] as String,
      },
      reportedNumbers: {for (final i in live.where((i) => i.kind == OutboxKind.directoryReport)) i.payload['entry_id'] as String},
      needsAttention: outbox.where((i) => i.isRejected).toList(),
      queued: outbox.where((i) => i.isPending).length,
    );
  }
}

/// "2 Adeniyi" before "10 Adeniyi": compare digit runs by value.
int _natural(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final pa = re.allMatches(a).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = int.tryParse(pa[i]), y = int.tryParse(pb[i]);
    final c = (x != null && y != null) ? x.compareTo(y) : pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

int compareHomes(Home a, Home b) => _natural(a.displayAddress.toLowerCase(), b.displayAddress.toLowerCase());
