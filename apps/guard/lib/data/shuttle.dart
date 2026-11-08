/// The estate shuttle, as `/v1/device/state` sends it in `shuttle` (null when the estate runs
/// none, and then nothing about the shuttle shows). See the contract, "The estate shuttle".
///
/// Card hashes are kept in the encrypted database with the rest of the state. Raw card UIDs
/// and house codes are never stored, shown or logged.
library;

DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v as String);
double? _num(Object? v) => (v as num?)?.toDouble();
List<Map<String, dynamic>> _list(Object? v) => [for (final i in (v as List? ?? const [])) i as Map<String, dynamic>];

/// One of the estate's motorcycles.
class ShuttleBike {
  const ShuttleBike({required this.id, required this.label, this.plate});
  final String id;
  final String label;
  final String? plate;

  factory ShuttleBike.fromJson(Map<String, dynamic> j) => ShuttleBike(id: j['id'] as String, label: j['label'] as String, plate: j['plate'] as String?);
  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'plate': plate};
}

/// An estate place a ride can start or end at (clubhouse, mosque, market).
class EstatePlace {
  const EstatePlace({required this.id, required this.name, this.kind, this.lat, this.lng});
  final String id;
  final String name;
  final String? kind;
  final double? lat;
  final double? lng;

  factory EstatePlace.fromJson(Map<String, dynamic> j) =>
      EstatePlace(id: j['id'] as String, name: j['name'] as String, kind: j['kind'] as String?, lat: _num(j['lat']), lng: _num(j['lng']));
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'kind': kind, 'lat': lat, 'lng': lng};
}

/// A resident's estate card. Only the hash of its UID is known here.
class EstateCard {
  const EstateCard({required this.id, required this.uidHash, required this.residentId, required this.homeId, this.uidLast4});
  final String id;
  final String uidHash;
  final String residentId;
  final String homeId;
  final String? uidLast4;

  @override
  String toString() => 'EstateCard($id)';

  factory EstateCard.fromJson(Map<String, dynamic> j) => EstateCard(
        id: j['id'] as String,
        uidHash: (j['uid_hash'] as String).toLowerCase(),
        residentId: j['resident_id'] as String,
        homeId: j['home_id'] as String,
        uidLast4: j['uid_last4'] as String?,
      );
  Map<String, dynamic> toJson() => {'id': id, 'uid_hash': uidHash, 'resident_id': residentId, 'home_id': homeId, 'uid_last4': uidLast4};
}

/// Where a ride starts or ends: a home, a gate or an estate place.
class RideStop {
  const RideStop({required this.kind, required this.ref, required this.label, this.lat, this.lng});
  final String kind; // home | gate | place
  final String? ref;
  final String label;
  final double? lat;
  final double? lng;

  bool sameAs(RideStop o) => kind == o.kind && ref == o.ref;

  /// What the sync body carries.
  Map<String, dynamic> toRef() => {'kind': kind, 'ref': ref};

  factory RideStop.fromJson(Map<String, dynamic> j) => RideStop(
        kind: j['kind'] as String,
        ref: j['ref'] as String?,
        label: (j['label'] as String?) ?? '',
        lat: _num(j['lat']),
        lng: _num(j['lng']),
      );
  Map<String, dynamic> toJson() => {'kind': kind, 'ref': ref, 'label': label, 'lat': lat, 'lng': lng};
}

abstract final class RideKind {
  static const resident = 'resident';
  static const delivery = 'delivery';
  static const guest = 'guest';
}

abstract final class RideState {
  static const requested = 'requested';
  static const accepted = 'accepted';
  static const pickedUp = 'picked_up';
}

class Ride {
  const Ride({
    required this.id,
    required this.kind,
    required this.source,
    required this.state,
    required this.homeId,
    required this.pickup,
    required this.dropoff,
    this.residentId,
    this.passenger,
    this.wantedAt,
    this.note,
    this.riderId,
    this.rider,
    this.shuttleId,
    this.acceptedAt,
    this.pickedUpAt,
    this.createdAt,
  });

  final String id;

  /// resident | delivery | guest
  final String kind;

  /// whatsapp | sms | gate | flag | dispatch
  final String source;

  /// requested | accepted | picked_up (only open rides are sent)
  final String state;
  final String homeId;
  final String? residentId;

  /// The guest's name, or what the parcel is.
  final String? passenger;
  final RideStop pickup;
  final RideStop dropoff;
  final DateTime? wantedAt;
  final String? note;
  final String? riderId;
  final String? rider;
  final String? shuttleId;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? createdAt;

  bool get isDelivery => kind == RideKind.delivery;
  bool get isRequested => state == RideState.requested;

