import 'dart:async';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../analysis/analysis_controller.dart';
import '../packs/placeholder_pack.dart';
import '../workspace/project.dart';
import '../workspace/stage_player.dart';
import '../workspace/workspace_controller.dart';
import 'analysis_panel.dart';
import 'workspace_widgets.dart';

typedef ClipPathPicker = Future<String?> Function();
Future<String?> pickClipFile() async => (await FilePicker.pickFile(
  dialogTitle: 'Choose a clip', type: FileType.video))?.path;

/// Review is complete with one clip. Players belong to WorkspaceRoute, not layout.
class WorkspaceScreen extends StatefulWidget {
  WorkspaceScreen({super.key, required this.controller, this.pickClip = pickClipFile,
    PackInfo? pack, this.analysis, this.eventConfirmed = true,
    this.onChooseEvent, this.onClose, this.notice}) : pack = pack ?? placeholderPack;
  final WorkspaceController controller;
  final AnalysisController? analysis;
  final ClipPathPicker pickClip;
  final PackInfo pack;
  final bool eventConfirmed;
  final Future<void> Function()? onChooseEvent, onClose;
  final String? notice;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  WorkspaceController get c => widget.controller;
  AnalysisController? get a => widget.analysis;
  final _focus = FocusNode(debugLabel: 'review');
  bool _modal = false, _busy = false;
  String? _error;
  (Stage, Duration)? _pendingScrub;
  Future<void>? _seeking;
  @override
  void dispose() { _focus.dispose(); super.dispose(); }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try { await _seeking; await action(); }
    catch (_) { if (mounted) setState(() => _error = 'That action could not finish. Your original videos are unchanged. Retry or use Undo.'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  void _scrub(Stage stage, Duration position) {
    _pendingScrub = (stage, position);
    _seeking ??= _drainScrubs();
  }
  Future<void> _drainScrubs() async {
    try {
      await c.pause();
      while (_pendingScrub != null && mounted) {
        final next = _pendingScrub!; _pendingScrub = null;
        await c.scrub(next.$1, next.$2);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not seek to that frame. Try the frame-step controls.');
    } finally { _seeking = null; }
  }

  Future<void> _load(Stage stage) => _run(() async {
    _modal = true;
    try {
      final path = await widget.pickClip();
      if (path != null && mounted) await c.loadClip(stage, path);
    } finally { _modal = false; }
  });

  Future<void> _mark(MarkLabel label) => _run(() async {
    if (!widget.eventConfirmed) { await widget.onChooseEvent?.call(); return; }
    await c.pause();
    if (!await c.settleFrames()) throw StateError('Wait for the displayed frame.');
    await c.mark(label);
  });

  Future<void> _annotate() => _run(() async {
    await c.pause();
    if (!await c.settleFrames() || !mounted) return;
    _modal = true;
    try {
      final text = await showDialog<String>(context: context, builder: (_) => const AnnotationDialog());
      if (text != null && mounted) await c.annotate(text);
    } finally { _modal = false; }
    if (mounted) _focus.requestFocus();
  });

  bool get _shortcutsAllowed {
    if (_modal || _busy || ModalRoute.of(context)?.isCurrent != true) return false;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext?.findAncestorWidgetOfExactType<EditableText>() != null ||
        focusContext?.widget is EditableText) return false;
    return true;
  }
  void _shortcut(Future<void> Function() action) {
    if (_shortcutsAllowed) unawaited(_run(action));
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    const SingleActivator(LogicalKeyboardKey.space): () => _shortcut(c.togglePlay),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () => _shortcut(() => c.stepFrame(forward: true)),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _shortcut(() => c.stepFrame(forward: false)),
    const SingleActivator(LogicalKeyboardKey.keyS): () => _shortcut(c.setSyncPoint),
    const SingleActivator(LogicalKeyboardKey.keyL): () => _shortcut(() => c.setLocked(!c.locked)),
    const SingleActivator(LogicalKeyboardKey.keyM): () => _shortcut(c.toggleMirrorB),
    const SingleActivator(LogicalKeyboardKey.keyG): () { if (_shortcutsAllowed) unawaited(_mark(MarkLabel.green)); },
    const SingleActivator(LogicalKeyboardKey.keyR): () { if (_shortcutsAllowed) unawaited(_mark(MarkLabel.red)); },
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => _shortcut(c.undo),
    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () => _shortcut(c.undo),
    if (a != null) const SingleActivator(LogicalKeyboardKey.keyA): () => _shortcut(a!.analyze),
  };

  @override
  Widget build(BuildContext context) => CallbackShortcuts(bindings: _shortcuts,
    child: Focus(focusNode: _focus, autofocus: true,
      child: ListenableBuilder(listenable: Listenable.merge([c, ?a]), builder: (context, _) => Scaffold(
        body: SafeArea(child: LayoutBuilder(builder: (context, bounds) {
          final scroll = bounds.maxHeight < 560 || MediaQuery.textScalerOf(context).scale(16) > 24;
          final hasClip = c.clipOn(Stage.a) != null || c.clipOn(Stage.b) != null;
          final header = Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                BackButton(onPressed: () { if (widget.onClose != null) { unawaited(widget.onClose!()); } else { Navigator.maybePop(context); } }),
                Expanded(child: Text(c.project.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge)),
                TextButton.icon(key: const Key('undo'), onPressed: c.canUndo && !_busy ? () => _run(c.undo) : null,
                  icon: const Icon(Icons.undo), label: const Text('Undo')),
              ]),
              if (hasClip) Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SyncStatusPill(controller: c),
                if (widget.onChooseEvent != null) TextButton(key: const Key('review-event'),
                  onPressed: _busy ? null : () => _run(widget.onChooseEvent!),
                  child: Text(widget.eventConfirmed ? widget.pack.event.label : 'Choose event')),
                if (!c.hasBothClips) OutlinedButton.icon(key: Key('load-${c.clipOn(Stage.a) == null ? 'A' : 'B'}'),
                  onPressed: _busy ? null : () => _load(c.clipOn(Stage.a) == null ? Stage.a : Stage.b),
                  icon: const Icon(Icons.compare), label: const Text('Compare')),
                if (c.hasBothClips) TextButton.icon(key: const Key('single-view'),
                  onPressed: _busy ? null : () => _run(() => c.clearStage(Stage.b)),
                  icon: const Icon(Icons.crop_square), label: const Text('Single view')),
                if (a != null && c.clipOn(c.activeStage) != null)
                  OutlinedButton.icon(key: const Key('analyze'), onPressed: _busy || a!.running ? null : () => _run(() async {
                    if (a!.result != null) { a!.openPanel(); } else { await a!.analyze(); }
                  }), icon: const Icon(Icons.insights), label: Text(a!.running ? 'Analyzing…' : a!.result == null ? 'Analyze' : 'Details')),
              ]),
              if (_error != null || widget.notice != null) Padding(padding: const EdgeInsets.all(8),
                child: Semantics(liveRegion: true, child: Text(_error ?? widget.notice!))),
            ]));
          final controls = Column(mainAxisSize: MainAxisSize.min, children: [
            TransportBar(controller: c, onAnnotate: _annotate, run: _run, enabled: !_busy),
            if (hasClip && widget.eventConfirmed) MarkBar(controller: c, pack: widget.pack,
              onMark: _mark, enabled: !_busy),
          ]);
          if (scroll) return SingleChildScrollView(child: Column(children: [header,
            SizedBox(height: math.max(260.0, bounds.maxHeight * 0.55), child: _body()), controls]));
          return Column(children: [header, Expanded(child: _body()), controls]);
        })),
      )),
    ));

  Widget _body() => LayoutBuilder(builder: (context, bounds) {
    final analysis = a;
    final side = bounds.maxWidth >= 1180 && bounds.maxHeight >= 300;
    return Row(children: [
      Expanded(child: Stack(children: [
        Positioned.fill(child: ExcludeSemantics(excluding: analysis?.panelOpen == true && !side, child: _stages())),
        if (analysis?.panelOpen == true && !side) Positioned.fill(child: AnalysisPanel(analysis: analysis!, pack: widget.pack)),
      ])),
      if (analysis?.panelOpen == true && side) Padding(padding: const EdgeInsets.only(right: 16, bottom: 8),
        child: SizedBox(width: 340, child: AnalysisPanel(analysis: analysis!, pack: widget.pack))),
    ]);
  });

  Widget _stages() => LayoutBuilder(builder: (context, bounds) {
    final stages = c.hasBothClips ? Stage.values : [c.clipOn(Stage.b) != null ? Stage.b : Stage.a];
    double ratio(Stage s) { final player = c.player(s); return player is MediaKitStagePlayer ? player.aspectRatio ?? 16 / 9 : 16 / 9; }
    final average = stages.map(ratio).reduce((a, b) => a + b) / stages.length;
    final horizontal = stages.length < 2 || bounds.maxWidth / math.max(1, bounds.maxHeight) > average;
    return Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      children: [for (var i = 0; i < stages.length; i++) ...[
        if (i != 0) const SizedBox(width: 12, height: 12),
        Expanded(child: StagePanel(key: Key('stage-${stages[i].name.toUpperCase()}'),
          controller: c, stage: stages[i], onLoad: () => _load(stages[i]),
          onScrub: (position) => _scrub(stages[i], position))),
      ]],
    ));
  });
}
