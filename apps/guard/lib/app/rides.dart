import '../data/models.dart';
import '../data/shuttle.dart';
import '../data/store.dart';

/// Who rode, recorded on a pickup (or on a parcel's drop-off).
class RideConfirm {
  const RideConfirm._(this.by, {this.residentId, this.cardId});

  /// The resident's estate card, looked up offline in `shuttle.cards`.
  const RideConfirm.card({required String cardId, required String residentId}) : this._('card', residentId: residentId, cardId: cardId);

  /// The home's 4 digits, checked offline. [residentId] if the rider picked who it was.
  const RideConfirm.houseCode({String? residentId}) : this._('house_code', residentId: residentId);

  /// A gate booking the guard handed over.
  const RideConfirm.guard() : this._('guard');

  /// The rider vouches.
  const RideConfirm.rider({String? residentId}) : this._('rider', residentId: residentId);

  /// card | house_code | guard | rider
  final String by;
  final String? residentId;
  final String? cardId;

  Map<String, dynamic> toJson() => {'confirmed_by': by, 'resident_id': residentId, 'card_id': cardId};
}

/// The rides the phone knows about: the last pulled `shuttle.rides` with this phone's ride
/// records and ride events laid over them, so a ride taken or dropped off a moment ago shows
/// that way with no network. Each step is idempotent, so an event the server already has
/// changes nothing.
class RideView {
  const RideView._(this.open);

  /// Open rides (requested, accepted, picked up), soonest first.
  final List<Ride> open;

  static const empty = RideView._([]);

  Ride? ride(String id) => open.where((r) => r.id == id).firstOrNull;

  /// Waiting for a rider, soonest first. [hidden]: rides this rider lost to another ("taken by").
  List<Ride> waiting({Set<String> hidden = const {}}) => [for (final r in open) if (r.isRequested && !hidden.contains(r.id)) r];

  /// The rider's own rides: taken, or under way.
  List<Ride> mine(String? riderId) => [for (final r in open) if (riderId != null && !r.isRequested && r.riderId == riderId) r];

  factory RideView.build(StateSnapshot? snap, List<OutboxItem> outbox) {
    final shuttle = snap?.shuttle;
    if (shuttle == null) return empty;
    final rides = <String, Ride>{for (final r in shuttle.rides) r.id: r};
    final order = <String>[for (final r in shuttle.rides) r.id];
    final live = outbox.where((i) => i.isLive);
    DateTime? dt(Object? s) => s == null ? null : DateTime.tryParse(s as String);

    // Rides booked on this phone (at the gate, flagged down, by the CSO).
    for (final i in live.where((i) => i.kind == OutboxKind.ride)) {
      final p = i.payload;
      final id = (p['id'] as String).toLowerCase();
      if (rides.containsKey(id)) continue;
      rides[id] = Ride(
        id: id,
        kind: p['kind'] as String,
        source: p['source'] as String,
        state: RideState.requested,
        homeId: p['home_id'] as String,
        residentId: p['resident_id'] as String?,
        passenger: p['passenger'] as String?,
        pickup: stopFor(snap, p['pickup'] as Map<String, dynamic>),
        dropoff: stopFor(snap, p['dropoff'] as Map<String, dynamic>),
        wantedAt: dt(p['wanted_at']) ?? dt(p['at']),
        note: p['note'] as String?,
        createdAt: dt(p['at']),
      );
      order.add(id);
    }

    // What happened to them, in the order it happened on this phone.
    for (final i in live.where((i) => i.kind == OutboxKind.rideEvent)) {
      final p = i.payload;
      final id = (p['ride_id'] as String).toLowerCase();
      final r = rides[id];
      if (r == null) continue;
      final by = p['guard_id'] as String?;
      final name = snap?.guard(by)?.name;
      final at = dt(p['at']);
      switch (p['event']) {
        case 'accept':
          if (r.isRequested) rides[id] = r.copyWith(state: RideState.accepted, riderId: by, rider: name, acceptedAt: at);
        case 'release':
          if (r.state == RideState.accepted && r.riderId == by) rides[id] = r.copyWith(state: RideState.requested, clearRider: true);
        case 'pick_up':
          if (r.state != RideState.pickedUp) rides[id] = r.copyWith(state: RideState.pickedUp, riderId: by, rider: name, pickedUpAt: at);
        case 'drop_off' || 'no_show' || 'cancel':
          rides.remove(id);
      }
    }

    final open = [for (final id in order) ?rides[id]];
    open.sort((a, b) => (a.wantedAt ?? DateTime(0)).compareTo(b.wantedAt ?? DateTime(0)));
    return RideView._(open);
  }

  /// A ride end as the sync body names it, labelled from the cached state.
  static RideStop stopFor(StateSnapshot? snap, Map<String, dynamic> ref) {
    final kind = ref['kind'] as String;
    final id = ref['ref'] as String?;
    final label = switch (kind) {
      'home' => snap?.home(id ?? '')?.displayAddress,
      'gate' => snap?.gateName(id),
      'place' => snap?.shuttle?.place(id)?.name,
      _ => null,
    };
    return RideStop(kind: kind, ref: id, label: label ?? kind);
  }
}

/// Words for a ride's kind, as the rider reads them.
String rideKindLabel(String kind) => switch (kind) {
      RideKind.delivery => 'Parcel',
      RideKind.guest => 'Guest',
      _ => 'Resident',
    };

/// "Waiting 12 min", "Waiting 1 h 5 min", "Wanted at 16:00" (with [hhmm] for future times).
String waitLabel(DateTime? wantedAt, DateTime now, String Function(DateTime) hhmm) {
  if (wantedAt == null) return 'Waiting';
  final d = now.difference(wantedAt);
  if (d.inMinutes < 0) return 'Wanted at ${hhmm(wantedAt)}';
  final m = d.inMinutes;
  if (m < 1) return 'Just now';
  if (m < 60) return 'Waiting $m min';
  return 'Waiting ${m ~/ 60} h ${m % 60} min';
}

/// The stops a ride can use: the home first, then gates, then estate places.
List<RideStop> rideStops(StateSnapshot snap, {Home? home}) => [
      if (home != null) RideStop(kind: 'home', ref: home.id, label: home.displayAddress),
      for (final g in snap.gates) RideStop(kind: 'gate', ref: g.id, label: g.name),
      for (final p in snap.shuttle?.places ?? const <EstatePlace>[]) RideStop(kind: 'place', ref: p.id, label: p.name),
    ];
