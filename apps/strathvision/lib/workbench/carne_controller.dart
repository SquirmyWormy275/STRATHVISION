import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../profiles/clip_probe.dart';
import '../profiles/profile_package.dart';
import '../workspace/project.dart' show Mark;

typedef StrokeAnalyzer = Future<List<StrokeDetail>> Function(ClipSource clip);

StrokeAnalyzer isolateStrokeAnalyzer(AnalysisPack pack) =>
    (clip) => Isolate.run(() => AnalysisEngine(pack: pack).analyzeStrokes(clip));

typedef MarksLookup = Future<List<Mark>> Function(String path);

/// Stores the next package version (with `carne_asada/`) and lists it.
typedef ResearchWriter = Future<String> Function(Profile profile,
    Map<String, String> patches, Map<String, String> adapters, Map<String, String> research);

/// One line in the status feed.
class FeedLine {
  const FeedLine(this.text, {this.useAnywayClip});
  final String text;

  /// Set on "below the usable threshold" lines: the clip "use anyway" adds.
  final String? useAnywayClip;
}

const _video = {'.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm'};
const _audio = {'.m4a', '.mp3', '.wav', '.aac', '.ogg', '.flac'};

/// The CARNE ASADA playground: one drop zone feeding a constrained mixture
/// editor. Desktop only; nothing here is needed for inference.
class CarneController extends ChangeNotifier {
  CarneController({
    required this.pack,
    required this.attributes,
    required this.bundle,
    required this.probe,
    required this.analyze,
    required this.marks,
    required this.write,
    this.phaseLabel,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    session = CarneSession(
      pack: pack,
      profile: bundle.profile,
      priority: _defaultPriority(),
      clock: _clock,
      phaseLabel: phaseLabel,
    );
    feed.add(FeedLine(CarneCopy.priority(session.priority)));
  }

  final AnalysisPack pack;

  /// The pack's mark attributes, in order.
  final List<String> attributes;
  final ProfileBundle bundle;
  final ClipProber probe;
  final StrokeAnalyzer analyze;
  final MarksLookup marks;
  final ResearchWriter write;
  final String Function(String phase)? phaseLabel;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  late final CarneSession session;

  /// Newest last.
  final List<FeedLine> feed = [];
  final String sessionId = _uuid.v4();
  bool busy = false;
  String? savedPath;
  String? _lastClip;
  bool _disposed = false;

  String _defaultPriority() =>
      attributes.firstWhere((a) => pack.attributeMetrics.containsKey(a),
          orElse: () => attributes.isEmpty ? 'Priority' : attributes.first);

  List<String> get priorities =>
      [for (final a in attributes) if (pack.attributeMetrics.containsKey(a)) a];

  bool get canChangeSettings => session.edits.isEmpty;

  void setPriority(String attr) {
    if (!canChangeSettings || attr == session.priority) return;
    session.priority = attr;
    feed.add(FeedLine(CarneCopy.priority(attr)));
    _notify();
  }

  void setChaos(bool on) {
    if (!canChangeSettings) return;
    session.chaos = on;
    feed.add(FeedLine(on
        ? 'Chaos is on for this session: the coach hull is loosened by one spread. It resets next session.'
        : 'Chaos is off. Edits stay inside the coach hull.'));
    _notify();
  }

  /// Everything dropped or chosen, routed by kind.
  Future<void> drop(List<String> paths) async {
    busy = true;
    _notify();
    try {
      for (final path in paths) {
        await _ingest(path);
        _notify();
      }
      _tryUpdate();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _ingest(String path) async {
    final ext = p.extension(path).toLowerCase();
    final name = p.basenameWithoutExtension(path);
    if (_video.contains(ext)) {
      final info = await probe(path);
      if (info == null) {
        feed.add(FeedLine('Can’t open $name as video.'));
        return;
      }
      final strokes = await analyze(ClipSource(
          clipId: _uuid.v4(), path: path, durationMs: info.durationMs, fps: info.fps));
      final clipMarks = await marks(path);
      final lines = session.addClip(name, strokes, marksFor: (s) => [
            for (final m in clipMarks)
              if (m.timeMs / 1000 >= s.startFrame / s.fps &&
                  m.timeMs / 1000 <= (s.endFrame + 1) / s.fps)
                StrokeMark(
                    attribute: m.attribute,
                    label: m.label.name,
                    author: m.author.name,
                    createdAt: m.createdAt),
          ]);
      for (final l in lines) {
        feed.add(FeedLine(l, useAnywayClip: l == CarneCopy.belowThreshold ? name : null));
      }
      _lastClip = name;
    } else if (ext == '.txt' || ext == '.md') {
      await _note(await _readText(path));
    } else if (_audio.contains(ext)) {
      // No local transcriber yet (DECISIONS.md edge case: keep audio, drop
      // the language binding).
      feed.add(const FeedLine(
          'Saved the voice note. Spoken labels need a transcriber on this computer.'));
    } else if (ext == '.zip' || ext == '.json') {
      try {
        final other = await readProfileBundle(path);
        feed.add(FeedLine(other.profile.packId == pack.packId &&
                other.profile.eventId == pack.eventId
            ? 'Package ${other.profile.coachName} · v${other.profile.version} noted. '
                'Its coach strokes are not merged in this session.'
            : 'That package is for another event. Ignoring it.'));
      } on AnalysisError catch (e) {
        feed.add(FeedLine(e.message));
      }
    } else {
      feed.add(FeedLine('Can’t use $name${ext.isEmpty ? '' : ext}.'));
    }
  }

  /// Text notes: `priority: ATTRIBUTE` and `ignore this clip`.
  Future<void> _note(String text) async {
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim().toLowerCase();
      if (line.startsWith('priority:')) {
        final want = line.substring('priority:'.length).trim();
        final attr = priorities.where((a) => a.toLowerCase() == want).firstOrNull;
        if (attr != null) setPriority(attr);
      } else if (line == 'ignore this clip' && _lastClip != null) {
        session.ignore(_lastClip!);
        feed.add(FeedLine('Ignoring $_lastClip.'));
      }
    }
  }

  /// Reads a text note (injectable for tests).
  Future<String> Function(String path) readText = _defaultRead;
  Future<String> _readText(String path) => readText(path);

  void useAnyway(String clip) {
    session.useAnyway(clip);
    feed.add(FeedLine('Added $clip to the pile anyway.'));
    _tryUpdate();
    _notify();
  }

  /// Runs loop steps until nothing more is accepted (or the limit).
  void _tryUpdate() {
    if (!session.baselineMet) return;
    for (var i = 0; i < session.limit && !session.limitReached; i++) {
      final r = session.step();
      switch (r) {
        case StepAccepted(:final edit):
          feed.add(FeedLine(edit.status));
          feed.add(FeedLine(CarneCopy.tally(session.edits.length)));
        case StepRejected(:final message):
          feed.add(FeedLine(message));
          return;
        case StepIdle():
          return;
      }
    }
  }

  /// "Look for an update" button.
  void tryUpdate() {
    _tryUpdate();
    _notify();
  }

  void undo() {
    final e = session.undo();
    if (e == null) return;
    feed.add(FeedLine('Undid: ${e.explanation}'));
    feed.add(FeedLine(CarneCopy.tally(session.edits.length)));
    _notify();
  }

  /// Writes the next package version: the edited mixture in profile.json
  /// and the session record in `carne_asada/mixture_edits_vN.json`.
  Future<void> save() async {
    if (session.edits.isEmpty) return;
    final p0 = bundle.profile;
    final version = p0.version + 1;
    final next = Profile(
      profileId: p0.profileId,
      version: version,
      coachName: p0.coachName,
      packId: p0.packId,
      eventId: p0.eventId,
      metricSchemaVersion: p0.metricSchemaVersion,
      createdAt: _clock().toUtc(),
      sourceClipCount: p0.sourceClipCount,
      minClipsMet: p0.minClipsMet,
      selfConsistencyPassed: p0.selfConsistencyPassed,
      notes: '${p0.notes} CARNE ASADA: ${session.edits.length} edits on ${session.priority}.'.trim(),
      metrics: Map.of(session.mixture),
      referenceClips: p0.referenceClips,
    );
    savedPath = await write(next, bundle.patchFiles, bundle.adapterFiles, {
      'mixture_edits_v$version.json': const JsonEncoder.withIndent('  ')
          .convert(session.editsLog(version: version, sessionId: sessionId)),
    });
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

Future<String> _defaultRead(String path) => File(path).readAsString();