  Ride copyWith({required String state, String? riderId, String? rider, bool clearRider = false, DateTime? acceptedAt, DateTime? pickedUpAt}) => Ride(
        id: id,
        kind: kind,
        source: source,
        state: state,
        homeId: homeId,
        residentId: residentId,
        passenger: passenger,
        pickup: pickup,
        dropoff: dropoff,
        wantedAt: wantedAt,
        note: note,
        riderId: clearRider ? null : (riderId ?? this.riderId),
        rider: clearRider ? null : (rider ?? this.rider),
        shuttleId: clearRider ? null : shuttleId,
        acceptedAt: clearRider ? null : (acceptedAt ?? this.acceptedAt),
        pickedUpAt: pickedUpAt ?? this.pickedUpAt,
        createdAt: createdAt,
      );

  factory Ride.fromJson(Map<String, dynamic> j) => Ride(
        id: (j['id'] as String).toLowerCase(),
        kind: (j['kind'] as String?) ?? RideKind.resident,
        source: (j['source'] as String?) ?? '',
        state: (j['state'] as String?) ?? RideState.requested,
        homeId: (j['home_id'] as String).toLowerCase(),
        residentId: j['resident_id'] as String?,
        passenger: j['passenger'] as String?,
        pickup: RideStop.fromJson(j['pickup'] as Map<String, dynamic>),
        dropoff: RideStop.fromJson(j['dropoff'] as Map<String, dynamic>),
        wantedAt: _dt(j['wanted_at']),
        note: j['note'] as String?,
        riderId: j['rider_id'] as String?,
        rider: j['rider'] as String?,
        shuttleId: j['shuttle_id'] as String?,
        acceptedAt: _dt(j['accepted_at']),
        pickedUpAt: _dt(j['picked_up_at']),
        createdAt: _dt(j['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'source': source,
        'state': state,
        'home_id': homeId,
        'resident_id': residentId,
        'passenger': passenger,
        'pickup': pickup.toJson(),
        'dropoff': dropoff.toJson(),
        'wanted_at': wantedAt?.toIso8601String(),
        'note': note,
        'rider_id': riderId,
        'rider': rider,
        'shuttle_id': shuttleId,
        'accepted_at': acceptedAt?.toIso8601String(),
        'picked_up_at': pickedUpAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
      };
}

/// `state.shuttle`.
class ShuttleState {
  const ShuttleState({this.shuttles = const [], this.places = const [], this.cards = const [], this.rides = const []});
  final List<ShuttleBike> shuttles;
  final List<EstatePlace> places;
  final List<EstateCard> cards;

  /// Open rides wanted within the next 24 hours, soonest first.
  final List<Ride> rides;

  ShuttleBike? bike(String? id) => shuttles.where((s) => s.id == id).firstOrNull;
  EstatePlace? place(String? id) => places.where((p) => p.id == id).firstOrNull;
  EstateCard? cardByHash(String hash) => cards.where((c) => c.uidHash == hash.toLowerCase()).firstOrNull;

  factory ShuttleState.fromJson(Map<String, dynamic> j) => ShuttleState(
        shuttles: [for (final s in _list(j['shuttles'])) ShuttleBike.fromJson(s)],
        places: [for (final p in _list(j['places'])) EstatePlace.fromJson(p)],
        cards: [for (final c in _list(j['cards'])) EstateCard.fromJson(c)],
        rides: [for (final r in _list(j['rides'])) Ride.fromJson(r)],
      );

  Map<String, dynamic> toJson() => {
        'shuttles': [for (final s in shuttles) s.toJson()],
        'places': [for (final p in places) p.toJson()],
        'cards': [for (final c in cards) c.toJson()],
        'rides': [for (final r in rides) r.toJson()],
      };
}

/// One position fix from a rider's phone. Never logged: [toString] leaves out where.
class PositionFix {
  const PositionFix({required this.lat, required this.lng, required this.at, this.accuracyM, this.heading, this.speed});
  final double lat;
  final double lng;
  final double? accuracyM;
  final double? heading;
  final double? speed;
  final DateTime at;

  /// Values the server's validation would refuse are dropped, so one odd reading from the
  /// GPS cannot block the queue. Null if the fix itself is unusable.
  static PositionFix? clean({required double lat, required double lng, required DateTime at, double? accuracyM, double? heading, double? speed}) {
    if (lat.isNaN || lng.isNaN || lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    double? within(double? v, double lo, double hi) => v == null || v.isNaN || v < lo || v > hi ? null : v;
    return PositionFix(lat: lat, lng: lng, at: at, accuracyM: within(accuracyM, 0, 10000), heading: within(heading, 0, 360), speed: within(speed, 0, 100));
  }

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        if (accuracyM != null) 'accuracy_m': accuracyM,
        if (heading != null) 'heading': heading,
        if (speed != null) 'speed': speed,
        'at': at.toUtc().toIso8601String(),
      };

  @override
  String toString() => 'PositionFix(at $at)';
}

class QueuedPosition {
  const QueuedPosition(this.seq, this.shiftId, this.fix);
  final int seq;
  final String shiftId;
  final PositionFix fix;
}
