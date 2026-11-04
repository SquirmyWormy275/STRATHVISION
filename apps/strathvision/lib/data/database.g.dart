// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ProfilesTable extends Profiles
    with TableInfo<$ProfilesTable, ProfileRow> {
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
    Insertable<ProfileRow> instance, {
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
  ProfileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileRow(
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

class ProfileRow extends DataClass implements Insertable<ProfileRow> {
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
  const ProfileRow({
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

  factory ProfileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileRow(
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

  ProfileRow copyWith({
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
  }) => ProfileRow(
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
  ProfileRow copyWithCompanion(ProfilesCompanion data) {
    return ProfileRow(
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
    return (StringBuffer('ProfileRow(')
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
      (other is ProfileRow &&
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

class ProfilesCompanion extends UpdateCompanion<ProfileRow> {
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
  static Insertable<ProfileRow> custom({
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

class $ProjectRowsTable extends ProjectRows
    with TableInfo<$ProjectRowsTable, ProjectRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
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
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [projectId, name, json, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {projectId};
  @override
  ProjectRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectRow(
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProjectRowsTable createAlias(String alias) {
    return $ProjectRowsTable(attachedDatabase, alias);
  }
}

class ProjectRow extends DataClass implements Insertable<ProjectRow> {
  final String projectId;
  final String name;
  final String json;
  final DateTime updatedAt;
  const ProjectRow({
    required this.projectId,
    required this.name,
    required this.json,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['project_id'] = Variable<String>(projectId);
    map['name'] = Variable<String>(name);
    map['json'] = Variable<String>(json);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProjectRowsCompanion toCompanion(bool nullToAbsent) {
    return ProjectRowsCompanion(
      projectId: Value(projectId),
      name: Value(name),
      json: Value(json),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProjectRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectRow(
      projectId: serializer.fromJson<String>(json['projectId']),
      name: serializer.fromJson<String>(json['name']),
      json: serializer.fromJson<String>(json['json']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'projectId': serializer.toJson<String>(projectId),
      'name': serializer.toJson<String>(name),
      'json': serializer.toJson<String>(json),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProjectRow copyWith({
    String? projectId,
    String? name,
    String? json,
    DateTime? updatedAt,
  }) => ProjectRow(
    projectId: projectId ?? this.projectId,
    name: name ?? this.name,
    json: json ?? this.json,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProjectRow copyWithCompanion(ProjectRowsCompanion data) {
    return ProjectRow(
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      name: data.name.present ? data.name.value : this.name,
      json: data.json.present ? data.json.value : this.json,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectRow(')
          ..write('projectId: $projectId, ')
          ..write('name: $name, ')
          ..write('json: $json, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(projectId, name, json, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectRow &&
          other.projectId == this.projectId &&
          other.name == this.name &&
          other.json == this.json &&
          other.updatedAt == this.updatedAt);
}

class ProjectRowsCompanion extends UpdateCompanion<ProjectRow> {
  final Value<String> projectId;
  final Value<String> name;
  final Value<String> json;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProjectRowsCompanion({
    this.projectId = const Value.absent(),
    this.name = const Value.absent(),
    this.json = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectRowsCompanion.insert({
    required String projectId,
    required String name,
    required String json,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : projectId = Value(projectId),
       name = Value(name),
       json = Value(json),
       updatedAt = Value(updatedAt);
  static Insertable<ProjectRow> custom({
    Expression<String>? projectId,
    Expression<String>? name,
    Expression<String>? json,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (projectId != null) 'project_id': projectId,
      if (name != null) 'name': name,
      if (json != null) 'json': json,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectRowsCompanion copyWith({
    Value<String>? projectId,
    Value<String>? name,
    Value<String>? json,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProjectRowsCompanion(
      projectId: projectId ?? this.projectId,
      name: name ?? this.name,
      json: json ?? this.json,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectRowsCompanion(')
          ..write('projectId: $projectId, ')
          ..write('name: $name, ')
          ..write('json: $json, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ComparisonRowsTable extends ComparisonRows
    with TableInfo<$ComparisonRowsTable, ComparisonRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ComparisonRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _resultIdMeta = const VerificationMeta(
    'resultId',
  );
  @override
  late final GeneratedColumn<String> resultId = GeneratedColumn<String>(
    'result_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clipIdMeta = const VerificationMeta('clipId');
  @override
  late final GeneratedColumn<String> clipId = GeneratedColumn<String>(
    'clip_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  static const VerificationMeta _profileVersionMeta = const VerificationMeta(
    'profileVersion',
  );
  @override
  late final GeneratedColumn<int> profileVersion = GeneratedColumn<int>(
    'profile_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _overallScoreMeta = const VerificationMeta(
    'overallScore',
  );
  @override
  late final GeneratedColumn<double> overallScore = GeneratedColumn<double>(
    'overall_score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
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
  @override
  List<GeneratedColumn> get $columns => [
    resultId,
    projectId,
    clipId,
    profileId,
    profileVersion,
    overallScore,
    json,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'comparison_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ComparisonRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('result_id')) {
      context.handle(
        _resultIdMeta,
        resultId.isAcceptableOrUnknown(data['result_id']!, _resultIdMeta),
      );
    } else if (isInserting) {
      context.missing(_resultIdMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('clip_id')) {
      context.handle(
        _clipIdMeta,
        clipId.isAcceptableOrUnknown(data['clip_id']!, _clipIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clipIdMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('profile_version')) {
      context.handle(
        _profileVersionMeta,
        profileVersion.isAcceptableOrUnknown(
          data['profile_version']!,
          _profileVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_profileVersionMeta);
    }
    if (data.containsKey('overall_score')) {
      context.handle(
        _overallScoreMeta,
        overallScore.isAcceptableOrUnknown(
          data['overall_score']!,
          _overallScoreMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_overallScoreMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {resultId};
  @override
  ComparisonRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ComparisonRow(
      resultId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      clipId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clip_id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      profileVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}profile_version'],
      )!,
      overallScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}overall_score'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ComparisonRowsTable createAlias(String alias) {
    return $ComparisonRowsTable(attachedDatabase, alias);
  }
}

class ComparisonRow extends DataClass implements Insertable<ComparisonRow> {
  final String resultId;
  final String projectId;
  final String clipId;
  final String profileId;
  final int profileVersion;
  final double overallScore;
  final String json;
  final DateTime createdAt;
  const ComparisonRow({
    required this.resultId,
    required this.projectId,
    required this.clipId,
    required this.profileId,
    required this.profileVersion,
    required this.overallScore,
    required this.json,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['result_id'] = Variable<String>(resultId);
    map['project_id'] = Variable<String>(projectId);
    map['clip_id'] = Variable<String>(clipId);
    map['profile_id'] = Variable<String>(profileId);
    map['profile_version'] = Variable<int>(profileVersion);
    map['overall_score'] = Variable<double>(overallScore);
    map['json'] = Variable<String>(json);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ComparisonRowsCompanion toCompanion(bool nullToAbsent) {
    return ComparisonRowsCompanion(
      resultId: Value(resultId),
      projectId: Value(projectId),
      clipId: Value(clipId),
      profileId: Value(profileId),
      profileVersion: Value(profileVersion),
      overallScore: Value(overallScore),
      json: Value(json),
      createdAt: Value(createdAt),
    );
  }

  factory ComparisonRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ComparisonRow(
      resultId: serializer.fromJson<String>(json['resultId']),
      projectId: serializer.fromJson<String>(json['projectId']),
      clipId: serializer.fromJson<String>(json['clipId']),
      profileId: serializer.fromJson<String>(json['profileId']),
      profileVersion: serializer.fromJson<int>(json['profileVersion']),
      overallScore: serializer.fromJson<double>(json['overallScore']),
      json: serializer.fromJson<String>(json['json']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'resultId': serializer.toJson<String>(resultId),
      'projectId': serializer.toJson<String>(projectId),
      'clipId': serializer.toJson<String>(clipId),
      'profileId': serializer.toJson<String>(profileId),
      'profileVersion': serializer.toJson<int>(profileVersion),
      'overallScore': serializer.toJson<double>(overallScore),
      'json': serializer.toJson<String>(json),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ComparisonRow copyWith({
    String? resultId,
    String? projectId,
    String? clipId,
    String? profileId,
    int? profileVersion,
    double? overallScore,
    String? json,
    DateTime? createdAt,
  }) => ComparisonRow(
    resultId: resultId ?? this.resultId,
    projectId: projectId ?? this.projectId,
    clipId: clipId ?? this.clipId,
    profileId: profileId ?? this.profileId,
    profileVersion: profileVersion ?? this.profileVersion,
    overallScore: overallScore ?? this.overallScore,
    json: json ?? this.json,
    createdAt: createdAt ?? this.createdAt,
  );
  ComparisonRow copyWithCompanion(ComparisonRowsCompanion data) {
    return ComparisonRow(
      resultId: data.resultId.present ? data.resultId.value : this.resultId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      clipId: data.clipId.present ? data.clipId.value : this.clipId,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      profileVersion: data.profileVersion.present
          ? data.profileVersion.value
          : this.profileVersion,
      overallScore: data.overallScore.present
          ? data.overallScore.value
          : this.overallScore,
      json: data.json.present ? data.json.value : this.json,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ComparisonRow(')
          ..write('resultId: $resultId, ')
          ..write('projectId: $projectId, ')
          ..write('clipId: $clipId, ')
          ..write('profileId: $profileId, ')
          ..write('profileVersion: $profileVersion, ')
          ..write('overallScore: $overallScore, ')
          ..write('json: $json, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    resultId,
    projectId,
    clipId,
    profileId,
    profileVersion,
    overallScore,
    json,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComparisonRow &&
          other.resultId == this.resultId &&
          other.projectId == this.projectId &&
          other.clipId == this.clipId &&
          other.profileId == this.profileId &&
          other.profileVersion == this.profileVersion &&
          other.overallScore == this.overallScore &&
          other.json == this.json &&
          other.createdAt == this.createdAt);
}

class ComparisonRowsCompanion extends UpdateCompanion<ComparisonRow> {
  final Value<String> resultId;
  final Value<String> projectId;
  final Value<String> clipId;
  final Value<String> profileId;
  final Value<int> profileVersion;
  final Value<double> overallScore;
  final Value<String> json;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ComparisonRowsCompanion({
    this.resultId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.clipId = const Value.absent(),
    this.profileId = const Value.absent(),
    this.profileVersion = const Value.absent(),
    this.overallScore = const Value.absent(),
    this.json = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ComparisonRowsCompanion.insert({
    required String resultId,
    required String projectId,
    required String clipId,
    required String profileId,
    required int profileVersion,
    required double overallScore,
    required String json,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : resultId = Value(resultId),
       projectId = Value(projectId),
       clipId = Value(clipId),
       profileId = Value(profileId),
       profileVersion = Value(profileVersion),
       overallScore = Value(overallScore),
       json = Value(json),
       createdAt = Value(createdAt);
  static Insertable<ComparisonRow> custom({
    Expression<String>? resultId,
    Expression<String>? projectId,
    Expression<String>? clipId,
    Expression<String>? profileId,
    Expression<int>? profileVersion,
    Expression<double>? overallScore,
    Expression<String>? json,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (resultId != null) 'result_id': resultId,
      if (projectId != null) 'project_id': projectId,
      if (clipId != null) 'clip_id': clipId,
      if (profileId != null) 'profile_id': profileId,
      if (profileVersion != null) 'profile_version': profileVersion,
      if (overallScore != null) 'overall_score': overallScore,
      if (json != null) 'json': json,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ComparisonRowsCompanion copyWith({
    Value<String>? resultId,
    Value<String>? projectId,
    Value<String>? clipId,
    Value<String>? profileId,
    Value<int>? profileVersion,
    Value<double>? overallScore,
    Value<String>? json,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ComparisonRowsCompanion(
      resultId: resultId ?? this.resultId,
      projectId: projectId ?? this.projectId,
      clipId: clipId ?? this.clipId,
      profileId: profileId ?? this.profileId,
      profileVersion: profileVersion ?? this.profileVersion,
      overallScore: overallScore ?? this.overallScore,
      json: json ?? this.json,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (resultId.present) {
      map['result_id'] = Variable<String>(resultId.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (clipId.present) {
      map['clip_id'] = Variable<String>(clipId.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (profileVersion.present) {
      map['profile_version'] = Variable<int>(profileVersion.value);
    }
    if (overallScore.present) {
      map['overall_score'] = Variable<double>(overallScore.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ComparisonRowsCompanion(')
          ..write('resultId: $resultId, ')
          ..write('projectId: $projectId, ')
          ..write('clipId: $clipId, ')
          ..write('profileId: $profileId, ')
          ..write('profileVersion: $profileVersion, ')
          ..write('overallScore: $overallScore, ')
          ..write('json: $json, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
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
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
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
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
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

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
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
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
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

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
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
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $ProjectRowsTable projectRows = $ProjectRowsTable(this);
  late final $ComparisonRowsTable comparisonRows = $ComparisonRowsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    profiles,
    projectRows,
    comparisonRows,
    settings,
  ];
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
          ProfileRow,
          $$ProfilesTableFilterComposer,
          $$ProfilesTableOrderingComposer,
          $$ProfilesTableAnnotationComposer,
          $$ProfilesTableCreateCompanionBuilder,
          $$ProfilesTableUpdateCompanionBuilder,
          (
            ProfileRow,
            BaseReferences<_$AppDatabase, $ProfilesTable, ProfileRow>,
          ),
          ProfileRow,
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
                  e.readTable<$ProfilesTable, ProfileRow>(table),
                  BaseReferences<_$AppDatabase, $ProfilesTable, ProfileRow>(
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
      ProfileRow,
      $$ProfilesTableFilterComposer,
      $$ProfilesTableOrderingComposer,
      $$ProfilesTableAnnotationComposer,
      $$ProfilesTableCreateCompanionBuilder,
      $$ProfilesTableUpdateCompanionBuilder,
      (ProfileRow, BaseReferences<_$AppDatabase, $ProfilesTable, ProfileRow>),
      ProfileRow,
      PrefetchHooks Function()
    >;
typedef $$ProjectRowsTableCreateCompanionBuilder =
    ProjectRowsCompanion Function({
      required String projectId,
      required String name,
      required String json,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ProjectRowsTableUpdateCompanionBuilder =
    ProjectRowsCompanion Function({
      Value<String> projectId,
      Value<String> name,
      Value<String> json,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ProjectRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectRowsTable> {
  $$ProjectRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProjectRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectRowsTable> {
  $$ProjectRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectRowsTable> {
  $$ProjectRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProjectRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectRowsTable,
          ProjectRow,
          $$ProjectRowsTableFilterComposer,
          $$ProjectRowsTableOrderingComposer,
          $$ProjectRowsTableAnnotationComposer,
          $$ProjectRowsTableCreateCompanionBuilder,
          $$ProjectRowsTableUpdateCompanionBuilder,
          (
            ProjectRow,
            BaseReferences<_$AppDatabase, $ProjectRowsTable, ProjectRow>,
          ),
          ProjectRow,
          PrefetchHooks Function()
        > {
  $$ProjectRowsTableTableManager(_$AppDatabase db, $ProjectRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> projectId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectRowsCompanion(
                projectId: projectId,
                name: name,
                json: json,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String projectId,
                required String name,
                required String json,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProjectRowsCompanion.insert(
                projectId: projectId,
                name: name,
                json: json,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProjectRowsTable, ProjectRow>(table),
                  BaseReferences<_$AppDatabase, $ProjectRowsTable, ProjectRow>(
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

typedef $$ProjectRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectRowsTable,
      ProjectRow,
      $$ProjectRowsTableFilterComposer,
      $$ProjectRowsTableOrderingComposer,
      $$ProjectRowsTableAnnotationComposer,
      $$ProjectRowsTableCreateCompanionBuilder,
      $$ProjectRowsTableUpdateCompanionBuilder,
      (
        ProjectRow,
        BaseReferences<_$AppDatabase, $ProjectRowsTable, ProjectRow>,
      ),
      ProjectRow,
      PrefetchHooks Function()
    >;
typedef $$ComparisonRowsTableCreateCompanionBuilder =
    ComparisonRowsCompanion Function({
      required String resultId,
      required String projectId,
      required String clipId,
      required String profileId,
      required int profileVersion,
      required double overallScore,
      required String json,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ComparisonRowsTableUpdateCompanionBuilder =
    ComparisonRowsCompanion Function({
      Value<String> resultId,
      Value<String> projectId,
      Value<String> clipId,
      Value<String> profileId,
      Value<int> profileVersion,
      Value<double> overallScore,
      Value<String> json,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$ComparisonRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ComparisonRowsTable> {
  $$ComparisonRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get resultId => $composableBuilder(
    column: $table.resultId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clipId => $composableBuilder(
    column: $table.clipId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get profileVersion => $composableBuilder(
    column: $table.profileVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get overallScore => $composableBuilder(
    column: $table.overallScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ComparisonRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ComparisonRowsTable> {
  $$ComparisonRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get resultId => $composableBuilder(
    column: $table.resultId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clipId => $composableBuilder(
    column: $table.clipId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get profileVersion => $composableBuilder(
    column: $table.profileVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get overallScore => $composableBuilder(
    column: $table.overallScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ComparisonRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ComparisonRowsTable> {
  $$ComparisonRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get resultId =>
      $composableBuilder(column: $table.resultId, builder: (column) => column);

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get clipId =>
      $composableBuilder(column: $table.clipId, builder: (column) => column);

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<int> get profileVersion => $composableBuilder(
    column: $table.profileVersion,
    builder: (column) => column,
  );

  GeneratedColumn<double> get overallScore => $composableBuilder(
    column: $table.overallScore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ComparisonRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ComparisonRowsTable,
          ComparisonRow,
          $$ComparisonRowsTableFilterComposer,
          $$ComparisonRowsTableOrderingComposer,
          $$ComparisonRowsTableAnnotationComposer,
          $$ComparisonRowsTableCreateCompanionBuilder,
          $$ComparisonRowsTableUpdateCompanionBuilder,
          (
            ComparisonRow,
            BaseReferences<_$AppDatabase, $ComparisonRowsTable, ComparisonRow>,
          ),
          ComparisonRow,
          PrefetchHooks Function()
        > {
  $$ComparisonRowsTableTableManager(
    _$AppDatabase db,
    $ComparisonRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ComparisonRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ComparisonRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ComparisonRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> resultId = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<String> clipId = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<int> profileVersion = const Value.absent(),
                Value<double> overallScore = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ComparisonRowsCompanion(
                resultId: resultId,
                projectId: projectId,
                clipId: clipId,
                profileId: profileId,
                profileVersion: profileVersion,
                overallScore: overallScore,
                json: json,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String resultId,
                required String projectId,
                required String clipId,
                required String profileId,
                required int profileVersion,
                required double overallScore,
                required String json,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ComparisonRowsCompanion.insert(
                resultId: resultId,
                projectId: projectId,
                clipId: clipId,
                profileId: profileId,
                profileVersion: profileVersion,
                overallScore: overallScore,
                json: json,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ComparisonRowsTable, ComparisonRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ComparisonRowsTable,
                    ComparisonRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ComparisonRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ComparisonRowsTable,
      ComparisonRow,
      $$ComparisonRowsTableFilterComposer,
      $$ComparisonRowsTableOrderingComposer,
      $$ComparisonRowsTableAnnotationComposer,
      $$ComparisonRowsTableCreateCompanionBuilder,
      $$ComparisonRowsTableUpdateCompanionBuilder,
      (
        ComparisonRow,
        BaseReferences<_$AppDatabase, $ComparisonRowsTable, ComparisonRow>,
      ),
      ComparisonRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
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

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
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

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
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

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, SettingRow>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>(
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

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$ProjectRowsTableTableManager get projectRows =>
      $$ProjectRowsTableTableManager(_db, _db.projectRows);
  $$ComparisonRowsTableTableManager get comparisonRows =>
      $$ComparisonRowsTableTableManager(_db, _db.comparisonRows);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
