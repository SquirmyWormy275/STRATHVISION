import 'dart:convert';
import 'dart:math' as math;

import 'contracts.dart';
import 'errors.dart';
import 'pack.dart';

/// A fuzzy decision written as a short English spec in the pack
/// (DECISIONS.md "Compile-Once Adapters").
class AdapterSpec {
  const AdapterSpec({
    required this.name,
    required this.spec,
    required this.outputs,
    required this.examples,
    this.threshold,
  });

  final String name;
  final String spec;

  /// Output names. With [threshold], each is a yes/no decision; without,
  /// outputs are competing scores (the highest wins).
  final List<String> outputs;
  final double? threshold;

  /// Each: `{"inputs": {name: number}, "expect": {output: bool} | {"top": output}}`.
  final List<Map<String, Object?>> examples;

  /// Identifies the spec text and examples; a compiled adapter whose hash
  /// differs is stale and must be recompiled.
  String get specHash {
    final text = jsonEncode({
      'name': name,
      'spec': spec,
      'outputs': outputs,
      'threshold': threshold,
      'examples': examples,
    });
    var h = 0xcbf29ce484222325;
    for (final u in utf8.encode(text)) {
      h ^= u;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  static List<AdapterSpec> listFromJson(Object? raw, List<String> problems) {
    if (raw == null) return const [];
    if (raw is! List) {
      problems.add('adapters must be a list');
      return const [];
    }
    final out = <AdapterSpec>[];
    for (var i = 0; i < raw.length; i++) {
      final a = raw[i];
      final path = 'adapters[$i]';
      if (a is! Map) {
        problems.add('$path must be an object');
        continue;
      }
      final name = a['name'], spec = a['spec'], outputs = a['outputs'];
      final examples = a['examples'] ?? const [];
      final threshold = a['threshold'];
      if (name is! String || !RegExp(r'^[a-z0-9_]+$').hasMatch(name)) {
        problems.add('$path.name must be lower_snake_case');
      } else if (spec is! String || spec.trim().isEmpty) {
        problems.add('$path.spec must be non-empty English');
      } else if (outputs is! List ||
          outputs.isEmpty ||
          outputs.any((o) => o is! String)) {
        problems.add('$path.outputs must be a non-empty list of names');
      } else if (threshold != null && (threshold is! num || threshold <= 0 || threshold >= 1)) {
        problems.add('$path.threshold must be in (0, 1)');
      } else if (examples is! List || examples.any((e) => e is! Map)) {
        problems.add('$path.examples must be a list of objects');
      } else if (out.any((x) => x.name == name)) {
        problems.add('$path.name is duplicated');
      } else {
        out.add(AdapterSpec(
          name: name,
          spec: spec,
          outputs: outputs.cast<String>(),
          threshold: (threshold as num?)?.toDouble(),
          examples: [for (final e in examples) Map<String, Object?>.from(e as Map)],
        ));
      }
    }
    return out;
  }
}

/// One output of a compiled adapter: logistic over named inputs.
class AdapterOutput {
  const AdapterOutput({required this.bias, required this.weights});
  final double bias;
  final Map<String, double> weights;

  double score(Map<String, double> inputs) {
    var z = bias;
    for (final e in weights.entries) {
      z += e.value * (inputs[e.key] ?? 0);
    }
    return 1 / (1 + math.exp(-z));
  }
}

/// A compiled adapter (`adapters/<name>.paw`): a tiny local model. Runs with
/// no LLM call.
class CompiledAdapter {
  const CompiledAdapter({
    required this.name,
    required this.packId,
    required this.eventId,
    required this.specHash,
    required this.compiledBy,
    required this.compiledAt,
    required this.outputs,
    this.threshold,
  });

  final String name;
  final String packId;
  final String eventId;
  final String specHash;
  final String compiledBy;
  final DateTime compiledAt;
  final Map<String, AdapterOutput> outputs;
  final double? threshold;

  String get fileName => '$name.paw';

  /// Score per output, 0..1.
  Map<String, double> scores(Map<String, double> inputs) =>
      {for (final e in outputs.entries) e.key: e.value.score(inputs)};

  /// Yes/no per output (threshold adapters).
  Map<String, bool> decide(Map<String, double> inputs) => {
        for (final e in scores(inputs).entries) e.key: e.value >= (threshold ?? 0.5),
      };

  /// Highest-scoring output (score adapters); ties by name.
  String top(Map<String, double> inputs) {
    final s = scores(inputs).entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return s.first.key;
  }

  Map<String, Object?> toJson() => {
        'format': 'paw/1',
        'adapter': name,
        'pack_id': packId,
        'event_id': eventId,
        'spec_hash': specHash,
        'compiled_by': compiledBy,
        'compiled_at': compiledAt.toUtc().toIso8601String(),
        'kind': 'logistic',
        'threshold': threshold,
        'outputs': {
          for (final e in outputs.entries)
            e.key: {'bias': e.value.bias, 'weights': e.value.weights},
        },
      };

  /// Parses a `.paw` file. Throws ADAPTER_COMPILE_FAILED on a bad file.
  factory CompiledAdapter.parse(String fileName, String text) {
    AnalysisError bad(String why) => AnalysisError(ErrorCode.adapterCompileFailed,
        'The adapter $fileName could not be read.', {'file': fileName, 'problems': [why]});
    final Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException catch (e) {
      throw bad('not valid JSON: ${e.message}');
    }
    if (j is! Map || j['format'] != 'paw/1' || j['kind'] != 'logistic') {
      throw bad('format must be paw/1 with kind logistic');
    }
    final outs = j['outputs'];
    if (outs is! Map || outs.isEmpty) throw bad('outputs must be a non-empty object');
    final outputs = <String, AdapterOutput>{};
    for (final e in outs.entries) {
      final o = e.value;
      if (o is! Map || o['bias'] is! num || o['weights'] is! Map ||
          (o['weights'] as Map).values.any((w) => w is! num)) {
        throw bad('outputs.${e.key} needs a numeric bias and weights');
      }
      outputs['${e.key}'] = AdapterOutput(
        bias: (o['bias'] as num).toDouble(),
        weights: {
          for (final w in (o['weights'] as Map).entries) '${w.key}': (w.value as num).toDouble(),
        },
      );
    }
    for (final k in ['adapter', 'pack_id', 'event_id', 'spec_hash', 'compiled_by', 'compiled_at']) {
      if (j[k] is! String) throw bad('$k must be a string');
    }
    if ('${j['adapter']}.paw' != fileName) throw bad('file name must be ${j['adapter']}.paw');
    final t = j['threshold'];
    return CompiledAdapter(
      name: j['adapter'] as String,
      packId: j['pack_id'] as String,
      eventId: j['event_id'] as String,
      specHash: j['spec_hash'] as String,
      compiledBy: j['compiled_by'] as String,
      compiledAt: DateTime.tryParse(j['compiled_at'] as String) ?? DateTime.utc(1970),
      outputs: outputs,
      threshold: t is num ? t.toDouble() : null,
    );
  }
}

/// The generic inputs adapters may use, from one analysis (and comparison).
/// Names: `pose_confidence`, `implement_confidence`, `phase_confidence.PHASE`,
/// `phase_seconds.PHASE`, `metric.KEY`, `metric_confidence.KEY`, and with a
/// comparison `delta.KEY` (signed, in spreads), `abs_delta.KEY` and
/// `contribution.KEY`.
Map<String, double> adapterInputs(MetricVector v,
    {double implementConfidence = 0, ComparisonResult? comparison, double fps = 30}) {
  final x = <String, double>{
    'pose_confidence': v.poseConfidenceSummary,
    'implement_confidence': implementConfidence,
  };
  for (final e in v.phases.entries) {
    x['phase_confidence.${e.key}'] = e.value.confidence;
    x['phase_seconds.${e.key}'] = (e.value.endFrame - e.value.startFrame + 1) / fps;
  }
  for (final e in v.metrics.entries) {
    x['metric.${e.key}'] = e.value.value;
    x['metric_confidence.${e.key}'] = e.value.confidence;
  }
  for (final d in comparison?.rankedDeltas ?? const <RankedDelta>[]) {
    final signed = d.userValue >= d.coachCenter ? d.distanceSpreads : -d.distanceSpreads;
    x['delta.${d.metricKey}'] = signed;
    x['abs_delta.${d.metricKey}'] = d.distanceSpreads;
    x['contribution.${d.metricKey}'] = d.contribution;
  }
  return x;
}

/// Every input name an adapter for [pack] may use.
List<String> adapterInputNames(AnalysisPack pack, {bool withComparison = false}) => [
      'pose_confidence',
      'implement_confidence',
      for (final p in pack.phases) ...['phase_confidence.$p', 'phase_seconds.$p'],
      for (final m in pack.metrics) ...['metric.${m.key}', 'metric_confidence.${m.key}'],
      if (withComparison)
        for (final m in pack.metrics)
          ...['delta.${m.key}', 'abs_delta.${m.key}', 'contribution.${m.key}'],
    ];

/// Checks [adapter] against every example in [spec]. Empty = all agree.
List<String> checkExamples(AdapterSpec spec, CompiledAdapter adapter) {
  final problems = <String>[];
  for (var i = 0; i < spec.examples.length; i++) {
    final ex = spec.examples[i];
    final inputs = {
      for (final e in (ex['inputs'] as Map? ?? const {}).entries)
        '${e.key}': (e.value as num).toDouble(),
    };
    final expect = Map<String, Object?>.from(ex['expect'] as Map? ?? const {});
    if (expect.containsKey('top')) {
      final got = adapter.top(inputs);
      if (got != expect['top']) problems.add('example $i: expected ${expect['top']}, got $got');
    } else {
      final got = adapter.decide(inputs);
      for (final e in expect.entries) {
        if (got[e.key] != e.value) {
          problems.add('example $i: expected ${e.key}=${e.value}, got ${got[e.key]}');
        }
      }
    }
  }
  return problems;
}

/// Turns an English spec into adapter weights, once, at workbench time.
abstract class AdapterCompiler {
  /// Recorded in the `.paw` file (for example the model id).
  String get id;

  /// Returns weights for each output: `{output: {"bias": n, "weights": {input: n}}}`.
  /// [feedback] lists example mismatches from the previous attempt.
  Future<Map<String, AdapterOutput>> propose(AdapterSpec spec, AnalysisPack pack,
      List<String> inputNames, {List<String> feedback = const []});
}

/// Compiles [spec] with [compiler], validating against the spec's examples.
/// Retries with feedback up to [attempts] times; then ADAPTER_COMPILE_FAILED.
Future<CompiledAdapter> compileAdapter(
  AdapterSpec spec,
  AnalysisPack pack,
  AdapterCompiler compiler, {
  required DateTime now,
  int attempts = 3,
}) async {
  final inputNames = adapterInputNames(pack, withComparison: true);
  var feedback = <String>[];
  for (var a = 0; a < attempts; a++) {
    Map<String, AdapterOutput> outs;
    try {
      outs = await compiler.propose(spec, pack, inputNames, feedback: feedback);
    } on AnalysisError {
      rethrow;
    } on Object catch (e) {
      throw AnalysisError(ErrorCode.adapterCompileFailed,
          'The adapter ${spec.name} could not be compiled.', {'cause': '$e'});
    }
    final problems = <String>[];
    if (outs.keys.toSet().difference(spec.outputs.toSet()).isNotEmpty ||
        spec.outputs.any((o) => !outs.containsKey(o))) {
      problems.add('outputs must be exactly ${spec.outputs.join(', ')}');
    }
    for (final o in outs.values) {
      for (final k in o.weights.keys) {
        if (!inputNames.contains(k)) problems.add('unknown input "$k"');
      }
      if (!o.bias.isFinite || o.weights.values.any((w) => !w.isFinite)) {
        problems.add('weights must be finite');
      }
    }
    if (problems.isEmpty) {
      final adapter = CompiledAdapter(
        name: spec.name,
        packId: pack.packId,
        eventId: pack.eventId,
        specHash: spec.specHash,
        compiledBy: compiler.id,
        compiledAt: now.toUtc(),
        outputs: outs,
        threshold: spec.threshold,
      );
      problems.addAll(checkExamples(spec, adapter));
      if (problems.isEmpty) return adapter;
    }
    feedback = problems;
  }
  throw AnalysisError(ErrorCode.adapterCompileFailed,
      'The adapter ${spec.name} did not satisfy its examples.',
      {'adapter': spec.name, 'problems': feedback});
}

/// Adapters loaded from a package for one event.
class AdapterSet {
  const AdapterSet({required this.adapters, required this.rejected});
  final Map<String, CompiledAdapter> adapters;

  /// Adapters skipped (unreadable, other event, or stale), as warnings.
  final List<String> rejected;

  static const empty = AdapterSet(adapters: {}, rejected: []);
}

/// Loads `adapters/*.paw` for [pack]. Stale adapters (spec changed) and
/// adapters for another event are skipped with a reason.
AdapterSet loadAdapters(Map<String, String> files, AnalysisPack pack, List<AdapterSpec> specs) {
  final out = <String, CompiledAdapter>{};
  final rejected = <String>[];
  final names = files.keys.toList()..sort();
  for (final f in names) {
    try {
      final a = CompiledAdapter.parse(f, files[f]!);
      final spec = specs.where((s) => s.name == a.name).firstOrNull;
      if (a.packId != pack.packId || a.eventId != pack.eventId) {
        rejected.add('Adapter ${a.name} is for another event.');
      } else if (spec == null) {
        rejected.add('Adapter ${a.name} is not in this pack.');
      } else if (spec.specHash != a.specHash) {
        rejected.add('Adapter ${a.name} is out of date; recompile it on the workbench.');
      } else {
        out[a.name] = a;
      }
    } on AnalysisError catch (e) {
      rejected.add(e.message);
    }
  }
  return AdapterSet(adapters: out, rejected: rejected);
}
