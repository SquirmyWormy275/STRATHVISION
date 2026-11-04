import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../profiles/profile_package.dart';

part 'database.g.dart';

/// Installed profile metadata. Phase 1 stores metadata only.
class Profiles extends Table {
  TextColumn get profileId => text()();
  IntColumn get version => integer()();
  TextColumn get coachName => text()();
  TextColumn get packId => text()();
  TextColumn get eventId => text()();
  TextColumn get metricSchemaVersion => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get sourceClipCount => integer()();
  IntColumn get metricCount => integer()();
  BoolColumn get minClipsMet => boolean()();
  BoolColumn get selfConsistencyPassed => boolean()();
  TextColumn get sourcePath => text()();
  DateTimeColumn get importedAt => dateTime()();

  // Profile versions are non-mutating: each (id, version) is its own row.
  @override
  Set<Column> get primaryKey => {profileId, version};
}

@DriftDatabase(tables: [Profiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ??
            driftDatabase(
              name: 'strathvision',
              native: const DriftNativeOptions(
                databaseDirectory: getApplicationSupportDirectory,
              ),
            ));

  @override
  int get schemaVersion => 1;

  Stream<List<Profile>> watchProfiles() => (select(profiles)
        ..orderBy([
          (t) => OrderingTerm.desc(t.importedAt),
          (t) => OrderingTerm.desc(t.version),
        ]))
      .watch();

  /// Stores imported metadata. Re-importing the same id + version replaces the
  /// earlier row (the replace/keep/merge choice arrives with real packages).
  Future<void> saveProfile(ProfileMetadata m, String sourcePath,
      {DateTime? importedAt}) {
    return into(profiles).insertOnConflictUpdate(ProfilesCompanion.insert(
      profileId: m.profileId,
      version: m.version,
      coachName: m.coachName,
      packId: m.packId,
      eventId: m.eventId,
      metricSchemaVersion: m.metricSchemaVersion,
      createdAt: m.createdAt,
      sourceClipCount: m.sourceClipCount,
      metricCount: m.metricCount,
      minClipsMet: m.minClipsMet,
      selfConsistencyPassed: m.selfConsistencyPassed,
      sourcePath: sourcePath,
      importedAt: importedAt ?? DateTime.now(),
    ));
  }

  Future<void> removeProfile(String profileId, int version) =>
      (delete(profiles)
            ..where(
                (t) => t.profileId.equals(profileId) & t.version.equals(version)))
          .go();
}
