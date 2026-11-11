import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analysis_engine/analysis_engine.dart';

/// POSTs [body] to [url] with [headers]; returns (status, response body).
typedef HttpPost = Future<(int, String)> Function(
    Uri url, Map<String, String> headers, String body);

Future<(int, String)> _ioPost(Uri url, Map<String, String> headers, String body) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(url);
    headers.forEach(req.headers.set);
    req.add(utf8.encode(body));
    final res = await req.close();
    return (res.statusCode, await res.transform(utf8.decoder).join());
  } finally {
    client.close();
  }
}

/// Compiles adapter specs with Claude through the Messages API, once, on
/// the workbench. Dart has no official Anthropic SDK, so this is raw HTTP.
/// Inference never calls it: compiled adapters run locally.
class ClaudeAdapterCompiler implements AdapterCompiler {
  ClaudeAdapterCompiler({
    required this.apiKey,
    this.model = 'claude-opus-5-5',
    HttpPost? post,
  }) : _post = post ?? _ioPost;

  /// Reads `ANTHROPIC_API_KEY`; null when unset.
  static ClaudeAdapterCompiler? fromEnvironment({HttpPost? post}) {
    final key = Platform.environment['ANTHROPIC_API_KEY'];
    if (key == null || key.isEmpty) return null;
    return ClaudeAdapterCompiler(apiKey: key, post: post);
  }

  final String apiKey;
  final String model;
  final HttpPost _post;

  static final _url = Uri.parse('https://api.anthropic.com/v1/messages');

  @override
  String get id => model;

  /// JSON schema for the structured output: one entry per output, weights
  /// restricted to the allowed input names.
  static Map<String, Object?> schema(AdapterSpec spec, List<String> inputNames) => {
        'type': 'object',
        'additionalProperties': false,
        'required': ['outputs'],
        'properties': {
          'outputs': {
            'type': 'array',
            'items': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['name', 'bias', 'weights'],
              'properties': {
                'name': {'type': 'string', 'enum': spec.outputs},
                'bias': {'type': 'number'},
                'weights': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'additionalProperties': false,
                    'required': ['input', 'weight'],
                    'properties': {
                      'input': {'type': 'string', 'enum': inputNames},
                      'weight': {'type': 'number'},
                    },
                  },
                },
              },
            },
          },
        },
      };

  static String prompt(AdapterSpec spec, AnalysisPack pack, List<String> inputNames,
      List<String> feedback) {
    final kind = spec.threshold == null
        ? 'The outputs compete: the output with the highest score wins.'
        : 'Each output is a yes/no decision: yes when its score is at least '
            '${spec.threshold}.';
    return '''
You are compiling a short English rule into a tiny logistic model that will run on a phone with no further help from you.

For each output, score = sigmoid(bias + sum(weight * input)). Inputs you do not use count as zero. $kind

Allowed inputs (use only these names):
- pose_confidence, implement_confidence, phase_confidence.PHASE: 0..1 tracking or detection confidence.
- phase_seconds.PHASE: phase length in seconds.
- metric.KEY: the measured value; metric_confidence.KEY: 0..1.
- delta.KEY: signed distance from the coach in spreads; abs_delta.KEY: its magnitude; contribution.KEY: 0..1 share of the score lost to that metric.
Full list: ${inputNames.join(', ')}

Event: ${pack.packId} / ${pack.eventId}. Outputs: ${spec.outputs.join(', ')}.

Rule:
${spec.spec}

The model must reproduce every one of these examples (inputs not listed are zero):
${const JsonEncoder.withIndent('  ').convert(spec.examples)}
${feedback.isEmpty ? '' : '\nYour previous attempt got these wrong; fix them:\n${feedback.map((f) => '- $f').join('\n')}\n'}
Use as few inputs as the rule needs. Return the weights.''';
  }

  @override
  Future<Map<String, AdapterOutput>> propose(
      AdapterSpec spec, AnalysisPack pack, List<String> inputNames,
      {List<String> feedback = const []}) async {
    final body = jsonEncode({
      'model': model,
      'max_tokens': 16000,
      'fallbacks': 'default',
      'output_config': {
        'effort': 'high',
        'format': {'type': 'json_schema', 'schema': schema(spec, inputNames)},
      },
      'messages': [
        {'role': 'user', 'content': prompt(spec, pack, inputNames, feedback)},
      ],
    });
    final (status, text) = await _post(
        _url,
        {
          'content-type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2026-10-21',
          'anthropic-beta': 'server-side-fallback-2026-07-01',
        },
        body);
    if (status != 200) {
      throw AnalysisError(ErrorCode.adapterCompileFailed,
          'The compiler service returned an error ($status).', {'body': text});
    }
    final res = jsonDecode(text) as Map<String, Object?>;
    if (res['stop_reason'] == 'refusal') {
      throw AnalysisError(ErrorCode.adapterCompileFailed,
          'The compiler declined this spec.', {'stop_details': res['stop_details']});
    }
    if (res['stop_reason'] == 'max_tokens') {
      throw AnalysisError(ErrorCode.adapterCompileFailed,
          'The compiler ran out of room before finishing.');
    }
    final textBlock = (res['content'] as List)
        .cast<Map<String, Object?>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
    return parseOutputs(jsonDecode(textBlock) as Map<String, Object?>);
  }

  /// Parses the structured `{"outputs": [...]}` answer shared by every
  /// Claude transport.
  static Map<String, AdapterOutput> parseOutputs(Map<String, Object?> json) => {
        for (final o in (json['outputs'] as List).cast<Map<String, Object?>>())
          o['name'] as String: AdapterOutput(
            bias: (o['bias'] as num).toDouble(),
            weights: {
              for (final w in (o['weights'] as List).cast<Map<String, Object?>>())
                w['input'] as String: (w['weight'] as num).toDouble(),
            },
          ),
      };
}

