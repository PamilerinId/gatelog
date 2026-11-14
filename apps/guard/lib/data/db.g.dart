// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $HomesTableTable extends HomesTable
    with TableInfo<$HomesTableTable, HomeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HomesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _streetMeta = const VerificationMeta('street');
  @override
  late final GeneratedColumn<String> street = GeneratedColumn<String>(
    'street',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _zoneMeta = const VerificationMeta('zone');
  @override
  late final GeneratedColumn<String> zone = GeneratedColumn<String>(
    'zone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _callbackRequiredMeta = const VerificationMeta(
    'callbackRequired',
  );
  @override
  late final GeneratedColumn<bool> callbackRequired = GeneratedColumn<bool>(
    'callback_required',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("callback_required" IN (0, 1))',
    ),
  );
  static const VerificationMeta _houseCodeHashMeta = const VerificationMeta(
    'houseCodeHash',
  );
  @override
  late final GeneratedColumn<String> houseCodeHash = GeneratedColumn<String>(
    'house_code_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    label,
    street,
    zone,
    address,
    callbackRequired,
    houseCodeHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'homes';
  @override
  VerificationContext validateIntegrity(
    Insertable<HomeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('street')) {
      context.handle(
        _streetMeta,
        street.isAcceptableOrUnknown(data['street']!, _streetMeta),
      );
    } else if (isInserting) {
      context.missing(_streetMeta);
    }
    if (data.containsKey('zone')) {
      context.handle(
        _zoneMeta,
        zone.isAcceptableOrUnknown(data['zone']!, _zoneMeta),
      );
    } else if (isInserting) {
      context.missing(_zoneMeta);
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('callback_required')) {
      context.handle(
        _callbackRequiredMeta,
        callbackRequired.isAcceptableOrUnknown(
          data['callback_required']!,
          _callbackRequiredMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_callbackRequiredMeta);
    }
    if (data.containsKey('house_code_hash')) {
      context.handle(
        _houseCodeHashMeta,
        houseCodeHash.isAcceptableOrUnknown(
          data['house_code_hash']!,
          _houseCodeHashMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HomeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HomeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      street: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}street'],
      )!,
      zone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}zone'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      callbackRequired: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}callback_required'],
      )!,
      houseCodeHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}house_code_hash'],
      ),
    );
  }

  @override
  $HomesTableTable createAlias(String alias) {
    return $HomesTableTable(attachedDatabase, alias);
  }
}

class HomeRow extends DataClass implements Insertable<HomeRow> {
  final String id;
  final String label;
  final String street;
  final String zone;
  final String address;
  final bool callbackRequired;

