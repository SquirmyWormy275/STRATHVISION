// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ProfilesTable extends Profiles with TableInfo<$ProfilesTable, Profile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coachNameMeta = const VerificationMeta(
    'coachName',
  );
  @override
  late final GeneratedColumn<String> coachName = GeneratedColumn<String>(
    'coach_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _packIdMeta = const VerificationMeta('packId');
  @override
  late final GeneratedColumn<String> packId = GeneratedColumn<String>(
    'pack_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metricSchemaVersionMeta =
      const VerificationMeta('metricSchemaVersion');
  @override
  late final GeneratedColumn<String> metricSchemaVersion =
      GeneratedColumn<String>(
        'metric_schema_version',
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
  static const VerificationMeta _sourceClipCountMeta = const VerificationMeta(
    'sourceClipCount',
  );
  @override
  late final GeneratedColumn<int> sourceClipCount = GeneratedColumn<int>(
    'source_clip_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metricCountMeta = const VerificationMeta(
    'metricCount',
  );
  @override
  late final GeneratedColumn<int> metricCount = GeneratedColumn<int>(
    'metric_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minClipsMetMeta = const VerificationMeta(
    'minClipsMet',
  );
  @override
  late final GeneratedColumn<bool> minClipsMet = GeneratedColumn<bool>(
    'min_clips_met',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("min_clips_met" IN (0, 1))',
    ),
  );
  static const VerificationMeta _selfConsistencyPassedMeta =
      const VerificationMeta('selfConsistencyPassed');
  @override
  late final GeneratedColumn<bool> selfConsistencyPassed =
      GeneratedColumn<bool>(
        'self_consistency_passed',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("self_consistency_passed" IN (0, 1))',
        ),
      );
  static const VerificationMeta _sourcePathMeta = const VerificationMeta(
    'sourcePath',
  );
  @override
  late final GeneratedColumn<String> sourcePath = GeneratedColumn<String>(
    'source_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  @override
  late final GeneratedColumn<DateTime> importedAt = GeneratedColumn<DateTime>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    profileId,
    version,
    coachName,
    packId,
    eventId,
    metricSchemaVersion,
    createdAt,
    sourceClipCount,
    metricCount,
    minClipsMet,
    selfConsistencyPassed,
    sourcePath,
    importedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<Profile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('coach_name')) {
      context.handle(
        _coachNameMeta,
        coachName.isAcceptableOrUnknown(data['coach_name']!, _coachNameMeta),
      );
    } else if (isInserting) {
      context.missing(_coachNameMeta);
    }
    if (data.containsKey('pack_id')) {
      context.handle(
        _packIdMeta,
        packId.isAcceptableOrUnknown(data['pack_id']!, _packIdMeta),
      );
    } else if (isInserting) {
      context.missing(_packIdMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('metric_schema_version')) {
      context.handle(
        _metricSchemaVersionMeta,
        metricSchemaVersion.isAcceptableOrUnknown(
          data['metric_schema_version']!,
          _metricSchemaVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metricSchemaVersionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('source_clip_count')) {
      context.handle(
        _sourceClipCountMeta,
        sourceClipCount.isAcceptableOrUnknown(
          data['source_clip_count']!,
          _sourceClipCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceClipCountMeta);
    }
    if (data.containsKey('metric_count')) {
      context.handle(
        _metricCountMeta,
        metricCount.isAcceptableOrUnknown(
          data['metric_count']!,
          _metricCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metricCountMeta);
    }
    if (data.containsKey('min_clips_met')) {
      context.handle(
        _minClipsMetMeta,
        minClipsMet.isAcceptableOrUnknown(
          data['min_clips_met']!,
          _minClipsMetMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_minClipsMetMeta);
    }
    if (data.containsKey('self_consistency_passed')) {
      context.handle(
        _selfConsistencyPassedMeta,
        selfConsistencyPassed.isAcceptableOrUnknown(
          data['self_consistency_passed']!,
          _selfConsistencyPassedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_selfConsistencyPassedMeta);
    }
    if (data.containsKey('source_path')) {
      context.handle(
        _sourcePathMeta,
        sourcePath.isAcceptableOrUnknown(data['source_path']!, _sourcePathMeta),
      );
    } else if (isInserting) {
      context.missing(_sourcePathMeta);
    }
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, version};
  @override
  Profile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Profile(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      coachName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coach_name'],
      )!,
      packId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      metricSchemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metric_schema_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      sourceClipCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_clip_count'],
      )!,
      metricCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}metric_count'],
      )!,
      minClipsMet: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}min_clips_met'],
      )!,
      selfConsistencyPassed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}self_consistency_passed'],
      )!,
      sourcePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_path'],
      )!,
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}imported_at'],
      )!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class Profile extends DataClass implements Insertable<Profile> {
  final String profileId;
  final int version;
  final String coachName;
  final String packId;
  final String eventId;
  final String metricSchemaVersion;
  final DateTime createdAt;
  final int sourceClipCount;
  final int metricCount;
  final bool minClipsMet;
  final bool selfConsistencyPassed;
  final String sourcePath;
  final DateTime importedAt;
  const Profile({
    required this.profileId,
    required this.version,
    required this.coachName,
    required this.packId,
    required this.eventId,
    required this.metricSchemaVersion,
    required this.createdAt,
    required this.sourceClipCount,
    required this.metricCount,
    required this.minClipsMet,
    required this.selfConsistencyPassed,
    required this.sourcePath,
    required this.importedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['version'] = Variable<int>(version);
    map['coach_name'] = Variable<String>(coachName);
    map['pack_id'] = Variable<String>(packId);
    map['event_id'] = Variable<String>(eventId);
    map['metric_schema_version'] = Variable<String>(metricSchemaVersion);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['source_clip_count'] = Variable<int>(sourceClipCount);
    map['metric_count'] = Variable<int>(metricCount);
    map['min_clips_met'] = Variable<bool>(minClipsMet);
    map['self_consistency_passed'] = Variable<bool>(selfConsistencyPassed);
    map['source_path'] = Variable<String>(sourcePath);
    map['imported_at'] = Variable<DateTime>(importedAt);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      profileId: Value(profileId),
      version: Value(version),
      coachName: Value(coachName),
      packId: Value(packId),
      eventId: Value(eventId),
      metricSchemaVersion: Value(metricSchemaVersion),
      createdAt: Value(createdAt),
      sourceClipCount: Value(sourceClipCount),
      metricCount: Value(metricCount),
      minClipsMet: Value(minClipsMet),
      selfConsistencyPassed: Value(selfConsistencyPassed),
      sourcePath: Value(sourcePath),
      importedAt: Value(importedAt),
    );
  }

  factory Profile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Profile(
      profileId: serializer.fromJson<String>(json['profileId']),
      version: serializer.fromJson<int>(json['version']),
      coachName: serializer.fromJson<String>(json['coachName']),
      packId: serializer.fromJson<String>(json['packId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      metricSchemaVersion: serializer.fromJson<String>(
        json['metricSchemaVersion'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sourceClipCount: serializer.fromJson<int>(json['sourceClipCount']),
      metricCount: serializer.fromJson<int>(json['metricCount']),
      minClipsMet: serializer.fromJson<bool>(json['minClipsMet']),
      selfConsistencyPassed: serializer.fromJson<bool>(
        json['selfConsistencyPassed'],
      ),
      sourcePath: serializer.fromJson<String>(json['sourcePath']),
      importedAt: serializer.fromJson<DateTime>(json['importedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'version': serializer.toJson<int>(version),
      'coachName': serializer.toJson<String>(coachName),
      'packId': serializer.toJson<String>(packId),
      'eventId': serializer.toJson<String>(eventId),
      'metricSchemaVersion': serializer.toJson<String>(metricSchemaVersion),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sourceClipCount': serializer.toJson<int>(sourceClipCount),
      'metricCount': serializer.toJson<int>(metricCount),
      'minClipsMet': serializer.toJson<bool>(minClipsMet),
      'selfConsistencyPassed': serializer.toJson<bool>(selfConsistencyPassed),
      'sourcePath': serializer.toJson<String>(sourcePath),
      'importedAt': serializer.toJson<DateTime>(importedAt),
    };
  }

  Profile copyWith({
    String? profileId,
    int? version,
    String? coachName,
    String? packId,
    String? eventId,
    String? metricSchemaVersion,
    DateTime? createdAt,
    int? sourceClipCount,
    int? metricCount,
    bool? minClipsMet,
    bool? selfConsistencyPassed,
    String? sourcePath,
    DateTime? importedAt,
  }) => Profile(
    profileId: profileId ?? this.profileId,
    version: version ?? this.version,
    coachName: coachName ?? this.coachName,
    packId: packId ?? this.packId,
    eventId: eventId ?? this.eventId,
    metricSchemaVersion: metricSchemaVersion ?? this.metricSchemaVersion,
    createdAt: createdAt ?? this.createdAt,
    sourceClipCount: sourceClipCount ?? this.sourceClipCount,
    metricCount: metricCount ?? this.metricCount,
    minClipsMet: minClipsMet ?? this.minClipsMet,
    selfConsistencyPassed: selfConsistencyPassed ?? this.selfConsistencyPassed,
    sourcePath: sourcePath ?? this.sourcePath,
    importedAt: importedAt ?? this.importedAt,
  );
  Profile copyWithCompanion(ProfilesCompanion data) {
    return Profile(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      version: data.version.present ? data.version.value : this.version,
      coachName: data.coachName.present ? data.coachName.value : this.coachName,
      packId: data.packId.present ? data.packId.value : this.packId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      metricSchemaVersion: data.metricSchemaVersion.present
          ? data.metricSchemaVersion.value
          : this.metricSchemaVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sourceClipCount: data.sourceClipCount.present
          ? data.sourceClipCount.value
          : this.sourceClipCount,
      metricCount: data.metricCount.present
          ? data.metricCount.value
          : this.metricCount,
      minClipsMet: data.minClipsMet.present
          ? data.minClipsMet.value
          : this.minClipsMet,
      selfConsistencyPassed: data.selfConsistencyPassed.present
          ? data.selfConsistencyPassed.value
          : this.selfConsistencyPassed,
      sourcePath: data.sourcePath.present
          ? data.sourcePath.value
          : this.sourcePath,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Profile(')
          ..write('profileId: $profileId, ')
          ..write('version: $version, ')
          ..write('coachName: $coachName, ')
          ..write('packId: $packId, ')
          ..write('eventId: $eventId, ')
          ..write('metricSchemaVersion: $metricSchemaVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('sourceClipCount: $sourceClipCount, ')
          ..write('metricCount: $metricCount, ')
          ..write('minClipsMet: $minClipsMet, ')
          ..write('selfConsistencyPassed: $selfConsistencyPassed, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('importedAt: $importedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    profileId,
    version,
    coachName,
    packId,
    eventId,
    metricSchemaVersion,
    createdAt,
    sourceClipCount,
    metricCount,
    minClipsMet,
    selfConsistencyPassed,
    sourcePath,
    importedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Profile &&
          other.profileId == this.profileId &&
          other.version == this.version &&
          other.coachName == this.coachName &&
          other.packId == this.packId &&
          other.eventId == this.eventId &&
          other.metricSchemaVersion == this.metricSchemaVersion &&
          other.createdAt == this.createdAt &&
          other.sourceClipCount == this.sourceClipCount &&
          other.metricCount == this.metricCount &&
          other.minClipsMet == this.minClipsMet &&
          other.selfConsistencyPassed == this.selfConsistencyPassed &&
          other.sourcePath == this.sourcePath &&
          other.importedAt == this.importedAt);
}

class ProfilesCompanion extends UpdateCompanion<Profile> {
  final Value<String> profileId;
  final Value<int> version;
  final Value<String> coachName;
  final Value<String> packId;
  final Value<String> eventId;
  final Value<String> metricSchemaVersion;
  final Value<DateTime> createdAt;
  final Value<int> sourceClipCount;
  final Value<int> metricCount;
  final Value<bool> minClipsMet;
  final Value<bool> selfConsistencyPassed;
  final Value<String> sourcePath;
  final Value<DateTime> importedAt;
  final Value<int> rowid;
  const ProfilesCompanion({
    this.profileId = const Value.absent(),
    this.version = const Value.absent(),
    this.coachName = const Value.absent(),
    this.packId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.metricSchemaVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sourceClipCount = const Value.absent(),
    this.metricCount = const Value.absent(),
    this.minClipsMet = const Value.absent(),
    this.selfConsistencyPassed = const Value.absent(),
    this.sourcePath = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesCompanion.insert({
    required String profileId,
    required int version,
    required String coachName,
    required String packId,
    required String eventId,
    required String metricSchemaVersion,
    required DateTime createdAt,
    required int sourceClipCount,
    required int metricCount,
    required bool minClipsMet,
    required bool selfConsistencyPassed,
    required String sourcePath,
    required DateTime importedAt,
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       version = Value(version),
       coachName = Value(coachName),
       packId = Value(packId),
       eventId = Value(eventId),
       metricSchemaVersion = Value(metricSchemaVersion),
       createdAt = Value(createdAt),
       sourceClipCount = Value(sourceClipCount),
       metricCount = Value(metricCount),
       minClipsMet = Value(minClipsMet),
       selfConsistencyPassed = Value(selfConsistencyPassed),
       sourcePath = Value(sourcePath),
       importedAt = Value(importedAt);
  static Insertable<Profile> custom({
    Expression<String>? profileId,
    Expression<int>? version,
    Expression<String>? coachName,
    Expression<String>? packId,
    Expression<String>? eventId,
    Expression<String>? metricSchemaVersion,
    Expression<DateTime>? createdAt,
    Expression<int>? sourceClipCount,
    Expression<int>? metricCount,
    Expression<bool>? minClipsMet,
    Expression<bool>? selfConsistencyPassed,
    Expression<String>? sourcePath,
    Expression<DateTime>? importedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (version != null) 'version': version,
      if (coachName != null) 'coach_name': coachName,
      if (packId != null) 'pack_id': packId,
      if (eventId != null) 'event_id': eventId,
      if (metricSchemaVersion != null)
        'metric_schema_version': metricSchemaVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (sourceClipCount != null) 'source_clip_count': sourceClipCount,
      if (metricCount != null) 'metric_count': metricCount,
      if (minClipsMet != null) 'min_clips_met': minClipsMet,
      if (selfConsistencyPassed != null)
        'self_consistency_passed': selfConsistencyPassed,
      if (sourcePath != null) 'source_path': sourcePath,
      if (importedAt != null) 'imported_at': importedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesCompanion copyWith({
    Value<String>? profileId,
    Value<int>? version,
    Value<String>? coachName,
    Value<String>? packId,
    Value<String>? eventId,
    Value<String>? metricSchemaVersion,
    Value<DateTime>? createdAt,
    Value<int>? sourceClipCount,
    Value<int>? metricCount,
    Value<bool>? minClipsMet,
    Value<bool>? selfConsistencyPassed,
    Value<String>? sourcePath,
    Value<DateTime>? importedAt,
    Value<int>? rowid,
  }) {
    return ProfilesCompanion(
      profileId: profileId ?? this.profileId,
      version: version ?? this.version,
      coachName: coachName ?? this.coachName,
      packId: packId ?? this.packId,
      eventId: eventId ?? this.eventId,
      metricSchemaVersion: metricSchemaVersion ?? this.metricSchemaVersion,
      createdAt: createdAt ?? this.createdAt,
      sourceClipCount: sourceClipCount ?? this.sourceClipCount,
      metricCount: metricCount ?? this.metricCount,
      minClipsMet: minClipsMet ?? this.minClipsMet,
      selfConsistencyPassed:
          selfConsistencyPassed ?? this.selfConsistencyPassed,
      sourcePath: sourcePath ?? this.sourcePath,
      importedAt: importedAt ?? this.importedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (coachName.present) {
      map['coach_name'] = Variable<String>(coachName.value);
    }
    if (packId.present) {
      map['pack_id'] = Variable<String>(packId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (metricSchemaVersion.present) {
      map['metric_schema_version'] = Variable<String>(
        metricSchemaVersion.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sourceClipCount.present) {
      map['source_clip_count'] = Variable<int>(sourceClipCount.value);
    }
    if (metricCount.present) {
      map['metric_count'] = Variable<int>(metricCount.value);
    }
    if (minClipsMet.present) {
      map['min_clips_met'] = Variable<bool>(minClipsMet.value);
    }
    if (selfConsistencyPassed.present) {
      map['self_consistency_passed'] = Variable<bool>(
        selfConsistencyPassed.value,
      );
    }
    if (sourcePath.present) {
      map['source_path'] = Variable<String>(sourcePath.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<DateTime>(importedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfilesCompanion(')
          ..write('profileId: $profileId, ')
          ..write('version: $version, ')
          ..write('coachName: $coachName, ')
          ..write('packId: $packId, ')
          ..write('eventId: $eventId, ')
          ..write('metricSchemaVersion: $metricSchemaVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('sourceClipCount: $sourceClipCount, ')
          ..write('metricCount: $metricCount, ')
          ..write('minClipsMet: $minClipsMet, ')
          ..write('selfConsistencyPassed: $selfConsistencyPassed, ')
          ..write('sourcePath: $sourcePath, ')
          ..write('importedAt: $importedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [profiles];
}

typedef $$ProfilesTableCreateCompanionBuilder = ProfilesCompanion Function({
  required String profileId,
  required int version,
  required String coachName,
  required String packId,
  required String eventId,
  required String metricSchemaVersion,
  required DateTime createdAt,
  required int sourceClipCount,
  required int metricCount,
  required bool minClipsMet,
  required bool selfConsistencyPassed,
  required String sourcePath,
  required DateTime importedAt,
  Value<int> rowid,
});
typedef $$ProfilesTableUpdateCompanionBuilder = ProfilesCompanion Function({
  Value<String> profileId,
  Value<int> version,
  Value<String> coachName,
  Value<String> packId,
  Value<String> eventId,
  Value<String> metricSchemaVersion,
  Value<DateTime> createdAt,
  Value<int> sourceClipCount,
  Value<int> metricCount,
  Value<bool> minClipsMet,
  Value<bool> selfConsistencyPassed,
  Value<String> sourcePath,
  Value<DateTime> importedAt,
  Value<int> rowid,
});

class $$ProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coachName => $composableBuilder(
    column: $table.coachName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packId => $composableBuilder(
    column: $table.packId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metricSchemaVersion => $composableBuilder(
    column: $table.metricSchemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceClipCount => $composableBuilder(
    column: $table.sourceClipCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get metricCount => $composableBuilder(
    column: $table.metricCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get minClipsMet => $composableBuilder(
    column: $table.minClipsMet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get selfConsistencyPassed => $composableBuilder(
    column: $table.selfConsistencyPassed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coachName => $composableBuilder(
    column: $table.coachName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packId => $composableBuilder(
    column: $table.packId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metricSchemaVersion => $composableBuilder(
    column: $table.metricSchemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceClipCount => $composableBuilder(
    column: $table.sourceClipCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get metricCount => $composableBuilder(
    column: $table.metricCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get minClipsMet => $composableBuilder(
    column: $table.minClipsMet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get selfConsistencyPassed => $composableBuilder(
    column: $table.selfConsistencyPassed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get coachName =>
      $composableBuilder(column: $table.coachName, builder: (column) => column);

  GeneratedColumn<String> get packId =>
      $composableBuilder(column: $table.packId, builder: (column) => column);

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get metricSchemaVersion => $composableBuilder(
    column: $table.metricSchemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get sourceClipCount => $composableBuilder(
    column: $table.sourceClipCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get metricCount => $composableBuilder(
    column: $table.metricCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get minClipsMet => $composableBuilder(
    column: $table.minClipsMet,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get selfConsistencyPassed => $composableBuilder(
    column: $table.selfConsistencyPassed,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourcePath => $composableBuilder(
    column: $table.sourcePath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );
}

class $$ProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProfilesTable,
          Profile,
          $$ProfilesTableFilterComposer,
          $$ProfilesTableOrderingComposer,
          $$ProfilesTableAnnotationComposer,
          $$ProfilesTableCreateCompanionBuilder,
          $$ProfilesTableUpdateCompanionBuilder,
          (Profile, BaseReferences<_$AppDatabase, $ProfilesTable, Profile>),
          Profile,
          PrefetchHooks Function()
        > {
  $$ProfilesTableTableManager(_$AppDatabase db, $ProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> coachName = const Value.absent(),
                Value<String> packId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String> metricSchemaVersion = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> sourceClipCount = const Value.absent(),
                Value<int> metricCount = const Value.absent(),
                Value<bool> minClipsMet = const Value.absent(),
                Value<bool> selfConsistencyPassed = const Value.absent(),
                Value<String> sourcePath = const Value.absent(),
                Value<DateTime> importedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion(
                profileId: profileId,
                version: version,
                coachName: coachName,
                packId: packId,
                eventId: eventId,
                metricSchemaVersion: metricSchemaVersion,
                createdAt: createdAt,
                sourceClipCount: sourceClipCount,
                metricCount: metricCount,
                minClipsMet: minClipsMet,
                selfConsistencyPassed: selfConsistencyPassed,
                sourcePath: sourcePath,
                importedAt: importedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required int version,
                required String coachName,
                required String packId,
                required String eventId,
                required String metricSchemaVersion,
                required DateTime createdAt,
                required int sourceClipCount,
                required int metricCount,
                required bool minClipsMet,
                required bool selfConsistencyPassed,
                required String sourcePath,
                required DateTime importedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion.insert(
                profileId: profileId,
                version: version,
                coachName: coachName,
                packId: packId,
                eventId: eventId,
                metricSchemaVersion: metricSchemaVersion,
                createdAt: createdAt,
                sourceClipCount: sourceClipCount,
                metricCount: metricCount,
                minClipsMet: minClipsMet,
                selfConsistencyPassed: selfConsistencyPassed,
                sourcePath: sourcePath,
                importedAt: importedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProfilesTable, Profile>(table),
                  BaseReferences<_$AppDatabase, $ProfilesTable, Profile>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProfilesTable,
      Profile,
      $$ProfilesTableFilterComposer,
      $$ProfilesTableOrderingComposer,
      $$ProfilesTableAnnotationComposer,
      $$ProfilesTableCreateCompanionBuilder,
      $$ProfilesTableUpdateCompanionBuilder,
      (Profile, BaseReferences<_$AppDatabase, $ProfilesTable, Profile>),
      Profile,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
}
