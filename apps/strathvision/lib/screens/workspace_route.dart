import 'dart:async';

import 'package:analysis_engine/analysis_engine.dart' show PackDefinition;
import 'package:flutter/material.dart';

import '../analysis/analysis_controller.dart';
import '../data/database.dart';
import '../media/thumbnail_service.dart';
import '../packs/placeholder_pack.dart';
import '../vision/athlete.dart';
import '../vision/athlete_choices.dart';
import '../workspace/project.dart';
import '../workspace/review_presentation.dart';
import '../workspace/stage_player.dart';
import '../workspace/workspace_controller.dart';
import 'workspace_screen.dart';

Future<List<ProfileChoice>> compatibleProfiles(
  AppDatabase db,
  PackInfo pack,
) async => [
  for (final row in await db.allProfiles())
    if (row.packId == pack.packId &&
        row.eventId == pack.eventId &&
        row.minClipsMet &&
        row.selfConsistencyPassed &&
        row.metricSchemaVersion == pack.analysisPack.metricSchemaVersion)
      ProfileChoice(
        profileId: row.profileId,
        version: row.version,
        label: '${row.coachName} · v${row.version}',
        path: row.sourcePath,
      ),
];
typedef StagePlayerFactory = StagePlayer Function();
StagePlayer defaultStagePlayer() => MediaKitStagePlayer();

/// Owns players for the route, not the layout. Saved event context is authoritative.
class WorkspaceRoute extends StatefulWidget {
  const WorkspaceRoute({
    super.key,
    required this.db,
    required this.project,
    required this.pack,
    this.playerFactory = defaultStagePlayer,
    this.pickClip = pickClipFile,
    this.analysisRunner,
    this.availablePacks = const [],
    this.initialClipPath,
    this.initialEventConfirmed = false,
    this.sourceSignature = presentationSignature,
  });
  final AppDatabase db;
  final Project project;
  final PackInfo pack;
  final StagePlayerFactory playerFactory;
  final ClipPathPicker pickClip;
  final AnalysisRunner? analysisRunner;
  final List<PackDefinition> availablePacks;
  final String? initialClipPath;
  final bool initialEventConfirmed;
  final Future<String?> Function(String path) sourceSignature;
  @override
  State<WorkspaceRoute> createState() => _WorkspaceRouteState();
}