  /// The shuttle house code's PBKDF2 hash (never the code). Null when none was asked for.
  final String? houseCodeHash;
  const HomeRow({
    required this.id,
    required this.label,
    required this.street,
    required this.zone,
    required this.address,
    required this.callbackRequired,
    this.houseCodeHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['label'] = Variable<String>(label);
    map['street'] = Variable<String>(street);
    map['zone'] = Variable<String>(zone);
    map['address'] = Variable<String>(address);
    map['callback_required'] = Variable<bool>(callbackRequired);
    if (!nullToAbsent || houseCodeHash != null) {
      map['house_code_hash'] = Variable<String>(houseCodeHash);
    }
    return map;
  }

  HomesTableCompanion toCompanion(bool nullToAbsent) {
    return HomesTableCompanion(
      id: Value(id),
      label: Value(label),
      street: Value(street),
      zone: Value(zone),
      address: Value(address),
      callbackRequired: Value(callbackRequired),
      houseCodeHash: houseCodeHash == null && nullToAbsent
          ? const Value.absent()
          : Value(houseCodeHash),
    );
  }

  factory HomeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HomeRow(
      id: serializer.fromJson<String>(json['id']),
      label: serializer.fromJson<String>(json['label']),
      street: serializer.fromJson<String>(json['street']),
      zone: serializer.fromJson<String>(json['zone']),
      address: serializer.fromJson<String>(json['address']),
      callbackRequired: serializer.fromJson<bool>(json['callbackRequired']),
      houseCodeHash: serializer.fromJson<String?>(json['houseCodeHash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'label': serializer.toJson<String>(label),
      'street': serializer.toJson<String>(street),
      'zone': serializer.toJson<String>(zone),
      'address': serializer.toJson<String>(address),
      'callbackRequired': serializer.toJson<bool>(callbackRequired),
      'houseCodeHash': serializer.toJson<String?>(houseCodeHash),
    };
  }

  HomeRow copyWith({
    String? id,
    String? label,
    String? street,
    String? zone,
    String? address,
    bool? callbackRequired,
    Value<String?> houseCodeHash = const Value.absent(),
  }) => HomeRow(
    id: id ?? this.id,
    label: label ?? this.label,
    street: street ?? this.street,
    zone: zone ?? this.zone,
    address: address ?? this.address,
    callbackRequired: callbackRequired ?? this.callbackRequired,
    houseCodeHash: houseCodeHash.present
        ? houseCodeHash.value
        : this.houseCodeHash,
  );
  HomeRow copyWithCompanion(HomesTableCompanion data) {
    return HomeRow(
      id: data.id.present ? data.id.value : this.id,
      label: data.label.present ? data.label.value : this.label,
      street: data.street.present ? data.street.value : this.street,
      zone: data.zone.present ? data.zone.value : this.zone,
      address: data.address.present ? data.address.value : this.address,
      callbackRequired: data.callbackRequired.present
          ? data.callbackRequired.value
          : this.callbackRequired,
      houseCodeHash: data.houseCodeHash.present
          ? data.houseCodeHash.value
          : this.houseCodeHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HomeRow(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('street: $street, ')
          ..write('zone: $zone, ')
          ..write('address: $address, ')
          ..write('callbackRequired: $callbackRequired, ')
          ..write('houseCodeHash: $houseCodeHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    label,
    street,
    zone,
    address,
    callbackRequired,
    houseCodeHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HomeRow &&
          other.id == this.id &&
          other.label == this.label &&
          other.street == this.street &&
          other.zone == this.zone &&
          other.address == this.address &&
          other.callbackRequired == this.callbackRequired &&
          other.houseCodeHash == this.houseCodeHash);
}

class HomesTableCompanion extends UpdateCompanion<HomeRow> {
  final Value<String> id;
  final Value<String> label;
  final Value<String> street;
  final Value<String> zone;
  final Value<String> address;
  final Value<bool> callbackRequired;
  final Value<String?> houseCodeHash;
  final Value<int> rowid;
  const HomesTableCompanion({
    this.id = const Value.absent(),
    this.label = const Value.absent(),
    this.street = const Value.absent(),
    this.zone = const Value.absent(),
    this.address = const Value.absent(),
    this.callbackRequired = const Value.absent(),
    this.houseCodeHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HomesTableCompanion.insert({
    required String id,
    required String label,
    required String street,
    required String zone,
    required String address,
    required bool callbackRequired,
    this.houseCodeHash = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       label = Value(label),
       street = Value(street),
       zone = Value(zone),
       address = Value(address),
       callbackRequired = Value(callbackRequired);
  static Insertable<HomeRow> custom({
    Expression<String>? id,
    Expression<String>? label,
    Expression<String>? street,
    Expression<String>? zone,
    Expression<String>? address,
    Expression<bool>? callbackRequired,
    Expression<String>? houseCodeHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (label != null) 'label': label,
      if (street != null) 'street': street,
      if (zone != null) 'zone': zone,
      if (address != null) 'address': address,
      if (callbackRequired != null) 'callback_required': callbackRequired,
      if (houseCodeHash != null) 'house_code_hash': houseCodeHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HomesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? label,
    Value<String>? street,
    Value<String>? zone,
    Value<String>? address,
    Value<bool>? callbackRequired,
    Value<String?>? houseCodeHash,
    Value<int>? rowid,
  }) {
    return HomesTableCompanion(
      id: id ?? this.id,
      label: label ?? this.label,
      street: street ?? this.street,
      zone: zone ?? this.zone,
      address: address ?? this.address,
      callbackRequired: callbackRequired ?? this.callbackRequired,
      houseCodeHash: houseCodeHash ?? this.houseCodeHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (street.present) {
      map['street'] = Variable<String>(street.value);
    }
    if (zone.present) {
      map['zone'] = Variable<String>(zone.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (callbackRequired.present) {
      map['callback_required'] = Variable<bool>(callbackRequired.value);
    }
    if (houseCodeHash.present) {
      map['house_code_hash'] = Variable<String>(houseCodeHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HomesTableCompanion(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('street: $street, ')
          ..write('zone: $zone, ')
          ..write('address: $address, ')
          ..write('callbackRequired: $callbackRequired, ')
          ..write('houseCodeHash: $houseCodeHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ResidentsTableTable extends ResidentsTable
    with TableInfo<$ResidentsTableTable, ResidentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ResidentsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _homeIdMeta = const VerificationMeta('homeId');
  @override
  late final GeneratedColumn<String> homeId = GeneratedColumn<String>(
    'home_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contactPrefMeta = const VerificationMeta(
    'contactPref',
  );
  @override
  late final GeneratedColumn<String> contactPref = GeneratedColumn<String>(
    'contact_pref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    homeId,
    name,
    contactPref,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'residents';
  @override
  VerificationContext validateIntegrity(
    Insertable<ResidentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('home_id')) {
      context.handle(
        _homeIdMeta,
        homeId.isAcceptableOrUnknown(data['home_id']!, _homeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_homeIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('contact_pref')) {
      context.handle(
        _contactPrefMeta,
        contactPref.isAcceptableOrUnknown(
          data['contact_pref']!,
          _contactPrefMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contactPrefMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ResidentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ResidentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      homeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}home_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      contactPref: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_pref'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $ResidentsTableTable createAlias(String alias) {
    return $ResidentsTableTable(attachedDatabase, alias);
  }
}

class ResidentRow extends DataClass implements Insertable<ResidentRow> {
  final String id;
  final String homeId;
  final String name;
  final String contactPref;
  final int position;
  const ResidentRow({
    required this.id,
    required this.homeId,
    required this.name,
    required this.contactPref,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['home_id'] = Variable<String>(homeId);
    map['name'] = Variable<String>(name);
    map['contact_pref'] = Variable<String>(contactPref);
    map['position'] = Variable<int>(position);
    return map;
  }

  ResidentsTableCompanion toCompanion(bool nullToAbsent) {
    return ResidentsTableCompanion(
      id: Value(id),
      homeId: Value(homeId),
      name: Value(name),
      contactPref: Value(contactPref),
      position: Value(position),
    );
  }

  factory ResidentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ResidentRow(
      id: serializer.fromJson<String>(json['id']),
      homeId: serializer.fromJson<String>(json['homeId']),
      name: serializer.fromJson<String>(json['name']),
      contactPref: serializer.fromJson<String>(json['contactPref']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'homeId': serializer.toJson<String>(homeId),
      'name': serializer.toJson<String>(name),
      'contactPref': serializer.toJson<String>(contactPref),
      'position': serializer.toJson<int>(position),
    };
  }

  ResidentRow copyWith({
    String? id,
    String? homeId,
    String? name,
    String? contactPref,
    int? position,
  }) => ResidentRow(
    id: id ?? this.id,
    homeId: homeId ?? this.homeId,
    name: name ?? this.name,
    contactPref: contactPref ?? this.contactPref,
    position: position ?? this.position,
  );
  ResidentRow copyWithCompanion(ResidentsTableCompanion data) {
    return ResidentRow(
      id: data.id.present ? data.id.value : this.id,
      homeId: data.homeId.present ? data.homeId.value : this.homeId,
      name: data.name.present ? data.name.value : this.name,
      contactPref: data.contactPref.present
          ? data.contactPref.value
          : this.contactPref,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ResidentRow(')
          ..write('id: $id, ')
          ..write('homeId: $homeId, ')
          ..write('name: $name, ')
          ..write('contactPref: $contactPref, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, homeId, name, contactPref, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ResidentRow &&
          other.id == this.id &&
          other.homeId == this.homeId &&
          other.name == this.name &&
          other.contactPref == this.contactPref &&
          other.position == this.position);
}

class ResidentsTableCompanion extends UpdateCompanion<ResidentRow> {
  final Value<String> id;
  final Value<String> homeId;
  final Value<String> name;
  final Value<String> contactPref;
  final Value<int> position;
  final Value<int> rowid;
  const ResidentsTableCompanion({
    this.id = const Value.absent(),
    this.homeId = const Value.absent(),
    this.name = const Value.absent(),
    this.contactPref = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ResidentsTableCompanion.insert({
    required String id,
    required String homeId,
    required String name,
    required String contactPref,
    required int position,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       homeId = Value(homeId),
       name = Value(name),
       contactPref = Value(contactPref),
       position = Value(position);
  static Insertable<ResidentRow> custom({
    Expression<String>? id,
    Expression<String>? homeId,
    Expression<String>? name,
    Expression<String>? contactPref,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (homeId != null) 'home_id': homeId,
      if (name != null) 'name': name,
      if (contactPref != null) 'contact_pref': contactPref,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ResidentsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? homeId,
    Value<String>? name,
    Value<String>? contactPref,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return ResidentsTableCompanion(
      id: id ?? this.id,
      homeId: homeId ?? this.homeId,
      name: name ?? this.name,
      contactPref: contactPref ?? this.contactPref,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (homeId.present) {
      map['home_id'] = Variable<String>(homeId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (contactPref.present) {
      map['contact_pref'] = Variable<String>(contactPref.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ResidentsTableCompanion(')
          ..write('id: $id, ')
          ..write('homeId: $homeId, ')
          ..write('name: $name, ')
          ..write('contactPref: $contactPref, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NumbersTableTable extends NumbersTable
    with TableInfo<$NumbersTableTable, NumberRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NumbersTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _residentIdMeta = const VerificationMeta(
    'residentId',
  );
  @override
  late final GeneratedColumn<String> residentId = GeneratedColumn<String>(
    'resident_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _e164Meta = const VerificationMeta('e164');
  @override
  late final GeneratedColumn<String> e164 = GeneratedColumn<String>(
    'e164',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _last4Meta = const VerificationMeta('last4');
  @override
  late final GeneratedColumn<String> last4 = GeneratedColumn<String>(
    'last4',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPrimaryMeta = const VerificationMeta(
    'isPrimary',
  );
  @override
  late final GeneratedColumn<bool> isPrimary = GeneratedColumn<bool>(
    'is_primary',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_primary" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    residentId,
    e164,
    last4,
    isPrimary,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'numbers';
  @override
  VerificationContext validateIntegrity(
    Insertable<NumberRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('resident_id')) {
      context.handle(
        _residentIdMeta,
        residentId.isAcceptableOrUnknown(data['resident_id']!, _residentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_residentIdMeta);
    }
    if (data.containsKey('e164')) {
      context.handle(
        _e164Meta,
        e164.isAcceptableOrUnknown(data['e164']!, _e164Meta),
      );
    } else if (isInserting) {
      context.missing(_e164Meta);
    }
    if (data.containsKey('last4')) {
      context.handle(
        _last4Meta,
        last4.isAcceptableOrUnknown(data['last4']!, _last4Meta),
      );
    } else if (isInserting) {
      context.missing(_last4Meta);
    }
    if (data.containsKey('is_primary')) {
      context.handle(
        _isPrimaryMeta,
        isPrimary.isAcceptableOrUnknown(data['is_primary']!, _isPrimaryMeta),
      );
    } else if (isInserting) {
      context.missing(_isPrimaryMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NumberRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NumberRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      residentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resident_id'],
      )!,
      e164: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}e164'],
      )!,
      last4: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last4'],
      )!,
      isPrimary: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_primary'],
      )!,
    );
  }

  @override
  $NumbersTableTable createAlias(String alias) {
    return $NumbersTableTable(attachedDatabase, alias);
  }
}

class NumberRow extends DataClass implements Insertable<NumberRow> {
  final String id;
  final String residentId;
  final String e164;
  final String last4;
  final bool isPrimary;
  const NumberRow({
    required this.id,
    required this.residentId,
    required this.e164,
    required this.last4,
    required this.isPrimary,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['resident_id'] = Variable<String>(residentId);
    map['e164'] = Variable<String>(e164);
    map['last4'] = Variable<String>(last4);
    map['is_primary'] = Variable<bool>(isPrimary);
    return map;
  }

  NumbersTableCompanion toCompanion(bool nullToAbsent) {
    return NumbersTableCompanion(
      id: Value(id),
      residentId: Value(residentId),
      e164: Value(e164),
      last4: Value(last4),
      isPrimary: Value(isPrimary),
    );
  }

  factory NumberRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NumberRow(
      id: serializer.fromJson<String>(json['id']),
      residentId: serializer.fromJson<String>(json['residentId']),
      e164: serializer.fromJson<String>(json['e164']),
      last4: serializer.fromJson<String>(json['last4']),
      isPrimary: serializer.fromJson<bool>(json['isPrimary']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'residentId': serializer.toJson<String>(residentId),
      'e164': serializer.toJson<String>(e164),
      'last4': serializer.toJson<String>(last4),
      'isPrimary': serializer.toJson<bool>(isPrimary),
    };
  }

  NumberRow copyWith({
    String? id,
    String? residentId,
    String? e164,
    String? last4,
    bool? isPrimary,
  }) => NumberRow(
    id: id ?? this.id,
    residentId: residentId ?? this.residentId,
    e164: e164 ?? this.e164,
    last4: last4 ?? this.last4,
    isPrimary: isPrimary ?? this.isPrimary,
  );
  NumberRow copyWithCompanion(NumbersTableCompanion data) {
    return NumberRow(
      id: data.id.present ? data.id.value : this.id,
      residentId: data.residentId.present
          ? data.residentId.value
          : this.residentId,
      e164: data.e164.present ? data.e164.value : this.e164,
      last4: data.last4.present ? data.last4.value : this.last4,
      isPrimary: data.isPrimary.present ? data.isPrimary.value : this.isPrimary,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NumberRow(')
          ..write('id: $id, ')
          ..write('residentId: $residentId, ')
          ..write('e164: $e164, ')
          ..write('last4: $last4, ')
          ..write('isPrimary: $isPrimary')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, residentId, e164, last4, isPrimary);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NumberRow &&
          other.id == this.id &&
          other.residentId == this.residentId &&
          other.e164 == this.e164 &&
          other.last4 == this.last4 &&
          other.isPrimary == this.isPrimary);
}

class NumbersTableCompanion extends UpdateCompanion<NumberRow> {
  final Value<String> id;
  final Value<String> residentId;
  final Value<String> e164;
  final Value<String> last4;
  final Value<bool> isPrimary;
  final Value<int> rowid;
  const NumbersTableCompanion({
    this.id = const Value.absent(),
    this.residentId = const Value.absent(),
    this.e164 = const Value.absent(),
    this.last4 = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NumbersTableCompanion.insert({
    required String id,
    required String residentId,
    required String e164,
    required String last4,
    required bool isPrimary,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       residentId = Value(residentId),
       e164 = Value(e164),
       last4 = Value(last4),
       isPrimary = Value(isPrimary);
  static Insertable<NumberRow> custom({
    Expression<String>? id,
    Expression<String>? residentId,
    Expression<String>? e164,
    Expression<String>? last4,
    Expression<bool>? isPrimary,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (residentId != null) 'resident_id': residentId,
      if (e164 != null) 'e164': e164,
      if (last4 != null) 'last4': last4,
      if (isPrimary != null) 'is_primary': isPrimary,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NumbersTableCompanion copyWith({
    Value<String>? id,
    Value<String>? residentId,
    Value<String>? e164,
    Value<String>? last4,
    Value<bool>? isPrimary,
    Value<int>? rowid,
  }) {
    return NumbersTableCompanion(
      id: id ?? this.id,
      residentId: residentId ?? this.residentId,
      e164: e164 ?? this.e164,
      last4: last4 ?? this.last4,
      isPrimary: isPrimary ?? this.isPrimary,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (residentId.present) {
      map['resident_id'] = Variable<String>(residentId.value);
    }
    if (e164.present) {
      map['e164'] = Variable<String>(e164.value);
    }
    if (last4.present) {
      map['last4'] = Variable<String>(last4.value);
    }
    if (isPrimary.present) {
      map['is_primary'] = Variable<bool>(isPrimary.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NumbersTableCompanion(')
          ..write('id: $id, ')
          ..write('residentId: $residentId, ')
          ..write('e164: $e164, ')
          ..write('last4: $last4, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VisitsTableTable extends VisitsTable
    with TableInfo<$VisitsTableTable, VisitRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VisitsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _homeIdMeta = const VerificationMeta('homeId');
  @override
  late final GeneratedColumn<String> homeId = GeneratedColumn<String>(
    'home_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _residentIdMeta = const VerificationMeta(
    'residentId',
  );
  @override
  late final GeneratedColumn<String> residentId = GeneratedColumn<String>(
    'resident_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _guestNameMeta = const VerificationMeta(
    'guestName',
  );
  @override
  late final GeneratedColumn<String> guestName = GeneratedColumn<String>(
    'guest_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _windowStartMeta = const VerificationMeta(
    'windowStart',
  );
  @override
  late final GeneratedColumn<int> windowStart = GeneratedColumn<int>(
    'window_start',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _windowEndMeta = const VerificationMeta(
    'windowEnd',
  );
  @override
  late final GeneratedColumn<int> windowEnd = GeneratedColumn<int>(
    'window_end',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyVersionMeta = const VerificationMeta(
    'keyVersion',
  );
  @override
  late final GeneratedColumn<int> keyVersion = GeneratedColumn<int>(
    'key_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _codeIssuedMeta = const VerificationMeta(
    'codeIssued',
  );
  @override
  late final GeneratedColumn<bool> codeIssued = GeneratedColumn<bool>(
    'code_issued',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("code_issued" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedUntilMeta = const VerificationMeta(
    'expectedUntil',
  );
  @override
  late final GeneratedColumn<String> expectedUntil = GeneratedColumn<String>(
    'expected_until',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enteredAtMeta = const VerificationMeta(
    'enteredAt',
  );
  @override
  late final GeneratedColumn<String> enteredAt = GeneratedColumn<String>(
    'entered_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    homeId,
    residentId,
    guestName,
    windowStart,
    windowEnd,
    keyVersion,
    codeIssued,
    source,
    state,
    expectedUntil,
    entryId,
    enteredAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'visits';
  @override
  VerificationContext validateIntegrity(
    Insertable<VisitRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('home_id')) {
      context.handle(
        _homeIdMeta,
        homeId.isAcceptableOrUnknown(data['home_id']!, _homeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_homeIdMeta);
    }
    if (data.containsKey('resident_id')) {
      context.handle(
        _residentIdMeta,
        residentId.isAcceptableOrUnknown(data['resident_id']!, _residentIdMeta),
      );
    }
    if (data.containsKey('guest_name')) {
      context.handle(
        _guestNameMeta,
        guestName.isAcceptableOrUnknown(data['guest_name']!, _guestNameMeta),
      );
    } else if (isInserting) {
      context.missing(_guestNameMeta);
    }
    if (data.containsKey('window_start')) {
      context.handle(
        _windowStartMeta,
        windowStart.isAcceptableOrUnknown(
          data['window_start']!,
          _windowStartMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_windowStartMeta);
    }
    if (data.containsKey('window_end')) {
      context.handle(
        _windowEndMeta,
        windowEnd.isAcceptableOrUnknown(data['window_end']!, _windowEndMeta),
      );
    } else if (isInserting) {
      context.missing(_windowEndMeta);
    }
    if (data.containsKey('key_version')) {
      context.handle(
        _keyVersionMeta,
        keyVersion.isAcceptableOrUnknown(data['key_version']!, _keyVersionMeta),
      );
    }
    if (data.containsKey('code_issued')) {
      context.handle(
        _codeIssuedMeta,
        codeIssued.isAcceptableOrUnknown(data['code_issued']!, _codeIssuedMeta),
      );
    } else if (isInserting) {
      context.missing(_codeIssuedMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('expected_until')) {
      context.handle(
        _expectedUntilMeta,
        expectedUntil.isAcceptableOrUnknown(
          data['expected_until']!,
          _expectedUntilMeta,
        ),
      );
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    }
    if (data.containsKey('entered_at')) {
      context.handle(
        _enteredAtMeta,
        enteredAt.isAcceptableOrUnknown(data['entered_at']!, _enteredAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VisitRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VisitRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      homeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}home_id'],
      )!,
      residentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resident_id'],
      ),
      guestName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}guest_name'],
      )!,
      windowStart: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}window_start'],
      )!,
      windowEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}window_end'],
      )!,
      keyVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}key_version'],
      ),
      codeIssued: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}code_issued'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      expectedUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expected_until'],
      ),
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      ),
      enteredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entered_at'],
      ),
    );
  }

  @override
  $VisitsTableTable createAlias(String alias) {
    return $VisitsTableTable(attachedDatabase, alias);
  }
}

class VisitRow extends DataClass implements Insertable<VisitRow> {
  final String id;
  final String homeId;
  final String? residentId;
  final String guestName;
  final int windowStart;
  final int windowEnd;
  final int? keyVersion;
  final bool codeIssued;
  final String source;
  final String state;
  final String? expectedUntil;
  final String? entryId;
  final String? enteredAt;
  const VisitRow({
    required this.id,
    required this.homeId,
    this.residentId,
    required this.guestName,
    required this.windowStart,
    required this.windowEnd,
    this.keyVersion,
    required this.codeIssued,
    required this.source,
    required this.state,
    this.expectedUntil,
    this.entryId,
    this.enteredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['home_id'] = Variable<String>(homeId);
    if (!nullToAbsent || residentId != null) {
      map['resident_id'] = Variable<String>(residentId);
    }
    map['guest_name'] = Variable<String>(guestName);
    map['window_start'] = Variable<int>(windowStart);
    map['window_end'] = Variable<int>(windowEnd);
    if (!nullToAbsent || keyVersion != null) {
      map['key_version'] = Variable<int>(keyVersion);
    }
    map['code_issued'] = Variable<bool>(codeIssued);
    map['source'] = Variable<String>(source);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || expectedUntil != null) {
      map['expected_until'] = Variable<String>(expectedUntil);
    }
    if (!nullToAbsent || entryId != null) {
      map['entry_id'] = Variable<String>(entryId);
    }
    if (!nullToAbsent || enteredAt != null) {
      map['entered_at'] = Variable<String>(enteredAt);
    }
    return map;
  }

  VisitsTableCompanion toCompanion(bool nullToAbsent) {
    return VisitsTableCompanion(
      id: Value(id),
      homeId: Value(homeId),
      residentId: residentId == null && nullToAbsent
          ? const Value.absent()
          : Value(residentId),
      guestName: Value(guestName),
      windowStart: Value(windowStart),
      windowEnd: Value(windowEnd),
      keyVersion: keyVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(keyVersion),
      codeIssued: Value(codeIssued),
      source: Value(source),
      state: Value(state),
      expectedUntil: expectedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedUntil),
      entryId: entryId == null && nullToAbsent
          ? const Value.absent()
          : Value(entryId),
      enteredAt: enteredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(enteredAt),
    );
  }

  factory VisitRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VisitRow(
      id: serializer.fromJson<String>(json['id']),
      homeId: serializer.fromJson<String>(json['homeId']),
      residentId: serializer.fromJson<String?>(json['residentId']),
      guestName: serializer.fromJson<String>(json['guestName']),
      windowStart: serializer.fromJson<int>(json['windowStart']),
      windowEnd: serializer.fromJson<int>(json['windowEnd']),
      keyVersion: serializer.fromJson<int?>(json['keyVersion']),
      codeIssued: serializer.fromJson<bool>(json['codeIssued']),
      source: serializer.fromJson<String>(json['source']),
      state: serializer.fromJson<String>(json['state']),
      expectedUntil: serializer.fromJson<String?>(json['expectedUntil']),
      entryId: serializer.fromJson<String?>(json['entryId']),
      enteredAt: serializer.fromJson<String?>(json['enteredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'homeId': serializer.toJson<String>(homeId),
      'residentId': serializer.toJson<String?>(residentId),
      'guestName': serializer.toJson<String>(guestName),
      'windowStart': serializer.toJson<int>(windowStart),
      'windowEnd': serializer.toJson<int>(windowEnd),
      'keyVersion': serializer.toJson<int?>(keyVersion),
      'codeIssued': serializer.toJson<bool>(codeIssued),
      'source': serializer.toJson<String>(source),
      'state': serializer.toJson<String>(state),
      'expectedUntil': serializer.toJson<String?>(expectedUntil),
      'entryId': serializer.toJson<String?>(entryId),
      'enteredAt': serializer.toJson<String?>(enteredAt),
    };
  }

  VisitRow copyWith({
    String? id,
    String? homeId,
    Value<String?> residentId = const Value.absent(),
    String? guestName,
    int? windowStart,
    int? windowEnd,
    Value<int?> keyVersion = const Value.absent(),
    bool? codeIssued,
    String? source,
    String? state,
    Value<String?> expectedUntil = const Value.absent(),
    Value<String?> entryId = const Value.absent(),
    Value<String?> enteredAt = const Value.absent(),
  }) => VisitRow(
    id: id ?? this.id,
    homeId: homeId ?? this.homeId,
    residentId: residentId.present ? residentId.value : this.residentId,
    guestName: guestName ?? this.guestName,
    windowStart: windowStart ?? this.windowStart,
    windowEnd: windowEnd ?? this.windowEnd,
    keyVersion: keyVersion.present ? keyVersion.value : this.keyVersion,
    codeIssued: codeIssued ?? this.codeIssued,
    source: source ?? this.source,
    state: state ?? this.state,
    expectedUntil: expectedUntil.present
        ? expectedUntil.value
        : this.expectedUntil,
    entryId: entryId.present ? entryId.value : this.entryId,
    enteredAt: enteredAt.present ? enteredAt.value : this.enteredAt,
  );
  VisitRow copyWithCompanion(VisitsTableCompanion data) {
    return VisitRow(
      id: data.id.present ? data.id.value : this.id,
      homeId: data.homeId.present ? data.homeId.value : this.homeId,
      residentId: data.residentId.present
          ? data.residentId.value
          : this.residentId,
      guestName: data.guestName.present ? data.guestName.value : this.guestName,
      windowStart: data.windowStart.present
          ? data.windowStart.value
          : this.windowStart,
      windowEnd: data.windowEnd.present ? data.windowEnd.value : this.windowEnd,
      keyVersion: data.keyVersion.present
          ? data.keyVersion.value
          : this.keyVersion,
      codeIssued: data.codeIssued.present
          ? data.codeIssued.value
          : this.codeIssued,
      source: data.source.present ? data.source.value : this.source,
      state: data.state.present ? data.state.value : this.state,
      expectedUntil: data.expectedUntil.present
          ? data.expectedUntil.value
          : this.expectedUntil,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      enteredAt: data.enteredAt.present ? data.enteredAt.value : this.enteredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VisitRow(')
          ..write('id: $id, ')
          ..write('homeId: $homeId, ')
          ..write('residentId: $residentId, ')
          ..write('guestName: $guestName, ')
          ..write('windowStart: $windowStart, ')
          ..write('windowEnd: $windowEnd, ')
          ..write('keyVersion: $keyVersion, ')
          ..write('codeIssued: $codeIssued, ')
          ..write('source: $source, ')
          ..write('state: $state, ')
          ..write('expectedUntil: $expectedUntil, ')
          ..write('entryId: $entryId, ')
          ..write('enteredAt: $enteredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    homeId,
    residentId,
    guestName,
    windowStart,
    windowEnd,
    keyVersion,
    codeIssued,
    source,
    state,
    expectedUntil,
    entryId,
    enteredAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VisitRow &&
          other.id == this.id &&
          other.homeId == this.homeId &&
          other.residentId == this.residentId &&
          other.guestName == this.guestName &&
          other.windowStart == this.windowStart &&
          other.windowEnd == this.windowEnd &&
          other.keyVersion == this.keyVersion &&
          other.codeIssued == this.codeIssued &&
          other.source == this.source &&
          other.state == this.state &&
          other.expectedUntil == this.expectedUntil &&
          other.entryId == this.entryId &&
          other.enteredAt == this.enteredAt);
}

class VisitsTableCompanion extends UpdateCompanion<VisitRow> {
  final Value<String> id;
  final Value<String> homeId;
  final Value<String?> residentId;
  final Value<String> guestName;
  final Value<int> windowStart;
  final Value<int> windowEnd;
  final Value<int?> keyVersion;
  final Value<bool> codeIssued;
  final Value<String> source;
  final Value<String> state;
  final Value<String?> expectedUntil;
  final Value<String?> entryId;
  final Value<String?> enteredAt;
  final Value<int> rowid;
  const VisitsTableCompanion({
    this.id = const Value.absent(),
    this.homeId = const Value.absent(),
    this.residentId = const Value.absent(),
    this.guestName = const Value.absent(),
    this.windowStart = const Value.absent(),
    this.windowEnd = const Value.absent(),
    this.keyVersion = const Value.absent(),
    this.codeIssued = const Value.absent(),
    this.source = const Value.absent(),
    this.state = const Value.absent(),
    this.expectedUntil = const Value.absent(),
    this.entryId = const Value.absent(),
    this.enteredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VisitsTableCompanion.insert({
    required String id,
    required String homeId,
    this.residentId = const Value.absent(),
    required String guestName,
    required int windowStart,
    required int windowEnd,
    this.keyVersion = const Value.absent(),
    required bool codeIssued,
    required String source,
    required String state,
    this.expectedUntil = const Value.absent(),
    this.entryId = const Value.absent(),
    this.enteredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       homeId = Value(homeId),
       guestName = Value(guestName),
       windowStart = Value(windowStart),
       windowEnd = Value(windowEnd),
       codeIssued = Value(codeIssued),
       source = Value(source),
       state = Value(state);
  static Insertable<VisitRow> custom({
    Expression<String>? id,
    Expression<String>? homeId,
    Expression<String>? residentId,
    Expression<String>? guestName,
    Expression<int>? windowStart,
    Expression<int>? windowEnd,
    Expression<int>? keyVersion,
    Expression<bool>? codeIssued,
    Expression<String>? source,
    Expression<String>? state,
    Expression<String>? expectedUntil,
    Expression<String>? entryId,
    Expression<String>? enteredAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (homeId != null) 'home_id': homeId,
      if (residentId != null) 'resident_id': residentId,
      if (guestName != null) 'guest_name': guestName,
      if (windowStart != null) 'window_start': windowStart,
      if (windowEnd != null) 'window_end': windowEnd,
      if (keyVersion != null) 'key_version': keyVersion,
      if (codeIssued != null) 'code_issued': codeIssued,
      if (source != null) 'source': source,
      if (state != null) 'state': state,
      if (expectedUntil != null) 'expected_until': expectedUntil,
      if (entryId != null) 'entry_id': entryId,
      if (enteredAt != null) 'entered_at': enteredAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VisitsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? homeId,
    Value<String?>? residentId,
    Value<String>? guestName,
    Value<int>? windowStart,
    Value<int>? windowEnd,
    Value<int?>? keyVersion,
    Value<bool>? codeIssued,
    Value<String>? source,
    Value<String>? state,
    Value<String?>? expectedUntil,
    Value<String?>? entryId,
    Value<String?>? enteredAt,
    Value<int>? rowid,
  }) {
    return VisitsTableCompanion(
      id: id ?? this.id,
      homeId: homeId ?? this.homeId,
      residentId: residentId ?? this.residentId,
      guestName: guestName ?? this.guestName,
      windowStart: windowStart ?? this.windowStart,
      windowEnd: windowEnd ?? this.windowEnd,
      keyVersion: keyVersion ?? this.keyVersion,
      codeIssued: codeIssued ?? this.codeIssued,
      source: source ?? this.source,
      state: state ?? this.state,
      expectedUntil: expectedUntil ?? this.expectedUntil,
      entryId: entryId ?? this.entryId,
      enteredAt: enteredAt ?? this.enteredAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (homeId.present) {
      map['home_id'] = Variable<String>(homeId.value);
    }
    if (residentId.present) {
      map['resident_id'] = Variable<String>(residentId.value);
    }
    if (guestName.present) {
      map['guest_name'] = Variable<String>(guestName.value);
    }
    if (windowStart.present) {
      map['window_start'] = Variable<int>(windowStart.value);
    }
    if (windowEnd.present) {
      map['window_end'] = Variable<int>(windowEnd.value);
    }
    if (keyVersion.present) {
      map['key_version'] = Variable<int>(keyVersion.value);
    }
    if (codeIssued.present) {
      map['code_issued'] = Variable<bool>(codeIssued.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (expectedUntil.present) {
      map['expected_until'] = Variable<String>(expectedUntil.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (enteredAt.present) {
      map['entered_at'] = Variable<String>(enteredAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VisitsTableCompanion(')
          ..write('id: $id, ')
          ..write('homeId: $homeId, ')
          ..write('residentId: $residentId, ')
          ..write('guestName: $guestName, ')
          ..write('windowStart: $windowStart, ')
          ..write('windowEnd: $windowEnd, ')
          ..write('keyVersion: $keyVersion, ')
          ..write('codeIssued: $codeIssued, ')
          ..write('source: $source, ')
          ..write('state: $state, ')
          ..write('expectedUntil: $expectedUntil, ')
          ..write('entryId: $entryId, ')
          ..write('enteredAt: $enteredAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DirectoryTableTable extends DirectoryTable
    with TableInfo<$DirectoryTableTable, DirectoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DirectoryTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<String> number = GeneratedColumn<String>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _verifiedAtMeta = const VerificationMeta(
    'verifiedAt',
  );
  @override
  late final GeneratedColumn<String> verifiedAt = GeneratedColumn<String>(
    'verified_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reportedNotWorkingMeta =
      const VerificationMeta('reportedNotWorking');
  @override
  late final GeneratedColumn<bool> reportedNotWorking = GeneratedColumn<bool>(
    'reported_not_working',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reported_not_working" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    position,
    category,
    name,
    number,
    verifiedAt,
    reportedNotWorking,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'directory';
  @override
  VerificationContext validateIntegrity(
    Insertable<DirectoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('verified_at')) {
      context.handle(
        _verifiedAtMeta,
        verifiedAt.isAcceptableOrUnknown(data['verified_at']!, _verifiedAtMeta),
      );
    }
    if (data.containsKey('reported_not_working')) {
      context.handle(
        _reportedNotWorkingMeta,
        reportedNotWorking.isAcceptableOrUnknown(
          data['reported_not_working']!,
          _reportedNotWorkingMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reportedNotWorkingMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DirectoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DirectoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}number'],
      )!,
      verifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verified_at'],
      ),
      reportedNotWorking: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reported_not_working'],
      )!,
    );
  }

  @override
  $DirectoryTableTable createAlias(String alias) {
    return $DirectoryTableTable(attachedDatabase, alias);
  }
}

class DirectoryRow extends DataClass implements Insertable<DirectoryRow> {
  final String id;
  final int position;
  final String category;
  final String name;
  final String number;
  final String? verifiedAt;
  final bool reportedNotWorking;
  const DirectoryRow({
    required this.id,
    required this.position,
    required this.category,
    required this.name,
    required this.number,
    this.verifiedAt,
    required this.reportedNotWorking,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['position'] = Variable<int>(position);
    map['category'] = Variable<String>(category);
    map['name'] = Variable<String>(name);
    map['number'] = Variable<String>(number);
    if (!nullToAbsent || verifiedAt != null) {
      map['verified_at'] = Variable<String>(verifiedAt);
    }
    map['reported_not_working'] = Variable<bool>(reportedNotWorking);
    return map;
  }

  DirectoryTableCompanion toCompanion(bool nullToAbsent) {
    return DirectoryTableCompanion(
      id: Value(id),
      position: Value(position),
      category: Value(category),
      name: Value(name),
      number: Value(number),
      verifiedAt: verifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(verifiedAt),
      reportedNotWorking: Value(reportedNotWorking),
    );
  }

  factory DirectoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DirectoryRow(
      id: serializer.fromJson<String>(json['id']),
      position: serializer.fromJson<int>(json['position']),
      category: serializer.fromJson<String>(json['category']),
      name: serializer.fromJson<String>(json['name']),
      number: serializer.fromJson<String>(json['number']),
      verifiedAt: serializer.fromJson<String?>(json['verifiedAt']),
      reportedNotWorking: serializer.fromJson<bool>(json['reportedNotWorking']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'position': serializer.toJson<int>(position),
      'category': serializer.toJson<String>(category),
      'name': serializer.toJson<String>(name),
      'number': serializer.toJson<String>(number),
      'verifiedAt': serializer.toJson<String?>(verifiedAt),
      'reportedNotWorking': serializer.toJson<bool>(reportedNotWorking),
    };
  }

  DirectoryRow copyWith({
    String? id,
    int? position,
    String? category,
    String? name,
    String? number,
    Value<String?> verifiedAt = const Value.absent(),
    bool? reportedNotWorking,
  }) => DirectoryRow(
    id: id ?? this.id,
    position: position ?? this.position,
    category: category ?? this.category,
    name: name ?? this.name,
    number: number ?? this.number,
    verifiedAt: verifiedAt.present ? verifiedAt.value : this.verifiedAt,
    reportedNotWorking: reportedNotWorking ?? this.reportedNotWorking,
  );
  DirectoryRow copyWithCompanion(DirectoryTableCompanion data) {
    return DirectoryRow(
      id: data.id.present ? data.id.value : this.id,
      position: data.position.present ? data.position.value : this.position,
      category: data.category.present ? data.category.value : this.category,
      name: data.name.present ? data.name.value : this.name,
      number: data.number.present ? data.number.value : this.number,
      verifiedAt: data.verifiedAt.present
          ? data.verifiedAt.value
          : this.verifiedAt,
      reportedNotWorking: data.reportedNotWorking.present
          ? data.reportedNotWorking.value
          : this.reportedNotWorking,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DirectoryRow(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('category: $category, ')
          ..write('name: $name, ')
          ..write('number: $number, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('reportedNotWorking: $reportedNotWorking')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    position,
    category,
    name,
    number,
    verifiedAt,
    reportedNotWorking,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DirectoryRow &&
          other.id == this.id &&
          other.position == this.position &&
          other.category == this.category &&
          other.name == this.name &&
          other.number == this.number &&
          other.verifiedAt == this.verifiedAt &&
          other.reportedNotWorking == this.reportedNotWorking);
}

class DirectoryTableCompanion extends UpdateCompanion<DirectoryRow> {
  final Value<String> id;
  final Value<int> position;
  final Value<String> category;
  final Value<String> name;
  final Value<String> number;
  final Value<String?> verifiedAt;
  final Value<bool> reportedNotWorking;
  final Value<int> rowid;
  const DirectoryTableCompanion({
    this.id = const Value.absent(),
    this.position = const Value.absent(),
    this.category = const Value.absent(),
    this.name = const Value.absent(),
    this.number = const Value.absent(),
    this.verifiedAt = const Value.absent(),
    this.reportedNotWorking = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DirectoryTableCompanion.insert({
    required String id,
    required int position,
    required String category,
    required String name,
    required String number,
    this.verifiedAt = const Value.absent(),
    required bool reportedNotWorking,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       position = Value(position),
       category = Value(category),
       name = Value(name),
       number = Value(number),
       reportedNotWorking = Value(reportedNotWorking);
  static Insertable<DirectoryRow> custom({
    Expression<String>? id,
    Expression<int>? position,
    Expression<String>? category,
    Expression<String>? name,
    Expression<String>? number,
    Expression<String>? verifiedAt,
    Expression<bool>? reportedNotWorking,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (position != null) 'position': position,
      if (category != null) 'category': category,
      if (name != null) 'name': name,
      if (number != null) 'number': number,
      if (verifiedAt != null) 'verified_at': verifiedAt,
      if (reportedNotWorking != null)
        'reported_not_working': reportedNotWorking,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DirectoryTableCompanion copyWith({
    Value<String>? id,
    Value<int>? position,
    Value<String>? category,
    Value<String>? name,
    Value<String>? number,
    Value<String?>? verifiedAt,
    Value<bool>? reportedNotWorking,
    Value<int>? rowid,
  }) {
    return DirectoryTableCompanion(
      id: id ?? this.id,
      position: position ?? this.position,
      category: category ?? this.category,
      name: name ?? this.name,
      number: number ?? this.number,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      reportedNotWorking: reportedNotWorking ?? this.reportedNotWorking,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (number.present) {
      map['number'] = Variable<String>(number.value);
    }
    if (verifiedAt.present) {
      map['verified_at'] = Variable<String>(verifiedAt.value);
    }
    if (reportedNotWorking.present) {
      map['reported_not_working'] = Variable<bool>(reportedNotWorking.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DirectoryTableCompanion(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('category: $category, ')
          ..write('name: $name, ')
          ..write('number: $number, ')
          ..write('verifiedAt: $verifiedAt, ')
          ..write('reportedNotWorking: $reportedNotWorking, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GatesTableTable extends GatesTable
    with TableInfo<$GatesTableTable, GateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GatesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gates';
  @override
  VerificationContext validateIntegrity(
    Insertable<GateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $GatesTableTable createAlias(String alias) {
    return $GatesTableTable(attachedDatabase, alias);
  }
}

class GateRow extends DataClass implements Insertable<GateRow> {
  final String id;
  final String name;
  const GateRow({required this.id, required this.name});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    return map;
  }

  GatesTableCompanion toCompanion(bool nullToAbsent) {
    return GatesTableCompanion(id: Value(id), name: Value(name));
  }

  factory GateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GateRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
    };
  }

  GateRow copyWith({String? id, String? name}) =>
      GateRow(id: id ?? this.id, name: name ?? this.name);
  GateRow copyWithCompanion(GatesTableCompanion data) {
    return GateRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GateRow(')
          ..write('id: $id, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GateRow && other.id == this.id && other.name == this.name);
}

class GatesTableCompanion extends UpdateCompanion<GateRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> rowid;
  const GatesTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GatesTableCompanion.insert({
    required String id,
    required String name,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<GateRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GatesTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return GatesTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GatesTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GuardsTableTable extends GuardsTable
    with TableInfo<$GuardsTableTable, GuardRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GuardsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('guard'),
  );
  static const VerificationMeta _pinHashMeta = const VerificationMeta(
    'pinHash',
  );
  @override
  late final GeneratedColumn<String> pinHash = GeneratedColumn<String>(
    'pin_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pinResetAtMeta = const VerificationMeta(
    'pinResetAt',
  );
  @override
  late final GeneratedColumn<String> pinResetAt = GeneratedColumn<String>(
    'pin_reset_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _consentMeta = const VerificationMeta(
    'consent',
  );
  @override
  late final GeneratedColumn<bool> consent = GeneratedColumn<bool>(
    'consent',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("consent" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    role,
    pinHash,
    pinResetAt,
    consent,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'guards';
  @override
  VerificationContext validateIntegrity(
    Insertable<GuardRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    }
    if (data.containsKey('pin_hash')) {
      context.handle(
        _pinHashMeta,
        pinHash.isAcceptableOrUnknown(data['pin_hash']!, _pinHashMeta),
      );
    }
    if (data.containsKey('pin_reset_at')) {
      context.handle(
        _pinResetAtMeta,
        pinResetAt.isAcceptableOrUnknown(
          data['pin_reset_at']!,
          _pinResetAtMeta,
        ),
      );
    }
    if (data.containsKey('consent')) {
      context.handle(
        _consentMeta,
        consent.isAcceptableOrUnknown(data['consent']!, _consentMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GuardRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GuardRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      pinHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pin_hash'],
      ),
      pinResetAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pin_reset_at'],
      ),
      consent: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}consent'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $GuardsTableTable createAlias(String alias) {
    return $GuardsTableTable(attachedDatabase, alias);
  }
}

class GuardRow extends DataClass implements Insertable<GuardRow> {
  final String id;
  final String name;
  final String role;
  final String? pinHash;
  final String? pinResetAt;
  final bool consent;
  final int position;
  const GuardRow({
    required this.id,
    required this.name,
    required this.role,
    this.pinHash,
    this.pinResetAt,
    required this.consent,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['role'] = Variable<String>(role);
    if (!nullToAbsent || pinHash != null) {
      map['pin_hash'] = Variable<String>(pinHash);
    }
    if (!nullToAbsent || pinResetAt != null) {
      map['pin_reset_at'] = Variable<String>(pinResetAt);
    }
    map['consent'] = Variable<bool>(consent);
    map['position'] = Variable<int>(position);
    return map;
  }

  GuardsTableCompanion toCompanion(bool nullToAbsent) {
    return GuardsTableCompanion(
      id: Value(id),
      name: Value(name),
      role: Value(role),
      pinHash: pinHash == null && nullToAbsent
          ? const Value.absent()
          : Value(pinHash),
      pinResetAt: pinResetAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pinResetAt),
      consent: Value(consent),
      position: Value(position),
    );
  }

  factory GuardRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GuardRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      role: serializer.fromJson<String>(json['role']),
      pinHash: serializer.fromJson<String?>(json['pinHash']),
      pinResetAt: serializer.fromJson<String?>(json['pinResetAt']),
      consent: serializer.fromJson<bool>(json['consent']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'role': serializer.toJson<String>(role),
      'pinHash': serializer.toJson<String?>(pinHash),
      'pinResetAt': serializer.toJson<String?>(pinResetAt),
      'consent': serializer.toJson<bool>(consent),
      'position': serializer.toJson<int>(position),
    };
  }

  GuardRow copyWith({
    String? id,
    String? name,
    String? role,
    Value<String?> pinHash = const Value.absent(),
    Value<String?> pinResetAt = const Value.absent(),
    bool? consent,
    int? position,
  }) => GuardRow(
    id: id ?? this.id,
    name: name ?? this.name,
    role: role ?? this.role,
    pinHash: pinHash.present ? pinHash.value : this.pinHash,
    pinResetAt: pinResetAt.present ? pinResetAt.value : this.pinResetAt,
    consent: consent ?? this.consent,
    position: position ?? this.position,
  );
  GuardRow copyWithCompanion(GuardsTableCompanion data) {
    return GuardRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      role: data.role.present ? data.role.value : this.role,
      pinHash: data.pinHash.present ? data.pinHash.value : this.pinHash,
      pinResetAt: data.pinResetAt.present
          ? data.pinResetAt.value
          : this.pinResetAt,
      consent: data.consent.present ? data.consent.value : this.consent,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GuardRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('pinHash: $pinHash, ')
          ..write('pinResetAt: $pinResetAt, ')
          ..write('consent: $consent, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, role, pinHash, pinResetAt, consent, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GuardRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.role == this.role &&
          other.pinHash == this.pinHash &&
          other.pinResetAt == this.pinResetAt &&
          other.consent == this.consent &&
          other.position == this.position);
}

class GuardsTableCompanion extends UpdateCompanion<GuardRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> role;
  final Value<String?> pinHash;
  final Value<String?> pinResetAt;
  final Value<bool> consent;
  final Value<int> position;
  final Value<int> rowid;
  const GuardsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.role = const Value.absent(),
    this.pinHash = const Value.absent(),
    this.pinResetAt = const Value.absent(),
    this.consent = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GuardsTableCompanion.insert({
    required String id,
    required String name,
    this.role = const Value.absent(),
    this.pinHash = const Value.absent(),
    this.pinResetAt = const Value.absent(),
    this.consent = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<GuardRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? role,
    Expression<String>? pinHash,
    Expression<String>? pinResetAt,
    Expression<bool>? consent,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (role != null) 'role': role,
      if (pinHash != null) 'pin_hash': pinHash,
      if (pinResetAt != null) 'pin_reset_at': pinResetAt,
      if (consent != null) 'consent': consent,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GuardsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? role,
    Value<String?>? pinHash,
    Value<String?>? pinResetAt,
    Value<bool>? consent,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return GuardsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      pinHash: pinHash ?? this.pinHash,
      pinResetAt: pinResetAt ?? this.pinResetAt,
      consent: consent ?? this.consent,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (pinHash.present) {
      map['pin_hash'] = Variable<String>(pinHash.value);
    }
    if (pinResetAt.present) {
      map['pin_reset_at'] = Variable<String>(pinResetAt.value);
    }
    if (consent.present) {
      map['consent'] = Variable<bool>(consent.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GuardsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('role: $role, ')
          ..write('pinHash: $pinHash, ')
          ..write('pinResetAt: $pinResetAt, ')
          ..write('consent: $consent, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VehiclesTableTable extends VehiclesTable
    with TableInfo<$VehiclesTableTable, VehicleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VehiclesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _homeIdMeta = const VerificationMeta('homeId');
  @override
  late final GeneratedColumn<String> homeId = GeneratedColumn<String>(
    'home_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _plateMeta = const VerificationMeta('plate');
  @override
  late final GeneratedColumn<String> plate = GeneratedColumn<String>(
    'plate',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [seq, homeId, plate, description];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'vehicles';
  @override
  VerificationContext validateIntegrity(
    Insertable<VehicleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    }
    if (data.containsKey('home_id')) {
      context.handle(
        _homeIdMeta,
        homeId.isAcceptableOrUnknown(data['home_id']!, _homeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_homeIdMeta);
    }
    if (data.containsKey('plate')) {
      context.handle(
        _plateMeta,
        plate.isAcceptableOrUnknown(data['plate']!, _plateMeta),
      );
    } else if (isInserting) {
      context.missing(_plateMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seq};
  @override
  VehicleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VehicleRow(
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      homeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}home_id'],
      )!,
      plate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plate'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
    );
  }

  @override
  $VehiclesTableTable createAlias(String alias) {
    return $VehiclesTableTable(attachedDatabase, alias);
  }
}

class VehicleRow extends DataClass implements Insertable<VehicleRow> {
  final int seq;
  final String homeId;
  final String plate;
  final String? description;
  const VehicleRow({
    required this.seq,
    required this.homeId,
    required this.plate,
    this.description,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['seq'] = Variable<int>(seq);
    map['home_id'] = Variable<String>(homeId);
    map['plate'] = Variable<String>(plate);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    return map;
  }

  VehiclesTableCompanion toCompanion(bool nullToAbsent) {
    return VehiclesTableCompanion(
      seq: Value(seq),
      homeId: Value(homeId),
      plate: Value(plate),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
    );
  }

  factory VehicleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VehicleRow(
      seq: serializer.fromJson<int>(json['seq']),
      homeId: serializer.fromJson<String>(json['homeId']),
      plate: serializer.fromJson<String>(json['plate']),
      description: serializer.fromJson<String?>(json['description']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seq': serializer.toJson<int>(seq),
      'homeId': serializer.toJson<String>(homeId),
      'plate': serializer.toJson<String>(plate),
      'description': serializer.toJson<String?>(description),
    };
  }

  VehicleRow copyWith({
    int? seq,
    String? homeId,
    String? plate,
    Value<String?> description = const Value.absent(),
  }) => VehicleRow(
    seq: seq ?? this.seq,
    homeId: homeId ?? this.homeId,
    plate: plate ?? this.plate,
    description: description.present ? description.value : this.description,
  );
  VehicleRow copyWithCompanion(VehiclesTableCompanion data) {
    return VehicleRow(
      seq: data.seq.present ? data.seq.value : this.seq,
      homeId: data.homeId.present ? data.homeId.value : this.homeId,
      plate: data.plate.present ? data.plate.value : this.plate,
      description: data.description.present
          ? data.description.value
          : this.description,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VehicleRow(')
          ..write('seq: $seq, ')
          ..write('homeId: $homeId, ')
          ..write('plate: $plate, ')
          ..write('description: $description')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(seq, homeId, plate, description);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VehicleRow &&
          other.seq == this.seq &&
          other.homeId == this.homeId &&
          other.plate == this.plate &&
          other.description == this.description);
}

class VehiclesTableCompanion extends UpdateCompanion<VehicleRow> {
  final Value<int> seq;
  final Value<String> homeId;
  final Value<String> plate;
  final Value<String?> description;
  const VehiclesTableCompanion({
    this.seq = const Value.absent(),
    this.homeId = const Value.absent(),
    this.plate = const Value.absent(),
    this.description = const Value.absent(),
  });
  VehiclesTableCompanion.insert({
    this.seq = const Value.absent(),
    required String homeId,
    required String plate,
    this.description = const Value.absent(),
  }) : homeId = Value(homeId),
       plate = Value(plate);
  static Insertable<VehicleRow> custom({
    Expression<int>? seq,
    Expression<String>? homeId,
    Expression<String>? plate,
    Expression<String>? description,
  }) {
    return RawValuesInsertable({
      if (seq != null) 'seq': seq,
      if (homeId != null) 'home_id': homeId,
      if (plate != null) 'plate': plate,
      if (description != null) 'description': description,
    });
  }

  VehiclesTableCompanion copyWith({
    Value<int>? seq,
    Value<String>? homeId,
    Value<String>? plate,
    Value<String?>? description,
  }) {
    return VehiclesTableCompanion(
      seq: seq ?? this.seq,
      homeId: homeId ?? this.homeId,
      plate: plate ?? this.plate,
      description: description ?? this.description,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (homeId.present) {
      map['home_id'] = Variable<String>(homeId.value);
    }
    if (plate.present) {
      map['plate'] = Variable<String>(plate.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VehiclesTableCompanion(')
          ..write('seq: $seq, ')
          ..write('homeId: $homeId, ')
          ..write('plate: $plate, ')
          ..write('description: $description')
          ..write(')'))
        .toString();
  }
}

class $MetaTableTable extends MetaTable
    with TableInfo<$MetaTableTable, MetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetaTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<MetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  MetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetaRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $MetaTableTable createAlias(String alias) {
    return $MetaTableTable(attachedDatabase, alias);
  }
}

class MetaRow extends DataClass implements Insertable<MetaRow> {
  final String key;
  final String value;
  const MetaRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  MetaTableCompanion toCompanion(bool nullToAbsent) {
    return MetaTableCompanion(key: Value(key), value: Value(value));
  }

  factory MetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetaRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  MetaRow copyWith({String? key, String? value}) =>
      MetaRow(key: key ?? this.key, value: value ?? this.value);
  MetaRow copyWithCompanion(MetaTableCompanion data) {
    return MetaRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetaRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetaRow && other.key == this.key && other.value == this.value);
}

class MetaTableCompanion extends UpdateCompanion<MetaRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const MetaTableCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetaTableCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<MetaRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetaTableCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return MetaTableCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetaTableCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTableTable extends OutboxTable
    with TableInfo<$OutboxTableTable, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<DateTime> sentAt = GeneratedColumn<DateTime>(
    'sent_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    seq,
    itemId,
    kind,
    payload,
    createdAt,
    status,
    reason,
    sentAt,
    attempts,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seq};
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sent_at'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
    );
  }

  @override
  $OutboxTableTable createAlias(String alias) {
    return $OutboxTableTable(attachedDatabase, alias);
  }
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  final int seq;

  /// The client UUID sent to the server (for rollup checks: the rollup item id).
  final String itemId;

  /// pins | shifts | visits | callbacks | entries | exits | rollup_checks | directory_report
  final String kind;
  final String payload;
  final DateTime createdAt;

  /// pending | sent | rejected
  final String status;
  final String? reason;
  final DateTime? sentAt;
  final int attempts;
  const OutboxRow({
    required this.seq,
    required this.itemId,
    required this.kind,
    required this.payload,
    required this.createdAt,
    required this.status,
    this.reason,
    this.sentAt,
    required this.attempts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['seq'] = Variable<int>(seq);
    map['item_id'] = Variable<String>(itemId);
    map['kind'] = Variable<String>(kind);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    if (!nullToAbsent || sentAt != null) {
      map['sent_at'] = Variable<DateTime>(sentAt);
    }
    map['attempts'] = Variable<int>(attempts);
    return map;
  }

  OutboxTableCompanion toCompanion(bool nullToAbsent) {
    return OutboxTableCompanion(
      seq: Value(seq),
      itemId: Value(itemId),
      kind: Value(kind),
      payload: Value(payload),
      createdAt: Value(createdAt),
      status: Value(status),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      sentAt: sentAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sentAt),
      attempts: Value(attempts),
    );
  }

  factory OutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      seq: serializer.fromJson<int>(json['seq']),
      itemId: serializer.fromJson<String>(json['itemId']),
      kind: serializer.fromJson<String>(json['kind']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      status: serializer.fromJson<String>(json['status']),
      reason: serializer.fromJson<String?>(json['reason']),
      sentAt: serializer.fromJson<DateTime?>(json['sentAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seq': serializer.toJson<int>(seq),
      'itemId': serializer.toJson<String>(itemId),
      'kind': serializer.toJson<String>(kind),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'status': serializer.toJson<String>(status),
      'reason': serializer.toJson<String?>(reason),
      'sentAt': serializer.toJson<DateTime?>(sentAt),
      'attempts': serializer.toJson<int>(attempts),
    };
  }

  OutboxRow copyWith({
    int? seq,
    String? itemId,
    String? kind,
    String? payload,
    DateTime? createdAt,
    String? status,
    Value<String?> reason = const Value.absent(),
    Value<DateTime?> sentAt = const Value.absent(),
    int? attempts,
  }) => OutboxRow(
    seq: seq ?? this.seq,
    itemId: itemId ?? this.itemId,
    kind: kind ?? this.kind,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    status: status ?? this.status,
    reason: reason.present ? reason.value : this.reason,
    sentAt: sentAt.present ? sentAt.value : this.sentAt,
    attempts: attempts ?? this.attempts,
  );
  OutboxRow copyWithCompanion(OutboxTableCompanion data) {
    return OutboxRow(
      seq: data.seq.present ? data.seq.value : this.seq,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      kind: data.kind.present ? data.kind.value : this.kind,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      status: data.status.present ? data.status.value : this.status,
      reason: data.reason.present ? data.reason.value : this.reason,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('seq: $seq, ')
          ..write('itemId: $itemId, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('status: $status, ')
          ..write('reason: $reason, ')
          ..write('sentAt: $sentAt, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    seq,
    itemId,
    kind,
    payload,
    createdAt,
    status,
    reason,
    sentAt,
    attempts,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.seq == this.seq &&
          other.itemId == this.itemId &&
          other.kind == this.kind &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.status == this.status &&
          other.reason == this.reason &&
          other.sentAt == this.sentAt &&
          other.attempts == this.attempts);
}

class OutboxTableCompanion extends UpdateCompanion<OutboxRow> {
  final Value<int> seq;
  final Value<String> itemId;
  final Value<String> kind;
  final Value<String> payload;
  final Value<DateTime> createdAt;
  final Value<String> status;
  final Value<String?> reason;
  final Value<DateTime?> sentAt;
  final Value<int> attempts;
  const OutboxTableCompanion({
    this.seq = const Value.absent(),
    this.itemId = const Value.absent(),
    this.kind = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.status = const Value.absent(),
    this.reason = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.attempts = const Value.absent(),
  });
  OutboxTableCompanion.insert({
    this.seq = const Value.absent(),
    required String itemId,
    required String kind,
    required String payload,
    required DateTime createdAt,
    this.status = const Value.absent(),
    this.reason = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.attempts = const Value.absent(),
  }) : itemId = Value(itemId),
       kind = Value(kind),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<OutboxRow> custom({
    Expression<int>? seq,
    Expression<String>? itemId,
    Expression<String>? kind,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<String>? status,
    Expression<String>? reason,
    Expression<DateTime>? sentAt,
    Expression<int>? attempts,
  }) {
    return RawValuesInsertable({
      if (seq != null) 'seq': seq,
      if (itemId != null) 'item_id': itemId,
      if (kind != null) 'kind': kind,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (status != null) 'status': status,
      if (reason != null) 'reason': reason,
      if (sentAt != null) 'sent_at': sentAt,
      if (attempts != null) 'attempts': attempts,
    });
  }

  OutboxTableCompanion copyWith({
    Value<int>? seq,
    Value<String>? itemId,
    Value<String>? kind,
    Value<String>? payload,
    Value<DateTime>? createdAt,
    Value<String>? status,
    Value<String?>? reason,
    Value<DateTime?>? sentAt,
    Value<int>? attempts,
  }) {
    return OutboxTableCompanion(
      seq: seq ?? this.seq,
      itemId: itemId ?? this.itemId,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      sentAt: sentAt ?? this.sentAt,
      attempts: attempts ?? this.attempts,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<DateTime>(sentAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxTableCompanion(')
          ..write('seq: $seq, ')
          ..write('itemId: $itemId, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('status: $status, ')
          ..write('reason: $reason, ')
          ..write('sentAt: $sentAt, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }
}

class $SelfiesTableTable extends SelfiesTable
    with TableInfo<$SelfiesTableTable, SelfieRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SelfiesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _shiftIdMeta = const VerificationMeta(
    'shiftId',
  );
  @override
  late final GeneratedColumn<String> shiftId = GeneratedColumn<String>(
    'shift_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jpegMeta = const VerificationMeta('jpeg');
  @override
  late final GeneratedColumn<Uint8List> jpeg = GeneratedColumn<Uint8List>(
    'jpeg',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [shiftId, jpeg, createdAt, attempts];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'selfies';
  @override
  VerificationContext validateIntegrity(
    Insertable<SelfieRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('shift_id')) {
      context.handle(
        _shiftIdMeta,
        shiftId.isAcceptableOrUnknown(data['shift_id']!, _shiftIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shiftIdMeta);
    }
    if (data.containsKey('jpeg')) {
      context.handle(
        _jpegMeta,
        jpeg.isAcceptableOrUnknown(data['jpeg']!, _jpegMeta),
      );
    } else if (isInserting) {
      context.missing(_jpegMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {shiftId};
  @override
  SelfieRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SelfieRow(
      shiftId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shift_id'],
      )!,
      jpeg: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}jpeg'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
    );
  }

  @override
  $SelfiesTableTable createAlias(String alias) {
    return $SelfiesTableTable(attachedDatabase, alias);
  }
}

class SelfieRow extends DataClass implements Insertable<SelfieRow> {
  final String shiftId;
  final Uint8List jpeg;
  final DateTime createdAt;
  final int attempts;
  const SelfieRow({
    required this.shiftId,
    required this.jpeg,
    required this.createdAt,
    required this.attempts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['shift_id'] = Variable<String>(shiftId);
    map['jpeg'] = Variable<Uint8List>(jpeg);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    return map;
  }

  SelfiesTableCompanion toCompanion(bool nullToAbsent) {
    return SelfiesTableCompanion(
      shiftId: Value(shiftId),
      jpeg: Value(jpeg),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
    );
  }

  factory SelfieRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SelfieRow(
      shiftId: serializer.fromJson<String>(json['shiftId']),
      jpeg: serializer.fromJson<Uint8List>(json['jpeg']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'shiftId': serializer.toJson<String>(shiftId),
      'jpeg': serializer.toJson<Uint8List>(jpeg),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
    };
  }

  SelfieRow copyWith({
    String? shiftId,
    Uint8List? jpeg,
    DateTime? createdAt,
    int? attempts,
  }) => SelfieRow(
    shiftId: shiftId ?? this.shiftId,
    jpeg: jpeg ?? this.jpeg,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
  );
  SelfieRow copyWithCompanion(SelfiesTableCompanion data) {
    return SelfieRow(
      shiftId: data.shiftId.present ? data.shiftId.value : this.shiftId,
      jpeg: data.jpeg.present ? data.jpeg.value : this.jpeg,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SelfieRow(')
          ..write('shiftId: $shiftId, ')
          ..write('jpeg: $jpeg, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(shiftId, $driftBlobEquality.hash(jpeg), createdAt, attempts);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SelfieRow &&
          other.shiftId == this.shiftId &&
          $driftBlobEquality.equals(other.jpeg, this.jpeg) &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts);
}

class SelfiesTableCompanion extends UpdateCompanion<SelfieRow> {
  final Value<String> shiftId;
  final Value<Uint8List> jpeg;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<int> rowid;
  const SelfiesTableCompanion({
    this.shiftId = const Value.absent(),
    this.jpeg = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SelfiesTableCompanion.insert({
    required String shiftId,
    required Uint8List jpeg,
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : shiftId = Value(shiftId),
       jpeg = Value(jpeg),
       createdAt = Value(createdAt);
  static Insertable<SelfieRow> custom({
    Expression<String>? shiftId,
    Expression<Uint8List>? jpeg,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (shiftId != null) 'shift_id': shiftId,
      if (jpeg != null) 'jpeg': jpeg,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SelfiesTableCompanion copyWith({
    Value<String>? shiftId,
    Value<Uint8List>? jpeg,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<int>? rowid,
  }) {
    return SelfiesTableCompanion(
      shiftId: shiftId ?? this.shiftId,
      jpeg: jpeg ?? this.jpeg,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (shiftId.present) {
      map['shift_id'] = Variable<String>(shiftId.value);
    }
    if (jpeg.present) {
      map['jpeg'] = Variable<Uint8List>(jpeg.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SelfiesTableCompanion(')
          ..write('shiftId: $shiftId, ')
          ..write('jpeg: $jpeg, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PositionsTableTable extends PositionsTable
    with TableInfo<$PositionsTableTable, PositionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PositionsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _shiftIdMeta = const VerificationMeta(
    'shiftId',
  );
  @override
  late final GeneratedColumn<String> shiftId = GeneratedColumn<String>(
    'shift_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accuracyMMeta = const VerificationMeta(
    'accuracyM',
  );
  @override
  late final GeneratedColumn<double> accuracyM = GeneratedColumn<double>(
    'accuracy_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _headingMeta = const VerificationMeta(
    'heading',
  );
  @override
  late final GeneratedColumn<double> heading = GeneratedColumn<double>(
    'heading',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _speedMeta = const VerificationMeta('speed');
  @override
  late final GeneratedColumn<double> speed = GeneratedColumn<double>(
    'speed',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<DateTime> at = GeneratedColumn<DateTime>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    seq,
    shiftId,
    lat,
    lng,
    accuracyM,
    heading,
    speed,
    at,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'positions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PositionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    }
    if (data.containsKey('shift_id')) {
      context.handle(
        _shiftIdMeta,
        shiftId.isAcceptableOrUnknown(data['shift_id']!, _shiftIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shiftIdMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    } else if (isInserting) {
      context.missing(_lngMeta);
    }
    if (data.containsKey('accuracy_m')) {
      context.handle(
        _accuracyMMeta,
        accuracyM.isAcceptableOrUnknown(data['accuracy_m']!, _accuracyMMeta),
      );
    }
    if (data.containsKey('heading')) {
      context.handle(
        _headingMeta,
        heading.isAcceptableOrUnknown(data['heading']!, _headingMeta),
      );
    }
    if (data.containsKey('speed')) {
      context.handle(
        _speedMeta,
        speed.isAcceptableOrUnknown(data['speed']!, _speedMeta),
      );
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seq};
  @override
  PositionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PositionRow(
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      shiftId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shift_id'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      )!,
      accuracyM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy_m'],
      ),
      heading: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}heading'],
      ),
      speed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed'],
      ),
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}at'],
      )!,
    );
  }

  @override
  $PositionsTableTable createAlias(String alias) {
    return $PositionsTableTable(attachedDatabase, alias);
  }
}

class PositionRow extends DataClass implements Insertable<PositionRow> {
  final int seq;
  final String shiftId;
  final double lat;
  final double lng;
  final double? accuracyM;
  final double? heading;
  final double? speed;
  final DateTime at;
  const PositionRow({
    required this.seq,
    required this.shiftId,
    required this.lat,
    required this.lng,
    this.accuracyM,
    this.heading,
    this.speed,
    required this.at,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['seq'] = Variable<int>(seq);
    map['shift_id'] = Variable<String>(shiftId);
    map['lat'] = Variable<double>(lat);
    map['lng'] = Variable<double>(lng);
    if (!nullToAbsent || accuracyM != null) {
      map['accuracy_m'] = Variable<double>(accuracyM);
    }
    if (!nullToAbsent || heading != null) {
      map['heading'] = Variable<double>(heading);
    }
    if (!nullToAbsent || speed != null) {
      map['speed'] = Variable<double>(speed);
    }
    map['at'] = Variable<DateTime>(at);
    return map;
  }

  PositionsTableCompanion toCompanion(bool nullToAbsent) {
    return PositionsTableCompanion(
      seq: Value(seq),
      shiftId: Value(shiftId),
      lat: Value(lat),
      lng: Value(lng),
      accuracyM: accuracyM == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracyM),
      heading: heading == null && nullToAbsent
          ? const Value.absent()
          : Value(heading),
      speed: speed == null && nullToAbsent
          ? const Value.absent()
          : Value(speed),
      at: Value(at),
    );
  }

  factory PositionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PositionRow(
      seq: serializer.fromJson<int>(json['seq']),
      shiftId: serializer.fromJson<String>(json['shiftId']),
      lat: serializer.fromJson<double>(json['lat']),
      lng: serializer.fromJson<double>(json['lng']),
      accuracyM: serializer.fromJson<double?>(json['accuracyM']),
      heading: serializer.fromJson<double?>(json['heading']),
      speed: serializer.fromJson<double?>(json['speed']),
      at: serializer.fromJson<DateTime>(json['at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seq': serializer.toJson<int>(seq),
      'shiftId': serializer.toJson<String>(shiftId),
      'lat': serializer.toJson<double>(lat),
      'lng': serializer.toJson<double>(lng),
      'accuracyM': serializer.toJson<double?>(accuracyM),
      'heading': serializer.toJson<double?>(heading),
      'speed': serializer.toJson<double?>(speed),
      'at': serializer.toJson<DateTime>(at),
    };
  }

  PositionRow copyWith({
    int? seq,
    String? shiftId,
    double? lat,
    double? lng,
    Value<double?> accuracyM = const Value.absent(),
    Value<double?> heading = const Value.absent(),
    Value<double?> speed = const Value.absent(),
    DateTime? at,
  }) => PositionRow(
    seq: seq ?? this.seq,
    shiftId: shiftId ?? this.shiftId,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    accuracyM: accuracyM.present ? accuracyM.value : this.accuracyM,
    heading: heading.present ? heading.value : this.heading,
    speed: speed.present ? speed.value : this.speed,
    at: at ?? this.at,
  );
  PositionRow copyWithCompanion(PositionsTableCompanion data) {
    return PositionRow(
      seq: data.seq.present ? data.seq.value : this.seq,
      shiftId: data.shiftId.present ? data.shiftId.value : this.shiftId,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      accuracyM: data.accuracyM.present ? data.accuracyM.value : this.accuracyM,
      heading: data.heading.present ? data.heading.value : this.heading,
      speed: data.speed.present ? data.speed.value : this.speed,
      at: data.at.present ? data.at.value : this.at,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PositionRow(')
          ..write('seq: $seq, ')
          ..write('shiftId: $shiftId, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('heading: $heading, ')
          ..write('speed: $speed, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(seq, shiftId, lat, lng, accuracyM, heading, speed, at);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PositionRow &&
          other.seq == this.seq &&
          other.shiftId == this.shiftId &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.accuracyM == this.accuracyM &&
          other.heading == this.heading &&
          other.speed == this.speed &&
          other.at == this.at);
}

class PositionsTableCompanion extends UpdateCompanion<PositionRow> {
  final Value<int> seq;
  final Value<String> shiftId;
  final Value<double> lat;
  final Value<double> lng;
  final Value<double?> accuracyM;
  final Value<double?> heading;
  final Value<double?> speed;
  final Value<DateTime> at;
  const PositionsTableCompanion({
    this.seq = const Value.absent(),
    this.shiftId = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.accuracyM = const Value.absent(),
    this.heading = const Value.absent(),
    this.speed = const Value.absent(),
    this.at = const Value.absent(),
  });
  PositionsTableCompanion.insert({
    this.seq = const Value.absent(),
    required String shiftId,
    required double lat,
    required double lng,
    this.accuracyM = const Value.absent(),
    this.heading = const Value.absent(),
    this.speed = const Value.absent(),
    required DateTime at,
  }) : shiftId = Value(shiftId),
       lat = Value(lat),
       lng = Value(lng),
       at = Value(at);
  static Insertable<PositionRow> custom({
    Expression<int>? seq,
    Expression<String>? shiftId,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<double>? accuracyM,
    Expression<double>? heading,
    Expression<double>? speed,
    Expression<DateTime>? at,
  }) {
    return RawValuesInsertable({
      if (seq != null) 'seq': seq,
      if (shiftId != null) 'shift_id': shiftId,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      if (at != null) 'at': at,
    });
  }

  PositionsTableCompanion copyWith({
    Value<int>? seq,
    Value<String>? shiftId,
    Value<double>? lat,
    Value<double>? lng,
    Value<double?>? accuracyM,
    Value<double?>? heading,
    Value<double?>? speed,
    Value<DateTime>? at,
  }) {
    return PositionsTableCompanion(
      seq: seq ?? this.seq,
      shiftId: shiftId ?? this.shiftId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      accuracyM: accuracyM ?? this.accuracyM,
      heading: heading ?? this.heading,
      speed: speed ?? this.speed,
      at: at ?? this.at,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (shiftId.present) {
      map['shift_id'] = Variable<String>(shiftId.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (accuracyM.present) {
      map['accuracy_m'] = Variable<double>(accuracyM.value);
    }
    if (heading.present) {
      map['heading'] = Variable<double>(heading.value);
    }
    if (speed.present) {
      map['speed'] = Variable<double>(speed.value);
    }
    if (at.present) {
      map['at'] = Variable<DateTime>(at.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PositionsTableCompanion(')
          ..write('seq: $seq, ')
          ..write('shiftId: $shiftId, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('accuracyM: $accuracyM, ')
          ..write('heading: $heading, ')
          ..write('speed: $speed, ')
          ..write('at: $at')
          ..write(')'))
        .toString();
  }
}

class $MediaTableTable extends MediaTable
    with TableInfo<$MediaTableTable, MediaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refMeta = const VerificationMeta('ref');
  @override
  late final GeneratedColumn<String> ref = GeneratedColumn<String>(
    'ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    bytes,
    contentType,
    ref,
    createdAt,
    attempts,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentTypeMeta);
    }
    if (data.containsKey('ref')) {
      context.handle(
        _refMeta,
        ref.isAcceptableOrUnknown(data['ref']!, _refMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      )!,
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      )!,
      ref: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
    );
  }

  @override
  $MediaTableTable createAlias(String alias) {
    return $MediaTableTable(attachedDatabase, alias);
  }
}

class MediaRow extends DataClass implements Insertable<MediaRow> {
  /// The clip's or photo's own UUID, named on the record (`name_clip_id`, `visitor_photo_id`...).
  final String id;

  /// clip | visitor | plate
  final String kind;
  final Uint8List bytes;
  final String contentType;

  /// The record that names it (an entry or a visit), so Leaving can play a clip back.
  final String? ref;
  final DateTime createdAt;
  final int attempts;
  const MediaRow({
    required this.id,
    required this.kind,
    required this.bytes,
    required this.contentType,
    this.ref,
    required this.createdAt,
    required this.attempts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['bytes'] = Variable<Uint8List>(bytes);
    map['content_type'] = Variable<String>(contentType);
    if (!nullToAbsent || ref != null) {
      map['ref'] = Variable<String>(ref);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    return map;
  }

  MediaTableCompanion toCompanion(bool nullToAbsent) {
    return MediaTableCompanion(
      id: Value(id),
      kind: Value(kind),
      bytes: Value(bytes),
      contentType: Value(contentType),
      ref: ref == null && nullToAbsent ? const Value.absent() : Value(ref),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
    );
  }

  factory MediaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaRow(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
      contentType: serializer.fromJson<String>(json['contentType']),
      ref: serializer.fromJson<String?>(json['ref']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'bytes': serializer.toJson<Uint8List>(bytes),
      'contentType': serializer.toJson<String>(contentType),
      'ref': serializer.toJson<String?>(ref),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
    };
  }

  MediaRow copyWith({
    String? id,
    String? kind,
    Uint8List? bytes,
    String? contentType,
    Value<String?> ref = const Value.absent(),
    DateTime? createdAt,
    int? attempts,
  }) => MediaRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    bytes: bytes ?? this.bytes,
    contentType: contentType ?? this.contentType,
    ref: ref.present ? ref.value : this.ref,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
  );
  MediaRow copyWithCompanion(MediaTableCompanion data) {
    return MediaRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      ref: data.ref.present ? data.ref.value : this.ref,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('bytes: $bytes, ')
          ..write('contentType: $contentType, ')
          ..write('ref: $ref, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    $driftBlobEquality.hash(bytes),
    contentType,
    ref,
    createdAt,
    attempts,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          $driftBlobEquality.equals(other.bytes, this.bytes) &&
          other.contentType == this.contentType &&
          other.ref == this.ref &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts);
}

class MediaTableCompanion extends UpdateCompanion<MediaRow> {
  final Value<String> id;
  final Value<String> kind;
  final Value<Uint8List> bytes;
  final Value<String> contentType;
  final Value<String?> ref;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<int> rowid;
  const MediaTableCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.bytes = const Value.absent(),
    this.contentType = const Value.absent(),
    this.ref = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaTableCompanion.insert({
    required String id,
    required String kind,
    required Uint8List bytes,
    required String contentType,
    this.ref = const Value.absent(),
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       bytes = Value(bytes),
       contentType = Value(contentType),
       createdAt = Value(createdAt);
  static Insertable<MediaRow> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<Uint8List>? bytes,
    Expression<String>? contentType,
    Expression<String>? ref,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (bytes != null) 'bytes': bytes,
      if (contentType != null) 'content_type': contentType,
      if (ref != null) 'ref': ref,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaTableCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<Uint8List>? bytes,
    Value<String>? contentType,
    Value<String?>? ref,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<int>? rowid,
  }) {
    return MediaTableCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      bytes: bytes ?? this.bytes,
      contentType: contentType ?? this.contentType,
      ref: ref ?? this.ref,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (ref.present) {
      map['ref'] = Variable<String>(ref.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaTableCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('bytes: $bytes, ')
          ..write('contentType: $contentType, ')
          ..write('ref: $ref, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$GateDatabase extends GeneratedDatabase {
  _$GateDatabase(QueryExecutor e) : super(e);
  $GateDatabaseManager get managers => $GateDatabaseManager(this);
  late final $HomesTableTable homesTable = $HomesTableTable(this);
  late final $ResidentsTableTable residentsTable = $ResidentsTableTable(this);
  late final $NumbersTableTable numbersTable = $NumbersTableTable(this);
  late final $VisitsTableTable visitsTable = $VisitsTableTable(this);
  late final $DirectoryTableTable directoryTable = $DirectoryTableTable(this);
  late final $GatesTableTable gatesTable = $GatesTableTable(this);
  late final $GuardsTableTable guardsTable = $GuardsTableTable(this);
  late final $VehiclesTableTable vehiclesTable = $VehiclesTableTable(this);
  late final $MetaTableTable metaTable = $MetaTableTable(this);
  late final $OutboxTableTable outboxTable = $OutboxTableTable(this);
  late final $SelfiesTableTable selfiesTable = $SelfiesTableTable(this);
  late final $PositionsTableTable positionsTable = $PositionsTableTable(this);
  late final $MediaTableTable mediaTable = $MediaTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    homesTable,
    residentsTable,
    numbersTable,
    visitsTable,
    directoryTable,
    gatesTable,
    guardsTable,
    vehiclesTable,
    metaTable,
    outboxTable,
    selfiesTable,
    positionsTable,
    mediaTable,
  ];
}

typedef $$HomesTableTableCreateCompanionBuilder =
    HomesTableCompanion Function({
      required String id,
      required String label,
      required String street,
      required String zone,
      required String address,
      required bool callbackRequired,
      Value<String?> houseCodeHash,
      Value<int> rowid,
    });
typedef $$HomesTableTableUpdateCompanionBuilder =
    HomesTableCompanion Function({
      Value<String> id,
      Value<String> label,
      Value<String> street,
      Value<String> zone,
      Value<String> address,
      Value<bool> callbackRequired,
      Value<String?> houseCodeHash,
      Value<int> rowid,
    });

class $$HomesTableTableFilterComposer
    extends Composer<_$GateDatabase, $HomesTableTable> {
  $$HomesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get street => $composableBuilder(
    column: $table.street,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get zone => $composableBuilder(
    column: $table.zone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get callbackRequired => $composableBuilder(
    column: $table.callbackRequired,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get houseCodeHash => $composableBuilder(
    column: $table.houseCodeHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HomesTableTableOrderingComposer
    extends Composer<_$GateDatabase, $HomesTableTable> {
  $$HomesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get street => $composableBuilder(
    column: $table.street,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get zone => $composableBuilder(
    column: $table.zone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get callbackRequired => $composableBuilder(
    column: $table.callbackRequired,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get houseCodeHash => $composableBuilder(
    column: $table.houseCodeHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HomesTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $HomesTableTable> {
  $$HomesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get street =>
      $composableBuilder(column: $table.street, builder: (column) => column);

  GeneratedColumn<String> get zone =>
      $composableBuilder(column: $table.zone, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<bool> get callbackRequired => $composableBuilder(
    column: $table.callbackRequired,
    builder: (column) => column,
  );

  GeneratedColumn<String> get houseCodeHash => $composableBuilder(
    column: $table.houseCodeHash,
    builder: (column) => column,
  );
}

class $$HomesTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $HomesTableTable,
          HomeRow,
          $$HomesTableTableFilterComposer,
          $$HomesTableTableOrderingComposer,
          $$HomesTableTableAnnotationComposer,
          $$HomesTableTableCreateCompanionBuilder,
          $$HomesTableTableUpdateCompanionBuilder,
          (HomeRow, BaseReferences<_$GateDatabase, $HomesTableTable, HomeRow>),
          HomeRow,
          PrefetchHooks Function()
        > {
  $$HomesTableTableTableManager(_$GateDatabase db, $HomesTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HomesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HomesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HomesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String> street = const Value.absent(),
                Value<String> zone = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<bool> callbackRequired = const Value.absent(),
                Value<String?> houseCodeHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HomesTableCompanion(
                id: id,
                label: label,
                street: street,
                zone: zone,
                address: address,
                callbackRequired: callbackRequired,
                houseCodeHash: houseCodeHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String label,
                required String street,
                required String zone,
                required String address,
                required bool callbackRequired,
                Value<String?> houseCodeHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HomesTableCompanion.insert(
                id: id,
                label: label,
                street: street,
                zone: zone,
                address: address,
                callbackRequired: callbackRequired,
                houseCodeHash: houseCodeHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HomesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $HomesTableTable,
      HomeRow,
      $$HomesTableTableFilterComposer,
      $$HomesTableTableOrderingComposer,
      $$HomesTableTableAnnotationComposer,
      $$HomesTableTableCreateCompanionBuilder,
      $$HomesTableTableUpdateCompanionBuilder,
      (HomeRow, BaseReferences<_$GateDatabase, $HomesTableTable, HomeRow>),
      HomeRow,
      PrefetchHooks Function()
    >;
typedef $$ResidentsTableTableCreateCompanionBuilder =
    ResidentsTableCompanion Function({
      required String id,
      required String homeId,
      required String name,
      required String contactPref,
      required int position,
      Value<int> rowid,
    });
typedef $$ResidentsTableTableUpdateCompanionBuilder =
    ResidentsTableCompanion Function({
      Value<String> id,
      Value<String> homeId,
      Value<String> name,
      Value<String> contactPref,
      Value<int> position,
      Value<int> rowid,
    });

class $$ResidentsTableTableFilterComposer
    extends Composer<_$GateDatabase, $ResidentsTableTable> {
  $$ResidentsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactPref => $composableBuilder(
    column: $table.contactPref,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ResidentsTableTableOrderingComposer
    extends Composer<_$GateDatabase, $ResidentsTableTable> {
  $$ResidentsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactPref => $composableBuilder(
    column: $table.contactPref,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ResidentsTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $ResidentsTableTable> {
  $$ResidentsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get homeId =>
      $composableBuilder(column: $table.homeId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get contactPref => $composableBuilder(
    column: $table.contactPref,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$ResidentsTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $ResidentsTableTable,
          ResidentRow,
          $$ResidentsTableTableFilterComposer,
          $$ResidentsTableTableOrderingComposer,
          $$ResidentsTableTableAnnotationComposer,
          $$ResidentsTableTableCreateCompanionBuilder,
          $$ResidentsTableTableUpdateCompanionBuilder,
          (
            ResidentRow,
            BaseReferences<_$GateDatabase, $ResidentsTableTable, ResidentRow>,
          ),
          ResidentRow,
          PrefetchHooks Function()
        > {
  $$ResidentsTableTableTableManager(
    _$GateDatabase db,
    $ResidentsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ResidentsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ResidentsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ResidentsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> homeId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> contactPref = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResidentsTableCompanion(
                id: id,
                homeId: homeId,
                name: name,
                contactPref: contactPref,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String homeId,
                required String name,
                required String contactPref,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => ResidentsTableCompanion.insert(
                id: id,
                homeId: homeId,
                name: name,
                contactPref: contactPref,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ResidentsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $ResidentsTableTable,
      ResidentRow,
      $$ResidentsTableTableFilterComposer,
      $$ResidentsTableTableOrderingComposer,
      $$ResidentsTableTableAnnotationComposer,
      $$ResidentsTableTableCreateCompanionBuilder,
      $$ResidentsTableTableUpdateCompanionBuilder,
      (
        ResidentRow,
        BaseReferences<_$GateDatabase, $ResidentsTableTable, ResidentRow>,
      ),
      ResidentRow,
      PrefetchHooks Function()
    >;
typedef $$NumbersTableTableCreateCompanionBuilder =
    NumbersTableCompanion Function({
      required String id,
      required String residentId,
      required String e164,
      required String last4,
      required bool isPrimary,
      Value<int> rowid,
    });
typedef $$NumbersTableTableUpdateCompanionBuilder =
    NumbersTableCompanion Function({
      Value<String> id,
      Value<String> residentId,
      Value<String> e164,
      Value<String> last4,
      Value<bool> isPrimary,
      Value<int> rowid,
    });

class $$NumbersTableTableFilterComposer
    extends Composer<_$GateDatabase, $NumbersTableTable> {
  $$NumbersTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get residentId => $composableBuilder(
    column: $table.residentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get e164 => $composableBuilder(
    column: $table.e164,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get last4 => $composableBuilder(
    column: $table.last4,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NumbersTableTableOrderingComposer
    extends Composer<_$GateDatabase, $NumbersTableTable> {
  $$NumbersTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get residentId => $composableBuilder(
    column: $table.residentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get e164 => $composableBuilder(
    column: $table.e164,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get last4 => $composableBuilder(
    column: $table.last4,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPrimary => $composableBuilder(
    column: $table.isPrimary,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NumbersTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $NumbersTableTable> {
  $$NumbersTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get residentId => $composableBuilder(
    column: $table.residentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get e164 =>
      $composableBuilder(column: $table.e164, builder: (column) => column);

  GeneratedColumn<String> get last4 =>
      $composableBuilder(column: $table.last4, builder: (column) => column);

  GeneratedColumn<bool> get isPrimary =>
      $composableBuilder(column: $table.isPrimary, builder: (column) => column);
}

class $$NumbersTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $NumbersTableTable,
          NumberRow,
          $$NumbersTableTableFilterComposer,
          $$NumbersTableTableOrderingComposer,
          $$NumbersTableTableAnnotationComposer,
          $$NumbersTableTableCreateCompanionBuilder,
          $$NumbersTableTableUpdateCompanionBuilder,
          (
            NumberRow,
            BaseReferences<_$GateDatabase, $NumbersTableTable, NumberRow>,
          ),
          NumberRow,
          PrefetchHooks Function()
        > {
  $$NumbersTableTableTableManager(_$GateDatabase db, $NumbersTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NumbersTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NumbersTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NumbersTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> residentId = const Value.absent(),
                Value<String> e164 = const Value.absent(),
                Value<String> last4 = const Value.absent(),
                Value<bool> isPrimary = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NumbersTableCompanion(
                id: id,
                residentId: residentId,
                e164: e164,
                last4: last4,
                isPrimary: isPrimary,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String residentId,
                required String e164,
                required String last4,
                required bool isPrimary,
                Value<int> rowid = const Value.absent(),
              }) => NumbersTableCompanion.insert(
                id: id,
                residentId: residentId,
                e164: e164,
                last4: last4,
                isPrimary: isPrimary,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NumbersTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $NumbersTableTable,
      NumberRow,
      $$NumbersTableTableFilterComposer,
      $$NumbersTableTableOrderingComposer,
      $$NumbersTableTableAnnotationComposer,
      $$NumbersTableTableCreateCompanionBuilder,
      $$NumbersTableTableUpdateCompanionBuilder,
      (
        NumberRow,
        BaseReferences<_$GateDatabase, $NumbersTableTable, NumberRow>,
      ),
      NumberRow,
      PrefetchHooks Function()
    >;
typedef $$VisitsTableTableCreateCompanionBuilder =
    VisitsTableCompanion Function({
      required String id,
      required String homeId,
      Value<String?> residentId,
      required String guestName,
      required int windowStart,
      required int windowEnd,
      Value<int?> keyVersion,
      required bool codeIssued,
      required String source,
      required String state,
      Value<String?> expectedUntil,
      Value<String?> entryId,
      Value<String?> enteredAt,
      Value<int> rowid,
    });
typedef $$VisitsTableTableUpdateCompanionBuilder =
    VisitsTableCompanion Function({
      Value<String> id,
      Value<String> homeId,
      Value<String?> residentId,
      Value<String> guestName,
      Value<int> windowStart,
      Value<int> windowEnd,
      Value<int?> keyVersion,
      Value<bool> codeIssued,
      Value<String> source,
      Value<String> state,
      Value<String?> expectedUntil,
      Value<String?> entryId,
      Value<String?> enteredAt,
      Value<int> rowid,
    });

class $$VisitsTableTableFilterComposer
    extends Composer<_$GateDatabase, $VisitsTableTable> {
  $$VisitsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get residentId => $composableBuilder(
    column: $table.residentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get guestName => $composableBuilder(
    column: $table.guestName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get windowStart => $composableBuilder(
    column: $table.windowStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get windowEnd => $composableBuilder(
    column: $table.windowEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get keyVersion => $composableBuilder(
    column: $table.keyVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get codeIssued => $composableBuilder(
    column: $table.codeIssued,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expectedUntil => $composableBuilder(
    column: $table.expectedUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get enteredAt => $composableBuilder(
    column: $table.enteredAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VisitsTableTableOrderingComposer
    extends Composer<_$GateDatabase, $VisitsTableTable> {
  $$VisitsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get residentId => $composableBuilder(
    column: $table.residentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get guestName => $composableBuilder(
    column: $table.guestName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get windowStart => $composableBuilder(
    column: $table.windowStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get windowEnd => $composableBuilder(
    column: $table.windowEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get keyVersion => $composableBuilder(
    column: $table.keyVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get codeIssued => $composableBuilder(
    column: $table.codeIssued,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expectedUntil => $composableBuilder(
    column: $table.expectedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get enteredAt => $composableBuilder(
    column: $table.enteredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VisitsTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $VisitsTableTable> {
  $$VisitsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get homeId =>
      $composableBuilder(column: $table.homeId, builder: (column) => column);

  GeneratedColumn<String> get residentId => $composableBuilder(
    column: $table.residentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get guestName =>
      $composableBuilder(column: $table.guestName, builder: (column) => column);

  GeneratedColumn<int> get windowStart => $composableBuilder(
    column: $table.windowStart,
    builder: (column) => column,
  );

  GeneratedColumn<int> get windowEnd =>
      $composableBuilder(column: $table.windowEnd, builder: (column) => column);

  GeneratedColumn<int> get keyVersion => $composableBuilder(
    column: $table.keyVersion,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get codeIssued => $composableBuilder(
    column: $table.codeIssued,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get expectedUntil => $composableBuilder(
    column: $table.expectedUntil,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get enteredAt =>
      $composableBuilder(column: $table.enteredAt, builder: (column) => column);
}

class $$VisitsTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $VisitsTableTable,
          VisitRow,
          $$VisitsTableTableFilterComposer,
          $$VisitsTableTableOrderingComposer,
          $$VisitsTableTableAnnotationComposer,
          $$VisitsTableTableCreateCompanionBuilder,
          $$VisitsTableTableUpdateCompanionBuilder,
          (
            VisitRow,
            BaseReferences<_$GateDatabase, $VisitsTableTable, VisitRow>,
          ),
          VisitRow,
          PrefetchHooks Function()
        > {
  $$VisitsTableTableTableManager(_$GateDatabase db, $VisitsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VisitsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VisitsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VisitsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> homeId = const Value.absent(),
                Value<String?> residentId = const Value.absent(),
                Value<String> guestName = const Value.absent(),
                Value<int> windowStart = const Value.absent(),
                Value<int> windowEnd = const Value.absent(),
                Value<int?> keyVersion = const Value.absent(),
                Value<bool> codeIssued = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> expectedUntil = const Value.absent(),
                Value<String?> entryId = const Value.absent(),
                Value<String?> enteredAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisitsTableCompanion(
                id: id,
                homeId: homeId,
                residentId: residentId,
                guestName: guestName,
                windowStart: windowStart,
                windowEnd: windowEnd,
                keyVersion: keyVersion,
                codeIssued: codeIssued,
                source: source,
                state: state,
                expectedUntil: expectedUntil,
                entryId: entryId,
                enteredAt: enteredAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String homeId,
                Value<String?> residentId = const Value.absent(),
                required String guestName,
                required int windowStart,
                required int windowEnd,
                Value<int?> keyVersion = const Value.absent(),
                required bool codeIssued,
                required String source,
                required String state,
                Value<String?> expectedUntil = const Value.absent(),
                Value<String?> entryId = const Value.absent(),
                Value<String?> enteredAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VisitsTableCompanion.insert(
                id: id,
                homeId: homeId,
                residentId: residentId,
                guestName: guestName,
                windowStart: windowStart,
                windowEnd: windowEnd,
                keyVersion: keyVersion,
                codeIssued: codeIssued,
                source: source,
                state: state,
                expectedUntil: expectedUntil,
                entryId: entryId,
                enteredAt: enteredAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VisitsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $VisitsTableTable,
      VisitRow,
      $$VisitsTableTableFilterComposer,
      $$VisitsTableTableOrderingComposer,
      $$VisitsTableTableAnnotationComposer,
      $$VisitsTableTableCreateCompanionBuilder,
      $$VisitsTableTableUpdateCompanionBuilder,
      (VisitRow, BaseReferences<_$GateDatabase, $VisitsTableTable, VisitRow>),
      VisitRow,
      PrefetchHooks Function()
    >;
typedef $$DirectoryTableTableCreateCompanionBuilder =
    DirectoryTableCompanion Function({
      required String id,
      required int position,
      required String category,
      required String name,
      required String number,
      Value<String?> verifiedAt,
      required bool reportedNotWorking,
      Value<int> rowid,
    });
typedef $$DirectoryTableTableUpdateCompanionBuilder =
    DirectoryTableCompanion Function({
      Value<String> id,
      Value<int> position,
      Value<String> category,
      Value<String> name,
      Value<String> number,
      Value<String?> verifiedAt,
      Value<bool> reportedNotWorking,
      Value<int> rowid,
    });

class $$DirectoryTableTableFilterComposer
    extends Composer<_$GateDatabase, $DirectoryTableTable> {
  $$DirectoryTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reportedNotWorking => $composableBuilder(
    column: $table.reportedNotWorking,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DirectoryTableTableOrderingComposer
    extends Composer<_$GateDatabase, $DirectoryTableTable> {
  $$DirectoryTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reportedNotWorking => $composableBuilder(
    column: $table.reportedNotWorking,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DirectoryTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $DirectoryTableTable> {
  $$DirectoryTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get verifiedAt => $composableBuilder(
    column: $table.verifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get reportedNotWorking => $composableBuilder(
    column: $table.reportedNotWorking,
    builder: (column) => column,
  );
}

class $$DirectoryTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $DirectoryTableTable,
          DirectoryRow,
          $$DirectoryTableTableFilterComposer,
          $$DirectoryTableTableOrderingComposer,
          $$DirectoryTableTableAnnotationComposer,
          $$DirectoryTableTableCreateCompanionBuilder,
          $$DirectoryTableTableUpdateCompanionBuilder,
          (
            DirectoryRow,
            BaseReferences<_$GateDatabase, $DirectoryTableTable, DirectoryRow>,
          ),
          DirectoryRow,
          PrefetchHooks Function()
        > {
  $$DirectoryTableTableTableManager(
    _$GateDatabase db,
    $DirectoryTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DirectoryTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DirectoryTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DirectoryTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> number = const Value.absent(),
                Value<String?> verifiedAt = const Value.absent(),
                Value<bool> reportedNotWorking = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DirectoryTableCompanion(
                id: id,
                position: position,
                category: category,
                name: name,
                number: number,
                verifiedAt: verifiedAt,
                reportedNotWorking: reportedNotWorking,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int position,
                required String category,
                required String name,
                required String number,
                Value<String?> verifiedAt = const Value.absent(),
                required bool reportedNotWorking,
                Value<int> rowid = const Value.absent(),
              }) => DirectoryTableCompanion.insert(
                id: id,
                position: position,
                category: category,
                name: name,
                number: number,
                verifiedAt: verifiedAt,
                reportedNotWorking: reportedNotWorking,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DirectoryTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $DirectoryTableTable,
      DirectoryRow,
      $$DirectoryTableTableFilterComposer,
      $$DirectoryTableTableOrderingComposer,
      $$DirectoryTableTableAnnotationComposer,
      $$DirectoryTableTableCreateCompanionBuilder,
      $$DirectoryTableTableUpdateCompanionBuilder,
      (
        DirectoryRow,
        BaseReferences<_$GateDatabase, $DirectoryTableTable, DirectoryRow>,
      ),
      DirectoryRow,
      PrefetchHooks Function()
    >;
typedef $$GatesTableTableCreateCompanionBuilder =
    GatesTableCompanion Function({
      required String id,
      required String name,
      Value<int> rowid,
    });
typedef $$GatesTableTableUpdateCompanionBuilder =
    GatesTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> rowid,
    });

class $$GatesTableTableFilterComposer
    extends Composer<_$GateDatabase, $GatesTableTable> {
  $$GatesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GatesTableTableOrderingComposer
    extends Composer<_$GateDatabase, $GatesTableTable> {
  $$GatesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GatesTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $GatesTableTable> {
  $$GatesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);
}

class $$GatesTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $GatesTableTable,
          GateRow,
          $$GatesTableTableFilterComposer,
          $$GatesTableTableOrderingComposer,
          $$GatesTableTableAnnotationComposer,
          $$GatesTableTableCreateCompanionBuilder,
          $$GatesTableTableUpdateCompanionBuilder,
          (GateRow, BaseReferences<_$GateDatabase, $GatesTableTable, GateRow>),
          GateRow,
          PrefetchHooks Function()
        > {
  $$GatesTableTableTableManager(_$GateDatabase db, $GatesTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GatesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GatesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GatesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GatesTableCompanion(id: id, name: name, rowid: rowid),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> rowid = const Value.absent(),
              }) =>
                  GatesTableCompanion.insert(id: id, name: name, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GatesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $GatesTableTable,
      GateRow,
      $$GatesTableTableFilterComposer,
      $$GatesTableTableOrderingComposer,
      $$GatesTableTableAnnotationComposer,
      $$GatesTableTableCreateCompanionBuilder,
      $$GatesTableTableUpdateCompanionBuilder,
      (GateRow, BaseReferences<_$GateDatabase, $GatesTableTable, GateRow>),
      GateRow,
      PrefetchHooks Function()
    >;
typedef $$GuardsTableTableCreateCompanionBuilder =
    GuardsTableCompanion Function({
      required String id,
      required String name,
      Value<String> role,
      Value<String?> pinHash,
      Value<String?> pinResetAt,
      Value<bool> consent,
      Value<int> position,
      Value<int> rowid,
    });
typedef $$GuardsTableTableUpdateCompanionBuilder =
    GuardsTableCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> role,
      Value<String?> pinHash,
      Value<String?> pinResetAt,
      Value<bool> consent,
      Value<int> position,
      Value<int> rowid,
    });

class $$GuardsTableTableFilterComposer
    extends Composer<_$GateDatabase, $GuardsTableTable> {
  $$GuardsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pinHash => $composableBuilder(
    column: $table.pinHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pinResetAt => $composableBuilder(
    column: $table.pinResetAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get consent => $composableBuilder(
    column: $table.consent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GuardsTableTableOrderingComposer
    extends Composer<_$GateDatabase, $GuardsTableTable> {
  $$GuardsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pinHash => $composableBuilder(
    column: $table.pinHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pinResetAt => $composableBuilder(
    column: $table.pinResetAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get consent => $composableBuilder(
    column: $table.consent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GuardsTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $GuardsTableTable> {
  $$GuardsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get pinHash =>
      $composableBuilder(column: $table.pinHash, builder: (column) => column);

  GeneratedColumn<String> get pinResetAt => $composableBuilder(
    column: $table.pinResetAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get consent =>
      $composableBuilder(column: $table.consent, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$GuardsTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $GuardsTableTable,
          GuardRow,
          $$GuardsTableTableFilterComposer,
          $$GuardsTableTableOrderingComposer,
          $$GuardsTableTableAnnotationComposer,
          $$GuardsTableTableCreateCompanionBuilder,
          $$GuardsTableTableUpdateCompanionBuilder,
          (
            GuardRow,
            BaseReferences<_$GateDatabase, $GuardsTableTable, GuardRow>,
          ),
          GuardRow,
          PrefetchHooks Function()
        > {
  $$GuardsTableTableTableManager(_$GateDatabase db, $GuardsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GuardsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GuardsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GuardsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String?> pinHash = const Value.absent(),
                Value<String?> pinResetAt = const Value.absent(),
                Value<bool> consent = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GuardsTableCompanion(
                id: id,
                name: name,
                role: role,
                pinHash: pinHash,
                pinResetAt: pinResetAt,
                consent: consent,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> role = const Value.absent(),
                Value<String?> pinHash = const Value.absent(),
                Value<String?> pinResetAt = const Value.absent(),
                Value<bool> consent = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GuardsTableCompanion.insert(
                id: id,
                name: name,
                role: role,
                pinHash: pinHash,
                pinResetAt: pinResetAt,
                consent: consent,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GuardsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $GuardsTableTable,
      GuardRow,
      $$GuardsTableTableFilterComposer,
      $$GuardsTableTableOrderingComposer,
      $$GuardsTableTableAnnotationComposer,
      $$GuardsTableTableCreateCompanionBuilder,
      $$GuardsTableTableUpdateCompanionBuilder,
      (GuardRow, BaseReferences<_$GateDatabase, $GuardsTableTable, GuardRow>),
      GuardRow,
      PrefetchHooks Function()
    >;
typedef $$VehiclesTableTableCreateCompanionBuilder =
    VehiclesTableCompanion Function({
      Value<int> seq,
      required String homeId,
      required String plate,
      Value<String?> description,
    });
typedef $$VehiclesTableTableUpdateCompanionBuilder =
    VehiclesTableCompanion Function({
      Value<int> seq,
      Value<String> homeId,
      Value<String> plate,
      Value<String?> description,
    });

class $$VehiclesTableTableFilterComposer
    extends Composer<_$GateDatabase, $VehiclesTableTable> {
  $$VehiclesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plate => $composableBuilder(
    column: $table.plate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VehiclesTableTableOrderingComposer
    extends Composer<_$GateDatabase, $VehiclesTableTable> {
  $$VehiclesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get homeId => $composableBuilder(
    column: $table.homeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plate => $composableBuilder(
    column: $table.plate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VehiclesTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $VehiclesTableTable> {
  $$VehiclesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get homeId =>
      $composableBuilder(column: $table.homeId, builder: (column) => column);

  GeneratedColumn<String> get plate =>
      $composableBuilder(column: $table.plate, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );
}

class $$VehiclesTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $VehiclesTableTable,
          VehicleRow,
          $$VehiclesTableTableFilterComposer,
          $$VehiclesTableTableOrderingComposer,
          $$VehiclesTableTableAnnotationComposer,
          $$VehiclesTableTableCreateCompanionBuilder,
          $$VehiclesTableTableUpdateCompanionBuilder,
          (
            VehicleRow,
            BaseReferences<_$GateDatabase, $VehiclesTableTable, VehicleRow>,
          ),
          VehicleRow,
          PrefetchHooks Function()
        > {
  $$VehiclesTableTableTableManager(_$GateDatabase db, $VehiclesTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VehiclesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VehiclesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VehiclesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                Value<String> homeId = const Value.absent(),
                Value<String> plate = const Value.absent(),
                Value<String?> description = const Value.absent(),
              }) => VehiclesTableCompanion(
                seq: seq,
                homeId: homeId,
                plate: plate,
                description: description,
              ),
          createCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                required String homeId,
                required String plate,
                Value<String?> description = const Value.absent(),
              }) => VehiclesTableCompanion.insert(
                seq: seq,
                homeId: homeId,
                plate: plate,
                description: description,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VehiclesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $VehiclesTableTable,
      VehicleRow,
      $$VehiclesTableTableFilterComposer,
      $$VehiclesTableTableOrderingComposer,
      $$VehiclesTableTableAnnotationComposer,
      $$VehiclesTableTableCreateCompanionBuilder,
      $$VehiclesTableTableUpdateCompanionBuilder,
      (
        VehicleRow,
        BaseReferences<_$GateDatabase, $VehiclesTableTable, VehicleRow>,
      ),
      VehicleRow,
      PrefetchHooks Function()
    >;
typedef $$MetaTableTableCreateCompanionBuilder =
    MetaTableCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$MetaTableTableUpdateCompanionBuilder =
    MetaTableCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$MetaTableTableFilterComposer
    extends Composer<_$GateDatabase, $MetaTableTable> {
  $$MetaTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MetaTableTableOrderingComposer
    extends Composer<_$GateDatabase, $MetaTableTable> {
  $$MetaTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MetaTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $MetaTableTable> {
  $$MetaTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$MetaTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $MetaTableTable,
          MetaRow,
          $$MetaTableTableFilterComposer,
          $$MetaTableTableOrderingComposer,
          $$MetaTableTableAnnotationComposer,
          $$MetaTableTableCreateCompanionBuilder,
          $$MetaTableTableUpdateCompanionBuilder,
          (MetaRow, BaseReferences<_$GateDatabase, $MetaTableTable, MetaRow>),
          MetaRow,
          PrefetchHooks Function()
        > {
  $$MetaTableTableTableManager(_$GateDatabase db, $MetaTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MetaTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MetaTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MetaTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetaTableCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => MetaTableCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MetaTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $MetaTableTable,
      MetaRow,
      $$MetaTableTableFilterComposer,
      $$MetaTableTableOrderingComposer,
      $$MetaTableTableAnnotationComposer,
      $$MetaTableTableCreateCompanionBuilder,
      $$MetaTableTableUpdateCompanionBuilder,
      (MetaRow, BaseReferences<_$GateDatabase, $MetaTableTable, MetaRow>),
      MetaRow,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableTableCreateCompanionBuilder =
    OutboxTableCompanion Function({
      Value<int> seq,
      required String itemId,
      required String kind,
      required String payload,
      required DateTime createdAt,
      Value<String> status,
      Value<String?> reason,
      Value<DateTime?> sentAt,
      Value<int> attempts,
    });
typedef $$OutboxTableTableUpdateCompanionBuilder =
    OutboxTableCompanion Function({
      Value<int> seq,
      Value<String> itemId,
      Value<String> kind,
      Value<String> payload,
      Value<DateTime> createdAt,
      Value<String> status,
      Value<String?> reason,
      Value<DateTime?> sentAt,
      Value<int> attempts,
    });

class $$OutboxTableTableFilterComposer
    extends Composer<_$GateDatabase, $OutboxTableTable> {
  $$OutboxTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxTableTableOrderingComposer
    extends Composer<_$GateDatabase, $OutboxTableTable> {
  $$OutboxTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $OutboxTableTable> {
  $$OutboxTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<DateTime> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);
}

class $$OutboxTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $OutboxTableTable,
          OutboxRow,
          $$OutboxTableTableFilterComposer,
          $$OutboxTableTableOrderingComposer,
          $$OutboxTableTableAnnotationComposer,
          $$OutboxTableTableCreateCompanionBuilder,
          $$OutboxTableTableUpdateCompanionBuilder,
          (
            OutboxRow,
            BaseReferences<_$GateDatabase, $OutboxTableTable, OutboxRow>,
          ),
          OutboxRow,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableTableManager(_$GateDatabase db, $OutboxTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<DateTime?> sentAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
              }) => OutboxTableCompanion(
                seq: seq,
                itemId: itemId,
                kind: kind,
                payload: payload,
                createdAt: createdAt,
                status: status,
                reason: reason,
                sentAt: sentAt,
                attempts: attempts,
              ),
          createCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                required String itemId,
                required String kind,
                required String payload,
                required DateTime createdAt,
                Value<String> status = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<DateTime?> sentAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
              }) => OutboxTableCompanion.insert(
                seq: seq,
                itemId: itemId,
                kind: kind,
                payload: payload,
                createdAt: createdAt,
                status: status,
                reason: reason,
                sentAt: sentAt,
                attempts: attempts,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $OutboxTableTable,
      OutboxRow,
      $$OutboxTableTableFilterComposer,
      $$OutboxTableTableOrderingComposer,
      $$OutboxTableTableAnnotationComposer,
      $$OutboxTableTableCreateCompanionBuilder,
      $$OutboxTableTableUpdateCompanionBuilder,
      (OutboxRow, BaseReferences<_$GateDatabase, $OutboxTableTable, OutboxRow>),
      OutboxRow,
      PrefetchHooks Function()
    >;
typedef $$SelfiesTableTableCreateCompanionBuilder =
    SelfiesTableCompanion Function({
      required String shiftId,
      required Uint8List jpeg,
      required DateTime createdAt,
      Value<int> attempts,
      Value<int> rowid,
    });
typedef $$SelfiesTableTableUpdateCompanionBuilder =
    SelfiesTableCompanion Function({
      Value<String> shiftId,
      Value<Uint8List> jpeg,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<int> rowid,
    });

class $$SelfiesTableTableFilterComposer
    extends Composer<_$GateDatabase, $SelfiesTableTable> {
  $$SelfiesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get shiftId => $composableBuilder(
    column: $table.shiftId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get jpeg => $composableBuilder(
    column: $table.jpeg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SelfiesTableTableOrderingComposer
    extends Composer<_$GateDatabase, $SelfiesTableTable> {
  $$SelfiesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get shiftId => $composableBuilder(
    column: $table.shiftId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get jpeg => $composableBuilder(
    column: $table.jpeg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SelfiesTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $SelfiesTableTable> {
  $$SelfiesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get shiftId =>
      $composableBuilder(column: $table.shiftId, builder: (column) => column);

  GeneratedColumn<Uint8List> get jpeg =>
      $composableBuilder(column: $table.jpeg, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);
}

class $$SelfiesTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $SelfiesTableTable,
          SelfieRow,
          $$SelfiesTableTableFilterComposer,
          $$SelfiesTableTableOrderingComposer,
          $$SelfiesTableTableAnnotationComposer,
          $$SelfiesTableTableCreateCompanionBuilder,
          $$SelfiesTableTableUpdateCompanionBuilder,
          (
            SelfieRow,
            BaseReferences<_$GateDatabase, $SelfiesTableTable, SelfieRow>,
          ),
          SelfieRow,
          PrefetchHooks Function()
        > {
  $$SelfiesTableTableTableManager(_$GateDatabase db, $SelfiesTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SelfiesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SelfiesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SelfiesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> shiftId = const Value.absent(),
                Value<Uint8List> jpeg = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SelfiesTableCompanion(
                shiftId: shiftId,
                jpeg: jpeg,
                createdAt: createdAt,
                attempts: attempts,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String shiftId,
                required Uint8List jpeg,
                required DateTime createdAt,
                Value<int> attempts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SelfiesTableCompanion.insert(
                shiftId: shiftId,
                jpeg: jpeg,
                createdAt: createdAt,
                attempts: attempts,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SelfiesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $SelfiesTableTable,
      SelfieRow,
      $$SelfiesTableTableFilterComposer,
      $$SelfiesTableTableOrderingComposer,
      $$SelfiesTableTableAnnotationComposer,
      $$SelfiesTableTableCreateCompanionBuilder,
      $$SelfiesTableTableUpdateCompanionBuilder,
      (
        SelfieRow,
        BaseReferences<_$GateDatabase, $SelfiesTableTable, SelfieRow>,
      ),
      SelfieRow,
      PrefetchHooks Function()
    >;
typedef $$PositionsTableTableCreateCompanionBuilder =
    PositionsTableCompanion Function({
      Value<int> seq,
      required String shiftId,
      required double lat,
      required double lng,
      Value<double?> accuracyM,
      Value<double?> heading,
      Value<double?> speed,
      required DateTime at,
    });
typedef $$PositionsTableTableUpdateCompanionBuilder =
    PositionsTableCompanion Function({
      Value<int> seq,
      Value<String> shiftId,
      Value<double> lat,
      Value<double> lng,
      Value<double?> accuracyM,
      Value<double?> heading,
      Value<double?> speed,
      Value<DateTime> at,
    });

class $$PositionsTableTableFilterComposer
    extends Composer<_$GateDatabase, $PositionsTableTable> {
  $$PositionsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shiftId => $composableBuilder(
    column: $table.shiftId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracyM => $composableBuilder(
    column: $table.accuracyM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get heading => $composableBuilder(
    column: $table.heading,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PositionsTableTableOrderingComposer
    extends Composer<_$GateDatabase, $PositionsTableTable> {
  $$PositionsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shiftId => $composableBuilder(
    column: $table.shiftId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracyM => $composableBuilder(
    column: $table.accuracyM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get heading => $composableBuilder(
    column: $table.heading,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PositionsTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $PositionsTableTable> {
  $$PositionsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get shiftId =>
      $composableBuilder(column: $table.shiftId, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<double> get accuracyM =>
      $composableBuilder(column: $table.accuracyM, builder: (column) => column);

  GeneratedColumn<double> get heading =>
      $composableBuilder(column: $table.heading, builder: (column) => column);

  GeneratedColumn<double> get speed =>
      $composableBuilder(column: $table.speed, builder: (column) => column);

  GeneratedColumn<DateTime> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);
}

class $$PositionsTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $PositionsTableTable,
          PositionRow,
          $$PositionsTableTableFilterComposer,
          $$PositionsTableTableOrderingComposer,
          $$PositionsTableTableAnnotationComposer,
          $$PositionsTableTableCreateCompanionBuilder,
          $$PositionsTableTableUpdateCompanionBuilder,
          (
            PositionRow,
            BaseReferences<_$GateDatabase, $PositionsTableTable, PositionRow>,
          ),
          PositionRow,
          PrefetchHooks Function()
        > {
  $$PositionsTableTableTableManager(
    _$GateDatabase db,
    $PositionsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PositionsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PositionsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PositionsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                Value<String> shiftId = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lng = const Value.absent(),
                Value<double?> accuracyM = const Value.absent(),
                Value<double?> heading = const Value.absent(),
                Value<double?> speed = const Value.absent(),
                Value<DateTime> at = const Value.absent(),
              }) => PositionsTableCompanion(
                seq: seq,
                shiftId: shiftId,
                lat: lat,
                lng: lng,
                accuracyM: accuracyM,
                heading: heading,
                speed: speed,
                at: at,
              ),
          createCompanionCallback:
              ({
                Value<int> seq = const Value.absent(),
                required String shiftId,
                required double lat,
                required double lng,
                Value<double?> accuracyM = const Value.absent(),
                Value<double?> heading = const Value.absent(),
                Value<double?> speed = const Value.absent(),
                required DateTime at,
              }) => PositionsTableCompanion.insert(
                seq: seq,
                shiftId: shiftId,
                lat: lat,
                lng: lng,
                accuracyM: accuracyM,
                heading: heading,
                speed: speed,
                at: at,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PositionsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $PositionsTableTable,
      PositionRow,
      $$PositionsTableTableFilterComposer,
      $$PositionsTableTableOrderingComposer,
      $$PositionsTableTableAnnotationComposer,
      $$PositionsTableTableCreateCompanionBuilder,
      $$PositionsTableTableUpdateCompanionBuilder,
      (
        PositionRow,
        BaseReferences<_$GateDatabase, $PositionsTableTable, PositionRow>,
      ),
      PositionRow,
      PrefetchHooks Function()
    >;
typedef $$MediaTableTableCreateCompanionBuilder =
    MediaTableCompanion Function({
      required String id,
      required String kind,
      required Uint8List bytes,
      required String contentType,
      Value<String?> ref,
      required DateTime createdAt,
      Value<int> attempts,
      Value<int> rowid,
    });
typedef $$MediaTableTableUpdateCompanionBuilder =
    MediaTableCompanion Function({
      Value<String> id,
      Value<String> kind,
      Value<Uint8List> bytes,
      Value<String> contentType,
      Value<String?> ref,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<int> rowid,
    });

class $$MediaTableTableFilterComposer
    extends Composer<_$GateDatabase, $MediaTableTable> {
  $$MediaTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ref => $composableBuilder(
    column: $table.ref,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MediaTableTableOrderingComposer
    extends Composer<_$GateDatabase, $MediaTableTable> {
  $$MediaTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ref => $composableBuilder(
    column: $table.ref,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaTableTableAnnotationComposer
    extends Composer<_$GateDatabase, $MediaTableTable> {
  $$MediaTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ref =>
      $composableBuilder(column: $table.ref, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);
}

class $$MediaTableTableTableManager
    extends
        RootTableManager<
          _$GateDatabase,
          $MediaTableTable,
          MediaRow,
          $$MediaTableTableFilterComposer,
          $$MediaTableTableOrderingComposer,
          $$MediaTableTableAnnotationComposer,
          $$MediaTableTableCreateCompanionBuilder,
          $$MediaTableTableUpdateCompanionBuilder,
          (
            MediaRow,
            BaseReferences<_$GateDatabase, $MediaTableTable, MediaRow>,
          ),
          MediaRow,
          PrefetchHooks Function()
        > {
  $$MediaTableTableTableManager(_$GateDatabase db, $MediaTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<Uint8List> bytes = const Value.absent(),
                Value<String> contentType = const Value.absent(),
                Value<String?> ref = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaTableCompanion(
                id: id,
                kind: kind,
                bytes: bytes,
                contentType: contentType,
                ref: ref,
                createdAt: createdAt,
                attempts: attempts,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required Uint8List bytes,
                required String contentType,
                Value<String?> ref = const Value.absent(),
                required DateTime createdAt,
                Value<int> attempts = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaTableCompanion.insert(
                id: id,
                kind: kind,
                bytes: bytes,
                contentType: contentType,
                ref: ref,
                createdAt: createdAt,
                attempts: attempts,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MediaTableTableProcessedTableManager =
    ProcessedTableManager<
      _$GateDatabase,
      $MediaTableTable,
      MediaRow,
      $$MediaTableTableFilterComposer,
      $$MediaTableTableOrderingComposer,
      $$MediaTableTableAnnotationComposer,
      $$MediaTableTableCreateCompanionBuilder,
      $$MediaTableTableUpdateCompanionBuilder,
      (MediaRow, BaseReferences<_$GateDatabase, $MediaTableTable, MediaRow>),
      MediaRow,
      PrefetchHooks Function()
    >;

class $GateDatabaseManager {
  final _$GateDatabase _db;
  $GateDatabaseManager(this._db);
  $$HomesTableTableTableManager get homesTable =>
      $$HomesTableTableTableManager(_db, _db.homesTable);
  $$ResidentsTableTableTableManager get residentsTable =>
      $$ResidentsTableTableTableManager(_db, _db.residentsTable);
  $$NumbersTableTableTableManager get numbersTable =>
      $$NumbersTableTableTableManager(_db, _db.numbersTable);
  $$VisitsTableTableTableManager get visitsTable =>
      $$VisitsTableTableTableManager(_db, _db.visitsTable);
  $$DirectoryTableTableTableManager get directoryTable =>
      $$DirectoryTableTableTableManager(_db, _db.directoryTable);
  $$GatesTableTableTableManager get gatesTable =>
      $$GatesTableTableTableManager(_db, _db.gatesTable);
  $$GuardsTableTableTableManager get guardsTable =>
      $$GuardsTableTableTableManager(_db, _db.guardsTable);
  $$VehiclesTableTableTableManager get vehiclesTable =>
      $$VehiclesTableTableTableManager(_db, _db.vehiclesTable);
  $$MetaTableTableTableManager get metaTable =>
      $$MetaTableTableTableManager(_db, _db.metaTable);
  $$OutboxTableTableTableManager get outboxTable =>
      $$OutboxTableTableTableManager(_db, _db.outboxTable);
  $$SelfiesTableTableTableManager get selfiesTable =>
      $$SelfiesTableTableTableManager(_db, _db.selfiesTable);
  $$PositionsTableTableTableManager get positionsTable =>
      $$PositionsTableTableTableManager(_db, _db.positionsTable);
  $$MediaTableTableTableManager get mediaTable =>
      $$MediaTableTableTableManager(_db, _db.mediaTable);
}
