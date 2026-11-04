import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../workspace/project.dart';
import 'profile_export.dart';
import 'profile_package.dart';

/// Export choices (DECISIONS.md "Coaching Packages and Remote").
enum ExportChoice {
  /// Default: profile, specialist patches, adapters.
  profileOnly('Coaching profile only'),

  /// Plus the red/green marks on this event's attributes (no video, no paths).
  withMarks('Coaching profile + my marks'),

  /// Plus comparison history and CARNE ASADA research records.
  fullOverlay('Full local overlay');

  const ExportChoice(this.label);
  final String label;
}

/// What an export will write, for the summary shown before writing.
class ExportPlan {
  ExportPlan({required this.fileName, required this.entries, required this.summary});
  final String fileName;

  /// Path in the zip → contents (null = directory).
  final Map<String, String?> entries;

  /// One line per kind of content.
  final List<String> summary;

  Uint8List zip() {
    final archive = Archive();
    for (final e in entries.entries) {
      archive.add(e.value == null
          ? ArchiveFile.directory(e.key)
          : ArchiveFile.bytes(e.key, utf8.encode(e.value!)));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}

const marksFile = 'marks/marks.json';
const historyFile = 'history/comparisons.json';

/// Research files under `carne_asada/` of a package (desktop only).
Future<Map<String, String>> _research(String path) async {
  if (p.extension(path).toLowerCase() != '.zip') return const {};
  final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
  return {
    for (final f in archive.files)
      if (f.isFile && f.name.contains('carne_asada/'))
        p.basename(f.name): utf8.decode(f.content as List<int>),
  };
}

Future<ExportPlan> planExport(AppDatabase db, ProfileRow row, ExportChoice choice,
    {required List<String> attributes}) async {
  final b = await readProfileBundle(row.sourcePath);
  final entries = <String, String?>{
    ...b.profile.packageEntries(),
    for (final e in b.patchFiles.entries) 'specialist_patches/${e.key}': e.value,
    for (final e in b.adapterFiles.entries) 'adapters/${e.key}': e.value,
  };
  final summary = <String>[
    '${b.profile.coachName} · v${b.profile.version}: ${b.profile.metrics.length} measurements, '
        '${b.profile.sourceClipCount} clips',
    if (b.patchFiles.isNotEmpty) '${b.patchFiles.length} specialist patch(es)',
    if (b.adapterFiles.isNotEmpty) '${b.adapterFiles.length} adapter(s)',
  ];
  if (choice != ExportChoice.profileOnly) {
    final marks = <Map<String, Object?>>[];
    for (final r in await db.select(db.projectRows).get()) {
      final project = Project.fromJson(jsonDecode(r.json) as Map<String, Object?>);
      final names = {for (final c in project.clips) c.clipId: c.displayName};
      for (final m in project.marks) {
        if (!attributes.contains(m.attribute)) continue;
        marks.add({
          'clip': names[m.clipId] ?? 'clip',
          'time_ms': m.timeMs,
          'attribute': m.attribute,
          'label': m.label.name,
          'author': m.author.name,
          'created_at': m.createdAt.toUtc().toIso8601String(),
        });
      }
    }
    entries[marksFile] = const JsonEncoder.withIndent('  ').convert(marks);
    summary.add('${marks.length} red/green marks (file names only, no video)');
  }
  if (choice == ExportChoice.fullOverlay) {
    final rows = await db.comparisonsForProfile(row.profileId);
    entries[historyFile] = const JsonEncoder.withIndent('  ').convert([
      for (final r in rows)
        {'created_at': r.createdAt.toUtc().toIso8601String(), 'result': jsonDecode(r.json)},
    ]);
    summary.add('${rows.length} past comparisons (match trend)');
    final research = await _research(row.sourcePath);
    if (research.isNotEmpty) {
      entries['carne_asada/'] = null;
      for (final e in research.entries) {
        entries['carne_asada/${e.key}'] = e.value;
      }
      summary.add('${research.length} CARNE ASADA research record(s)');
    }
  }
  return ExportPlan(fileName: packageFileName(b.profile), entries: entries, summary: summary);
}

/// What to do when an imported package's profile is already installed.
enum ImportChoice {
  /// Install it and remove the other installed versions of that profile.
  replace('Replace'),

  /// Install it next to the versions already here.
  keep('Keep both'),

  /// Keep both, and also bring in its marks and match history.
  merge('Merge');

  const ImportChoice(this.label);
  final String label;
}

/// Installs [path] (already validated as [meta]) according to [choice].
/// Returns a plain-language result.
Future<String> applyImport(AppDatabase db, String path, ProfileMetadata meta,
    ImportChoice? choice, Future<Directory> Function() storeDir) async {
  final existing = [
    for (final r in await db.allProfiles()) if (r.profileId == meta.profileId) r,
  ];
  if (choice == ImportChoice.keep && existing.any((r) => r.version == meta.version)) {
    return 'Kept ${meta.coachName} · v${meta.version}; it was already here.';
  }
  var copy = path;
  if (p.extension(path).toLowerCase() == '.zip') {
    // Keep a private copy so the Library survives the original moving.
    final store = await storeDir();
    await store.create(recursive: true);
    copy = (await File(path).copy(
            p.join(store.path, '${meta.profileId}_v${meta.version}.zip')))
        .path;
  }
  if (choice == ImportChoice.replace) {
    for (final r in existing.where((r) => r.version != meta.version)) {
      await db.removeProfile(r.profileId, r.version);
    }
  }
  await db.saveProfile(meta, copy);
  var extra = '';
  if (choice == ImportChoice.merge && p.extension(path).toLowerCase() == '.zip') {
    extra = await _mergeExtras(db, path, meta);
  }
  final verb = switch (choice) {
    ImportChoice.replace => 'Replaced with',
    ImportChoice.merge => 'Merged',
    _ => 'Imported',
  };
  return '$verb ${meta.coachName} · v${meta.version}$extra';
}

Future<String> _mergeExtras(AppDatabase db, String path, ProfileMetadata meta) async {
  final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
  String? read(String name) {
    final f = archive.files.where((f) => f.isFile && f.name.endsWith(name)).firstOrNull;
    return f == null ? null : utf8.decode(f.content as List<int>);
  }

  final parts = <String>[];
  final history = read(historyFile);
  if (history != null) {
    final list = (jsonDecode(history) as List).cast<Map<String, Object?>>();
    var n = 0;
    for (final h in list) {
      final result = Map<String, Object?>.from(h['result'] as Map);
      await db.into(db.comparisonRows).insertOnConflictUpdate(ComparisonRowsCompanion.insert(
            resultId: result['result_id'] as String,
            projectId: 'imported',
            clipId: result['clip_id'] as String,
            profileId: result['profile_id'] as String,
            profileVersion: (result['profile_version'] as num).toInt(),
            overallScore: (result['overall_score'] as num).toDouble(),
            json: jsonEncode(result),
            createdAt: DateTime.parse(h['created_at'] as String),
          ));
      n++;
    }
    parts.add('$n past comparisons');
  }
  final marks = read(marksFile);
  if (marks != null) {
    final list = (jsonDecode(marks) as List).cast<Map<String, Object?>>();
    if (list.isNotEmpty) {
      // Bind marks to clips on this device with the same file name; keep the
      // rest under their names (clips not on this device).
      final local = <String, String>{};
      for (final r in await db.select(db.projectRows).get()) {
        final project = Project.fromJson(jsonDecode(r.json) as Map<String, Object?>);
        for (final c in project.clips) {
          local[c.displayName] = c.path;
        }
      }
      const uuid = Uuid();
      final clips = <String, Clip>{};
      final out = <Mark>[];
      for (final m in list) {
        final name = m['clip'] as String;
        final clip = clips.putIfAbsent(
            name,
            () => Clip(
                clipId: uuid.v4(),
                path: local[name] ?? '',
                displayName: name,
                addedAt: DateTime.now()));
        out.add(Mark(
          markId: uuid.v4(),
          clipId: clip.clipId,
          timeMs: (m['time_ms'] as num).toInt(),
          attribute: m['attribute'] as String,
          label: MarkLabel.values.byName(m['label'] as String),
          author: MarkAuthor.values.byName(m['author'] as String),
          createdAt: DateTime.parse(m['created_at'] as String),
        ));
      }
      await db.saveProject(Project(
        projectId: uuid.v4(),
        name: 'Marks from ${meta.coachName} · v${meta.version}',
        clips: clips.values.toList(),
        marks: out,
      ));
      final matched = clips.values.where((c) => c.path.isNotEmpty).length;
      parts.add('${out.length} marks ($matched of ${clips.length} clips found here)');
    }
  }
  return parts.isEmpty ? '' : ', with ${parts.join(' and ')}';
}
