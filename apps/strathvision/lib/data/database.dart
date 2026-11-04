import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../profiles/profile_package.dart';
import '../workspace/project.dart';
import '../workspace/workspace_controller.dart';

part 'database.g.dart';

/// Installed profile metadata. Phase 1 stores metadata only.
@DataClassName('ProfileRow')
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

/// Projects stored as the exact INTERFACES.md Project JSON.
@DataClassName('ProjectRow')
class ProjectRows extends Table {
  TextColumn get projectId => text()();
  TextColumn get name => text()();
  TextColumn get json => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {projectId};
}

@DriftDatabase(tables: [Profiles, ProjectRows])
class AppDatabase extends _$AppDatabase implements ProjectStore {
  AppDatabase([QueryExecutor? executor])
      : super(executor ??
            driftDatabase(
              name: 'strathvision',
              native: const DriftNativeOptions(
                databaseDirectory: getApplicationSupportDirectory,
              ),
            ));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(projectRows);
        },
      );

  // ---- projects -----------------------------------------------------------

  @override
  Future<void> saveProject(Project project) =>
      into(projectRows).insertOnConflictUpdate(ProjectRowsCompanion.insert(
        projectId: project.projectId,
        name: project.name,
        json: jsonEncode(project.toJson()),
        updatedAt: DateTime.now(),
      ));

  Future<Project?> loadProject(String projectId) async {
    final row = await (select(projectRows)
          ..where((t) => t.projectId.equals(projectId)))
        .getSingleOrNull();
    return row == null
        ? null
        : Project.fromJson(jsonDecode(row.json) as Map<String, Object?>);
  }

  Stream<List<ProjectRow>> watchProjects() => (select(projectRows)
        ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
      .watch();

  // ---- profiles -----------------------------------------------------------

  Stream<List<ProfileRow>> watchProfiles() => (select(profiles)
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
