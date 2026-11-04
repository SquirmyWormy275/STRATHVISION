import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../packs/placeholder_pack.dart';
import '../workspace/project.dart';
import '../workspace/workspace_controller.dart';
import 'workspace_widgets.dart';

typedef ClipPathPicker = Future<String?> Function();

Future<String?> pickClipFile() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Choose a clip',
    type: FileType.video,
  );
  return file?.path;
}

/// Dual-video workspace. Video takes most of the screen; the stepper sits
/// under the video and the mark controls bottom-right (UI_UX_PRINCIPLES.md).
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.controller,
    this.pickClip = pickClipFile,
    this.pack = placeholderPack,
  });

  final WorkspaceController controller;
  final ClipPathPicker pickClip;
  final PackInfo pack;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  WorkspaceController get c => widget.controller;
  final _focus = FocusNode(debugLabel: 'workspace');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load(Stage stage) async {
    final path = await widget.pickClip();
    if (path != null) await c.loadClip(stage, path);
  }

  Future<void> _annotate() async {
    final wasPlaying = c.playing;
    if (wasPlaying) await c.pause();
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const AnnotationDialog(),
    );
    if (text != null) await c.annotate(text);
    _focus.requestFocus();
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
        const SingleActivator(LogicalKeyboardKey.space): c.togglePlay,
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            c.stepFrame(forward: true),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            c.stepFrame(forward: false),
        const SingleActivator(LogicalKeyboardKey.keyS): () {
          if (c.hasBothClips) c.setSyncPoint();
        },
        const SingleActivator(LogicalKeyboardKey.keyL): () =>
            c.setLocked(!c.locked),
        const SingleActivator(LogicalKeyboardKey.keyM): c.toggleMirrorB,
        const SingleActivator(LogicalKeyboardKey.keyG): () =>
            c.mark(MarkLabel.green),
        const SingleActivator(LogicalKeyboardKey.keyR): () =>
            c.mark(MarkLabel.red),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): c.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): c.undo,
      };

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  WorkspaceTopBar(controller: c),
                  Expanded(child: _stages()),
                  TransportBar(
                    controller: c,
                    onAnnotate: _annotate,
                  ),
                  if (c.clipOn(c.activeStage) != null)
                    MarkBar(controller: c, pack: widget.pack),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stages() {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= constraints.maxHeight * 1.1;
      final children = [
        for (final s in Stage.values)
          Expanded(
            child: StagePanel(
              key: Key('stage-${s.name.toUpperCase()}'),
              controller: c,
              stage: s,
              onLoad: () => _load(s),
            ),
          ),
      ];
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: wide
            ? Row(children: [children[0], const SizedBox(width: 8), children[1]])
            : Column(
                children: [children[0], const SizedBox(height: 8), children[1]]),
      );
    });
  }
}