class _WorkspaceRouteState extends State<WorkspaceRoute>
    with WidgetsBindingObserver {
  late final _a = widget.playerFactory(), _b = widget.playerFactory();
  late final _store = ReviewStateStore(widget.db);
  late final Future<void> _initializing;
  WorkspaceController? _controller;
  AnalysisController? _analysis;
  AthleteChoices? _athletes;
  ReviewLease? _lease;
  ReviewPresentation _saved = const ReviewPresentation();
  PackInfo? _event;
  final _viewedAt = DateTime.now();
  final _loadedSignatures = <String, String>{};
  Timer? _timer, _debounce;
  Future<void>? _saving;
  bool _ready = false,
      _closed = false,
      _leaving = false,
      _canPop = false,
      _blocked = false;
  String? _notice, _saveError;

  List<PackInfo> get _events => {
    placeholderPack.key: placeholderPack,
    for (final e in PackInfo.all([
      ...widget.availablePacks,
      widget.pack.definition,
    ]))
      e.key: e,
  }.values.toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializing = _initialize();
  }

  Future<void> _initialize() async {
    if (widget.initialClipPath == null) {
      try {
        _lease = await _store.claim(widget.project.projectId);
        _saved = _lease!.initial;
      } catch (_) {
        _blocked = true;
        _notice = 'Saved context cannot be read. It has not been overwritten. Video review is still available.';
      }
    }
    if (_closed) return;
    if (_saved.eventKey != null) {
      final match = _events.where((e) => e.key == _saved.eventKey).firstOrNull;
      if (match != null &&
          match.analysisPack.metricSchemaVersion == _saved.schema) {
        _event = match;
      } else {
        _notice = 'The saved event version is unavailable. Choose an event before new marks or measurements.';
      }
    } else if (widget.initialClipPath != null && widget.initialEventConfirmed) {
      _event = widget.pack;
    }
    final c = _controller = WorkspaceController(
      project: widget.project,
      store: widget.db,
      playerA: _a,
      playerB: _b,
      attributes: _event?.topAttributes ?? const [],
      packId: _event?.packId,
      eventId: _event?.eventId,
    );
    _athletes = AthleteChoices(
      targetFor: (id) {
        final j = c.athleteFor(id);
        return j == null ? null : AthleteTarget.fromJson(j);
      },
    );
    try {
      if (widget.initialClipPath != null) {
        await c.loadClip(Stage.a, widget.initialClipPath!);
      } else {
        await c.restore();
      }
    } catch (_) {
      _notice = 'A source could not be opened. Replace the unavailable clip to continue; saved marks are unchanged.';
      for (final stage in Stage.values) {
        final clip = c.clipOn(stage), player = c.player(stage);
        if (clip == null || player.hasMedia) continue;
        try {
          await player.open(clip.path);
          await player.setRate(c.rate);
        } catch (_) {
          /* retain recovery state */
        }
      }
    }
    if (_closed) return;
    final positions = <Stage, int>{};
    for (final stage in Stage.values) {
      final clip = c.clipOn(stage);
      if (clip == null || !c.player(stage).hasMedia) continue;
      String? signature;
      try {
        signature = await widget.sourceSignature(clip.path);
      } catch (_) {
        /* unknown source */
      }
      if (signature == null) continue;
      _loadedSignatures[clip.clipId] = signature;
      if (signature == _saved.signatures[clip.clipId] &&
          _saved.positions.containsKey(clip.clipId)) {
        positions[stage] = _saved.positions[clip.clipId]!;
      } else if (_saved.positions.containsKey(clip.clipId)) {
        _notice = 'A source changed. Its previous position was not restored. Check the footage and sync.';
      }
    }
    if (_closed) return;
    final active = _saved.activeStage == 'b' && c.clipOn(Stage.b) != null
        ? Stage.b
        : c.clipOn(Stage.a) != null
        ? Stage.a
        : Stage.b;
    try {
      if (c.locked) {
        if (positions.length == 2) {
          await c.scrub(active, Duration(milliseconds: positions[active]!));
        }
      } else {
        for (final entry in positions.entries) {
          await c.scrub(entry.key, Duration(milliseconds: entry.value));
        }
      }
      c.setActiveStage(active);
      final allowed = [...?_event?.topAttributes, ...?_event?.moreAttributes];
      if (_saved.attribute != null && allowed.contains(_saved.attribute)) {
        c.selectAttribute(_saved.attribute!);
      }
      await c.settleFrames();
    } catch (_) {
      _notice = 'Could not restore the last frame. Choose a new position with the playback controls.';
    }
    if (_closed) return;
    _makeAnalysis();
    c.addListener(_changed);
    _ready = true;
    setState(() {});
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_controller?.playing == true) _saveQuietly();
    });
    _saveQuietly();
  }

  void _makeAnalysis() {
    _analysis?.removeListener(_changed);
    _analysis?.dispose();
    final event = _event;
    if (event == null) {
      _analysis = null;
      return;
    }
    _analysis = AnalysisController(
      workspace: _controller!,
      pack: event.analysisPack,
      run:
          widget.analysisRunner ??
          visionRunner(event.analysisPack, athletes: _athletes),
      athletes: widget.analysisRunner == null ? _athletes : null,
      listProfiles: () => compatibleProfiles(widget.db, event),
      preferredProfileKey: _saved.profileKey,
      restoreProfileSelection: _saved.profileChosen,
      metricLabel: event.metricLabel,
      phaseLabel: (id) => event.phaseLabel(id).toLowerCase(),
      saveResult: (r) => widget.db.saveComparison(
        projectId: widget.project.projectId,
        result: r,
      ),
    )..addListener(_changed);
  }

  void _changed() {
    if (!_ready || _closed || _leaving) return;
    _debounce?.cancel();
    if (_controller?.playing != true) {
      _debounce = Timer(const Duration(milliseconds: 500), _saveQuietly);
    }
  }

  void _saveQuietly() {
    if (_closed || _blocked) return;
    unawaited(
      _checkpoint().catchError((Object _) {
        if (mounted && !_closed) {
          setState(
            () => _saveError =
                'Could not save the review position. Retry before closing.',
          );
        }
      }),
    );
  }

  Future<void> _checkpoint() async {
    if (_saving != null) {
      await _saving;
      return;
    }
    final work = _save();
    _saving = work;
    try {
      await work;
    } finally {
      _saving = null;
    }
  }

  Future<void> _save() async {
    final c = _controller;
    if (c == null || c.project.clips.isEmpty || _blocked) return;
    if (!await c.settleFrames()) throw StateError('Frame is still seeking.');
    _lease ??= await _store.claim(widget.project.projectId);
    final positions = Map<String, int>.of(_saved.positions),
        signatures = Map<String, String>.of(_saved.signatures);
    for (final stage in Stage.values) {
      final clip = c.clipOn(stage);
      if (clip == null || !c.player(stage).hasMedia) continue;
      final signature = await widget.sourceSignature(clip.path);
      if (signature == null) continue;
      final loaded = _loadedSignatures.putIfAbsent(
        clip.clipId,
        () => signature,
      );
      if (signature != loaded) {
        positions.remove(clip.clipId);
        signatures.remove(clip.clipId);
        continue;
      }
      signatures[clip.clipId] = signature;
      positions[clip.clipId] = c
          .displayedPosition(stage)
          .inMilliseconds
          .clamp(0, 1 << 53)
          .toInt();
    }
    final next = ReviewPresentation(
      eventKey: _event?.key ?? _saved.eventKey,
      schema: _event?.analysisPack.metricSchemaVersion ?? _saved.schema,
      activeStage: c.activeStage.name,
      attribute: c.activeAttribute,
      profileKey: _analysis == null
          ? _saved.profileKey
          : _analysis!.requestedProfileKey,
      profileChosen:
          _analysis?.profileSelectionEstablished ?? _saved.profileChosen,
      positions: positions,
      signatures: signatures,
      viewedAt: _viewedAt,
    );
    if (!await _store.save(_lease!, next)) {
      _blocked = true;
      throw StateError('A newer session owns this review.');
    }
    _saved = next;
    if (_saveError != null && mounted && !_closed) {
      setState(() => _saveError = null);
    }
  }

  Future<void> _chooseEvent() async {
    final chosen = await showModalBottomSheet<PackInfo>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Review event',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final event in _events)
              ListTile(
                key: Key('review-event-${event.key}'),
                title: Text(event.label),
                selected: event.key == _event?.key,
                onTap: () => Navigator.pop(context, event),
              ),
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Applies to new marks and measurements. Existing feedback is unchanged.',
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted || _closed) return;
    await _saving;
    _event = chosen;
    _saved = ReviewPresentation(
      eventKey: chosen.key,
      schema: chosen.analysisPack.metricSchemaVersion,
      positions: _saved.positions,
      signatures: _saved.signatures,
      activeStage: _saved.activeStage,
    );
    _controller!.configureContext(
      packId: chosen.packId,
      eventId: chosen.eventId,
      attributes: chosen.topAttributes,
    );
    _makeAnalysis();
    setState(() {});
    _saveQuietly();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    _debounce?.cancel();
    var leave = true;
    try {
      await _initializing;
      await _saving;
      await _controller?.pause();
      await _controller?.flush();
      await _checkpoint();
      if (_saveError != null) throw StateError(_saveError!);
    } catch (_) {
      if (!mounted) return;
      leave =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Review not fully saved'),
              content: const Text(
                'Stay to retry, or leave without the latest saved changes. Original videos are unchanged.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Stay'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Leave anyway'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      _leaving = false;
    }
    if (!leave || !mounted) return;
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _saveQuietly();
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _debounce?.cancel();
    _controller?.removeListener(_changed);
    _analysis?.removeListener(_changed);
    unawaited(_disposePlayers());
    super.dispose();
  }

  Future<void> _disposePlayers() async {
    try {
      await _initializing;
      await _saving;
    } catch (_) {
      /* reported by the route */
    }
    _analysis?.dispose();
    _athletes?.dispose();
    try {
      await _controller?.pause();
    } catch (_) {
      /* native teardown */
    }
    _controller?.dispose();
    await _a.dispose();
    await _b.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_leave());
    },
    child: !_ready
        ? Scaffold(
            appBar: AppBar(title: const Text('Opening review')),
            body: const Center(child: Text('Opening footage…')),
          )
        : WorkspaceScreen(
            controller: _controller!,
            pack: _event ?? placeholderPack,
            analysis: _analysis,
            pickClip: widget.pickClip,
            eventConfirmed: _event != null,
            onChooseEvent: _chooseEvent,
            onClose: _leave,
            notice: _saveError ?? _notice,
          ),
  );
}
