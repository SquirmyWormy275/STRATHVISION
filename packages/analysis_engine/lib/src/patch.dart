import 'dart:convert';

import 'errors.dart';
import 'features.dart';
import 'heads.dart';

/// One sparse additive edit to a head tensor.
class PatchEdit {
  const PatchEdit(this.tensor, this.index, this.delta);
  final String tensor;
  final List<int> index;
  final double delta;

  Map<String, Object?> toJson() =>
      {'tensor': tensor, 'index': index, 'delta': delta};
}

/// A specialist patch (INTERFACES.md "Specialist Patch").
class SpecialistPatch {
  const SpecialistPatch({
    required this.head,
    required this.version,
    required this.base,
    required this.edits,
    this.notes = '',
  });

  final String head;
  final int version;
  final String base;
  final List<PatchEdit> edits;
  final String notes;

  /// Name used in `applied_patches`, e.g. `slope_residual_v3`.
  String get name => '${head}_v$version';
  String get fileName => '$name.patch';

  Map<String, Object?> toJson() => {
        'head': head,
        'version': version,
        'base': base,
        'edits': [for (final e in edits) e.toJson()],
        'notes': notes,
      };
}

/// Tensor shapes of an [MlpHead].
const _shapes = {
  'w1': [32, featureWidth],
  'b1': [32],
  'w2': [32],
  'b2': <int>[],
};

/// Fraction of a head's weights a patch must stay under (DECISIONS.md).
const maxPatchFraction = 0.02;

AnalysisError _reject(String file, List<String> problems) => AnalysisError(
    ErrorCode.patchRejected,
    'The patch $file was not applied.',
    {'file': file, 'problems': problems});

/// Parses and checks a patch file against [heads]. Throws [AnalysisError]
/// with PATCH_REJECTED listing every problem.
SpecialistPatch parsePatch(
    String fileName, String text, Map<String, SpecialistHead> heads) {
  final problems = <String>[];
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (e) {
    throw _reject(fileName, ['not valid JSON: ${e.message}']);
  }
  if (json is! Map) throw _reject(fileName, ['must be a JSON object']);

  final head = json['head'];
  final version = json['version'];
  final base = json['base'];
  final rawEdits = json['edits'];
  if (head is! String) problems.add('head must be a string');
  if (version is! int || version < 1) problems.add('version must be an integer >= 1');
  if (base is! String) problems.add('base must be a string');
  final h = head is String ? heads[head] : null;
  if (head is String && h == null) problems.add('unknown head "$head"');
  if (h != null && base is String && base != h.baseId) {
    problems.add('base "$base" does not match the head\'s base "${h.baseId}"');
  }
  if (head is String && version is int && fileName != '${head}_v$version.patch') {
    problems.add('file name must be ${head}_v$version.patch');
  }

  final edits = <PatchEdit>[];
  final seen = <String>{};
  if (rawEdits is! List || rawEdits.isEmpty) {
    problems.add('edits must be a non-empty list');
  } else {
    for (var i = 0; i < rawEdits.length; i++) {
      final e = rawEdits[i];
      final path = 'edits[$i]';
      if (e is! Map) {
        problems.add('$path must be an object');
        continue;
      }
      final tensor = e['tensor'];
      final index = e['index'];
      final delta = e['delta'];
      final shape = _shapes[tensor];
      if (shape == null) {
        problems.add('$path.tensor must be one of ${_shapes.keys.join(', ')}');
        continue;
      }
      if (index is! List ||
          index.length != shape.length ||
          index.any((x) => x is! int)) {
        problems.add('$path.index must have ${shape.length} integers for $tensor');
        continue;
      }
      final idx = index.cast<int>();
      var inRange = true;
      for (var d = 0; d < shape.length; d++) {
        if (idx[d] < 0 || idx[d] >= shape[d]) inRange = false;
      }
      if (!inRange) {
        problems.add('$path.index $idx is out of range for $tensor $shape');
        continue;
      }
      if (delta is! num || delta.isNaN || delta.isInfinite) {
        problems.add('$path.delta must be a finite number');
        continue;
      }
      if (!seen.add('$tensor$idx')) {
        problems.add('$path duplicates an earlier edit');
        continue;
      }
      edits.add(PatchEdit(tensor as String, idx, delta.toDouble()));
    }
  }
  if (h != null && edits.length >= h.parameterCount * maxPatchFraction) {
    problems.add('touches ${edits.length} of ${h.parameterCount} weights '
        '(must be under ${(maxPatchFraction * 100).round()}%)');
  }
  if (problems.isNotEmpty) throw _reject(fileName, problems);
  return SpecialistPatch(
    head: head as String,
    version: version as int,
    base: base as String,
    edits: edits,
    notes: json['notes'] is String ? json['notes'] as String : '',
  );
}

/// Result of loading a package's `specialist_patches/`.
class PatchSet {
  const PatchSet({required this.applied, required this.rejected});

  /// Highest valid version per head.
  final List<SpecialistPatch> applied;
  final List<AnalysisError> rejected;

  static const empty = PatchSet(applied: [], rejected: []);

  List<String> get appliedNames => [for (final p in applied) p.name];
}

/// Parses every patch file and keeps the highest valid version per head.
/// [files] maps file name → contents.
PatchSet loadPatches(Map<String, String> files, List<SpecialistHead> heads) {
  final byName = {for (final h in heads) h.name: h};
  final best = <String, SpecialistPatch>{};
  final rejected = <AnalysisError>[];
  final names = files.keys.toList()..sort();
  for (final name in names) {
    try {
      final p = parsePatch(name, files[name]!, byName);
      final cur = best[p.head];
      if (cur == null || p.version > cur.version) best[p.head] = p;
    } on AnalysisError catch (e) {
      rejected.add(e);
    }
  }
  final applied = best.values.toList()..sort((a, b) => a.head.compareTo(b.head));
  return PatchSet(applied: applied, rejected: rejected);
}

/// [heads] with [patches] applied. Heads without a patch are unchanged.
List<SpecialistHead> applyPatches(
    List<SpecialistHead> heads, List<SpecialistPatch> patches) {
  return [
    for (final h in heads)
      () {
        final p = patches.where((p) => p.head == h.name).firstOrNull;
        if (p == null || h is! MlpHead) return h;
        return patchedMlpHead(
            h, [for (final e in p.edits) (e.tensor, e.index, e.delta)]);
      }(),
  ];
}

/// The specialist heads every engine starts from.
List<SpecialistHead> defaultHeads() => [stubSlopeResidualHead()];
