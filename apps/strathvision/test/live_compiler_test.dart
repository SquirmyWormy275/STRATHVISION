// Opt-in live check for issue #5. Never runs in CI: it calls Claude through a
// signed-in Claude Code CLI on this computer (no API key needed).
//   LIVE_COMPILER=1 LIVE_OUT=/path/to/result.json \
//     flutter test test/live_compiler_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide ComparisonResult;
import 'package:strathvision/packs/pack_registry.dart';
import 'package:strathvision/workbench/claude_compiler.dart';

final _live = Platform.environment['LIVE_COMPILER'] == '1';
final _out = Platform.environment['LIVE_OUT'] ?? '';

class _Counting implements AdapterCompiler {
  _Counting(this.inner);
  final AdapterCompiler inner;
  int calls = 0;
  @override
  String get id => inner.id;
  @override
  Future<Map<String, AdapterOutput>> propose(
      AdapterSpec spec, AnalysisPack pack, List<String> inputNames,
      {List<String> feedback = const []}) {
    calls++;
    return inner.propose(spec, pack, inputNames, feedback: feedback);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('live: every timber adapter spec compiles and passes its examples',
      () async {
    final compiler = await ClaudeCodeAdapterCompiler.detect();
    expect(compiler, isNotNull, reason: 'claude CLI not installed');
    final packs = await loadPacks(rootBundle);
    final pack = activePack(packs, 'timber/underhand').analysisPack;
    final results = <Map<String, Object?>>[];
    for (final spec in pack.adapters) {
      final counting = _Counting(compiler!);
      final started = DateTime.now();
      final adapter = await compileAdapter(spec, pack, counting,
          now: DateTime.now().toUtc());
      results.add({
        'spec': spec.name,
        'examples': spec.examples.length,
        'attempts': counting.calls,
        'seconds': DateTime.now().difference(started).inSeconds,
        'adapter': adapter.toJson(),
      });
    }
    if (_out.isNotEmpty) {
      File(_out).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
        'compiler': compiler!.id,
        'pack': '${pack.packId}/${pack.eventId}',
        'ran_at': DateTime.now().toUtc().toIso8601String(),
        'results': results,
      }));
    }
    expect(results, hasLength(pack.adapters.length));

    // Phone path: reload the .paw files with no compiler and re-check every
    // example offline.
    final files = {
      for (final r in results)
        '${r['spec']}.paw': jsonEncode(r['adapter']),
    };
    final loaded = loadAdapters(files, pack, pack.adapters);
    expect(loaded.rejected, isEmpty);
    for (final spec in pack.adapters) {
      expect(checkExamples(spec, loaded.adapters[spec.name]!), isEmpty,
          reason: spec.name);
    }
  }, skip: !_live, timeout: const Timeout(Duration(minutes: 20)));
}