/// Runs [executable] with [args], writing [stdin]; returns (exit code, stdout, stderr).
typedef ProcessRunner = Future<(int, String, String)> Function(
    String executable, List<String> args, String stdin, Duration timeout);

Future<(int, String, String)> _runProcess(
    String executable, List<String> args, String stdin, Duration timeout) async {
  // Run outside any project so no repository instructions reach the compiler.
  final process = await Process.start(executable, args,
      workingDirectory: Directory.systemTemp.path);
  process.stdin.write(stdin);
  await process.stdin.close();
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode.timeout(timeout, onTimeout: () {
    process.kill();
    throw TimeoutException('Compiler timed out', timeout);
  });
  return (code, await out, await err);
}

/// Compiles adapter specs with Claude through a signed-in Claude Code CLI
/// (`claude -p`), for workbench computers with a Claude subscription but no
/// API key. Same prompt, schema and validation as [ClaudeAdapterCompiler];
/// tools are disabled, so the call is a single structured answer.
/// Inference never calls it: compiled adapters run locally.
class ClaudeCodeAdapterCompiler implements AdapterCompiler {
  ClaudeCodeAdapterCompiler({
    this.executable = 'claude',
    this.model = 'claude-opus-5-5',
    this.timeout = const Duration(minutes: 5),
    ProcessRunner? run,
  }) : _run = run ?? _runProcess;

  /// Returns a compiler when `claude` is installed; null otherwise. Sign-in is
  /// checked on the first compile, which reports a clear error if missing.
  static Future<ClaudeCodeAdapterCompiler?> detect({ProcessRunner? run}) async {
    final runner = run ?? _runProcess;
    try {
      final (code, out, _) = await runner(
          'claude', const ['--version'], '', const Duration(seconds: 10));
      return code == 0 && out.contains('Claude Code')
          ? ClaudeCodeAdapterCompiler(run: run)
          : null;
    } catch (_) {
      return null;
    }
  }

  final String executable;
  final String model;
  final Duration timeout;
  final ProcessRunner _run;

  @override
  String get id => 'claude-code:$model';

  @override
  Future<Map<String, AdapterOutput>> propose(
      AdapterSpec spec, AnalysisPack pack, List<String> inputNames,
      {List<String> feedback = const []}) async {
    final args = [
      '-p',
      '--output-format', 'json',
      '--json-schema', jsonEncode(ClaudeAdapterCompiler.schema(spec, inputNames)),
      '--model', model,
      '--tools', '',
      '--no-session-persistence',
      '--strict-mcp-config',
    ];
    final (int, String, String) ran;
    try {
      ran = await _run(executable, args,
          ClaudeAdapterCompiler.prompt(spec, pack, inputNames, feedback), timeout);
    } on TimeoutException {
      throw AnalysisError(ErrorCode.adapterCompileFailed,
          'The compiler did not answer in time.');
    } on ProcessException catch (e) {
      throw AnalysisError(ErrorCode.adapterCompileFailed,
          'Claude Code could not be started.', {'error': e.message});
    }
    final (code, out, err) = ran;
    Map<String, Object?> res;
    try {
      res = jsonDecode(out) as Map<String, Object?>;
    } on FormatException {
      throw AnalysisError(ErrorCode.adapterCompileFailed,
          'Claude Code returned an unreadable answer (exit $code).',
          {'stderr': err});
    }
    final structured = res['structured_output'];
    if (code != 0 || res['is_error'] == true || structured is! Map) {
      throw AnalysisError(ErrorCode.adapterCompileFailed,
          'Claude Code could not compile this spec. Check that it is signed in.',
          {'subtype': res['subtype'], 'result': res['result']});
    }
    return ClaudeAdapterCompiler.parseOutputs(structured.cast<String, Object?>());
  }
}
