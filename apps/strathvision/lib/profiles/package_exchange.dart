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
import 'source_identity.dart';

import 'package:crypto/crypto.dart';
import 'package:analysis_engine/analysis_engine.dart'
    show validateComparisonResult;

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
  ExportPlan({
    required this.fileName,
    required this.entries,
    required this.summary,
  });
  final String fileName;

  /// Path in the zip → contents (null = directory).
  final Map<String, String?> entries;

  /// One line per kind of content.
  final List<String> summary;

  Uint8List zip() {
    final archive = Archive();
    for (final e in entries.entries) {
      archive.add(
        e.value == null
            ? ArchiveFile.directory(e.key)
            : ArchiveFile.bytes(e.key, utf8.encode(e.value!)),
      );
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

Future<ExportPlan> planExport(
  AppDatabase db,
  ProfileRow row,
  ExportChoice choice, {
  required List<String> attributes,
}) async {
  final b = await readProfileBundle(row.sourcePath);
  final entries = <String, String?>{
    ...b.profile.packageEntries(),
    for (final e in b.patchFiles.entries)
      'specialist_patches/${e.key}': e.value,
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
    final seen = <String>{};
    var excluded = 0;
    for (final r in await db.select(db.projectRows).get()) {
      final project = Project.fromJson(
        jsonDecode(r.json) as Map<String, Object?>,
      );
      final names = {for (final c in project.clips) c.clipId: c.displayName};
      for (final m in project.marks) {
        if (!attributes.contains(m.attribute)) continue;
        if (m.packId != row.packId ||
            m.eventId != row.eventId ||
            m.sourceSha256 == null) {
          excluded++;
          continue;
        }
        if (!seen.add(m.markId)) continue;
        marks.add({
          'clip': names[m.clipId] ?? 'clip',
          'mark_id': m.markId,
          'pack_id': m.packId,
          'event_id': m.eventId,
          'source_sha256': m.sourceSha256,
          'time_ms': m.timeMs,
          'attribute': m.attribute,
          'label': m.label.name,
          'author': m.author.name,
          'created_at': m.createdAt.toUtc().toIso8601String(),
        });
      }
    }
    entries[marksFile] = const JsonEncoder.withIndent('  ').convert(marks);
    summary.add(
      '${marks.length} red/green marks (content identities, no video)',
    );
    if (excluded > 0) {
      summary.add(
        '$excluded marks excluded: missing provenance or another event. Originals stay on this device.',
      );
    }
  }
  if (choice == ExportChoice.fullOverlay) {
    final rows = (await db.comparisonsForProfile(row.profileId))
        .where((r) => r.profileVersion == row.version)
        .toList();
    entries[historyFile] = const JsonEncoder.withIndent('  ').convert([
      for (final r in rows)
        {
          'created_at': r.createdAt.toUtc().toIso8601String(),
          'result': jsonDecode(r.json),
        },
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
  return ExportPlan(
    fileName: packageFileName(b.profile),
    entries: entries,
    summary: summary,
  );
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
Future<String> applyImport(
  AppDatabase db,
  String path,
  ProfileMetadata meta,
  ImportChoice? choice,
  Future<Directory> Function() storeDir,
) async {
  final existing = [
    for (final r in await db.allProfiles())
      if (r.profileId == meta.profileId) r,
  ];
  if (choice == ImportChoice.keep &&
      existing.any((r) => r.version == meta.version)) {
    return 'Kept ${meta.coachName} · v${meta.version}; it was already here.';
  }
  String? stored;
  try {
    final extras = choice == ImportChoice.merge
        ? await _readExtras(path, meta)
        : _Extras();
    final store = await storeDir();
    await store.create(recursive: true);
    // Normalize JSON/directory imports too; the original can be moved safely.
    final bundle = await readProfileBundle(path);
    stored = p.join(store.path, '${const Uuid().v4()}.zip');
    if (p.extension(path).toLowerCase() == '.zip') {
      await File(path).copy(stored);
    } else {
      await File(stored).writeAsBytes(
        zipProfilePackage(
          bundle.profile,
          patches: bundle.patchFiles,
          adapters: bundle.adapterFiles,
        ),
        flush: true,
      );
    }
    var extra = '';
    await db.transaction(() async {
      if (choice == ImportChoice.replace) {
        for (final r in existing.where((r) => r.version != meta.version)) {
          await db.removeProfile(r.profileId, r.version);
        }
      }
      await db.saveProfile(meta, stored!);
      if (choice == ImportChoice.merge) {
        extra = await _mergeExtras(db, extras, meta);
      }
    });
    final verb = switch (choice) {
      ImportChoice.replace => 'Replaced with',
      ImportChoice.merge => 'Merged',
      _ => 'Imported',
    };
    return '$verb ${meta.coachName} · v${meta.version}$extra';
  } catch (error) {
    if (stored != null && await File(stored).exists()) {
      await File(stored).delete();
    }
    if (error is AnalysisError) rethrow;
    throw AnalysisError(
      ErrorCode.schemaMismatch,
      'The package could not be imported. Nothing was changed.',
    );
  }
}

class _Extras {
  final List<Map<String, Object?>> marks = [];
  final List<Map<String, Object?>> history = [];
}

Future<_Extras> _readExtras(String path, ProfileMetadata meta) async {
  final out = _Extras();
  if (p.extension(path).toLowerCase() != '.zip') return out;
  final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
  List<Map<String, Object?>> read(String name) {
    final fs = archive.files.where((f) => f.isFile && f.name == name).toList();
    if (fs.length > 1) throw const FormatException('Duplicate package entry');
    if (fs.isEmpty) return [];
    return (jsonDecode(utf8.decode(fs.single.content as List<int>)) as List)
        .map((v) => Map<String, Object?>.from(v as Map))
        .toList();
  }

  for (final h in read(historyFile)) {
    final r = Map<String, Object?>.from(h['result'] as Map);
    if (validateComparisonResult(r).isNotEmpty ||
        r['profile_id'] != meta.profileId ||
        r['profile_version'] != meta.version) {
      throw const FormatException('Invalid or unrelated history');
    }
    DateTime.parse(h['created_at'] as String);
    out.history.add(h);
  }
  for (final m in read(marksFile)) {
    if (m['clip'] is! String ||
        m['attribute'] is! String ||
        m['time_ms'] is! int ||
        (m['time_ms'] as int) < 0) {
      throw const FormatException('Invalid mark');
    }
    MarkLabel.values.byName(m['label'] as String);
    MarkAuthor.values.byName(m['author'] as String);
    DateTime.parse(m['created_at'] as String);
    final hash = m['source_sha256'];
    if (hash != null &&
        (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))) {
      throw const FormatException('Invalid source identity');
    }
    final identified =
        hash != null &&
        m['mark_id'] is String &&
        m['pack_id'] == meta.packId &&
        m['event_id'] == meta.eventId;
    // Legacy records stay available but cannot be bound to local video.
    out.marks.add({...m, '_identified': identified});
  }
  return out;
}

Future<String> _mergeExtras(
  AppDatabase db,
  _Extras extras,
  ProfileMetadata meta,
) async {
  final parts = <String>[];
  for (final h in extras.history) {
    final result = Map<String, Object?>.from(h['result'] as Map);
    await db
        .into(db.comparisonRows)
        .insertOnConflictUpdate(
          ComparisonRowsCompanion.insert(
            resultId: result['result_id'] as String,
            projectId: 'imported',
            clipId: result['clip_id'] as String,
            profileId: meta.profileId,
            profileVersion: result['profile_version'] as int,
            overallScore: (result['overall_score'] as num).toDouble(),
            json: jsonEncode(result),
            createdAt: DateTime.parse(h['created_at'] as String),
          ),
        );
  }
  if (extras.history.isNotEmpty) {
    parts.add('${extras.history.length} past comparisons');
  }
  if (extras.marks.isNotEmpty) {
    final local = <String, String>{};
    final existingMarks = <String>{};
    final paths = <String>{};
    for (final r in await db.select(db.projectRows).get()) {
      final project = Project.fromJson(
        jsonDecode(r.json) as Map<String, Object?>,
      );
      existingMarks.addAll(project.marks.map((m) => m.markId));
      paths.addAll(project.clips.map((c) => c.path).where((p) => p.isNotEmpty));
    }
    for (final path in paths) {
      try {
        local[await sourceHash(path)] = path;
      } catch (_) {
        /* unavailable media */
      }
    }
    final clips = <String, Clip>{};
    final marks = <Mark>[];
    for (final m in extras.marks) {
      final identified = m['_identified'] == true;
      final hash = m['source_sha256'] as String?;
      final identity = identified
          ? m['mark_id'] as String
          : 'legacy:${sha256.convert(utf8.encode(jsonEncode(m)))}';
      if (!existingMarks.add(identity)) continue;
      final key = identified ? hash! : identity;
      final clip = clips.putIfAbsent(
        key,
        () => Clip(
          clipId: const Uuid().v4(),
          path: identified ? local[hash] ?? '' : '',
          displayName: m['clip'] as String,
          addedAt: DateTime.now(),
        ),
      );
      marks.add(
        Mark(
          markId: identity,
          clipId: clip.clipId,
          timeMs: m['time_ms'] as int,
          attribute: m['attribute'] as String,
          label: MarkLabel.values.byName(m['label'] as String),
          author: MarkAuthor.values.byName(m['author'] as String),
          createdAt: DateTime.parse(m['created_at'] as String),
          packId: identified ? meta.packId : null,
          eventId: identified ? meta.eventId : null,
          sourceSha256: identified ? hash : null,
        ),
      );
    }
    if (marks.isNotEmpty) {
      await db.saveProject(
        Project(
          projectId: const Uuid().v4(),
          name: 'Marks from ${meta.coachName} · v${meta.version}',
          clips: clips.values.toList(),
          marks: marks,
        ),
      );
    }
    final matched = clips.values.where((c) => c.path.isNotEmpty).length;
    parts.add(
      '${marks.length} new marks ($matched of ${clips.length} clips verified here)',
    );
  }
  return parts.isEmpty ? '' : ', with ${parts.join(' and ')}';
}
