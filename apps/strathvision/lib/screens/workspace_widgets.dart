import 'package:flutter/material.dart';

import '../packs/placeholder_pack.dart';
import '../workspace/project.dart' show Mark, MarkLabel;
import '../workspace/workspace_controller.dart';

const _markGreen = Color(0xFF2E9E5B);
const _markRed = Color(0xFFD64541);

String formatTime(Duration d) {
  final neg = d.isNegative;
  d = d.abs();
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  final cs = (d.inMilliseconds % 1000) ~/ 10;
  return '${neg ? '-' : ''}$m:${s.toString().padLeft(2, '0')}'
      '.${cs.toString().padLeft(2, '0')}';
}

String formatOffset(int ms) {
  final sign = ms < 0 ? '−' : '+';
  return '$sign${(ms.abs() / 1000).toStringAsFixed(2)} s';
}

// ---- top bar --------------------------------------------------------------

class WorkspaceTopBar extends StatelessWidget {
  const WorkspaceTopBar({super.key, required this.controller, this.action});

  final WorkspaceController controller;

  /// The screen's primary action (Analyze), when available.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const BackButton(),
          Expanded(
            child: Text(c.project.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium),
          ),
          SyncStatusPill(controller: c),
          const SizedBox(width: 8),
          if (action != null) ...[action!, const SizedBox(width: 4)],
          IconButton(
            key: const Key('undo'),
            tooltip: 'Undo (Ctrl+Z)',
            onPressed: c.canUndo ? c.undo : null,
            icon: const Icon(Icons.undo),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// Sync state is always visible (Dual-Video-Workspace.md).
class SyncStatusPill extends StatelessWidget {
  const SyncStatusPill({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    final sync = c.sync;
    final (String label, IconData icon, Color bg, Color fg) = switch (sync) {
      null when !c.hasBothClips => (
          'Single view',
          Icons.crop_square,
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant
        ),
      null => (
          'Not synced',
          Icons.link_off,
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant
        ),
      _ when c.locked => (
          'Locked · B ${formatOffset(sync.offsetMs)}',
          Icons.link,
          scheme.primaryContainer,
          scheme.onPrimaryContainer
        ),
      _ => (
          'Synced · B ${formatOffset(sync.offsetMs)}',
          Icons.link,
          scheme.secondaryContainer,
          scheme.onSecondaryContainer
        ),
    };
    return AnimatedContainer(
      key: const Key('sync-status'),
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

// ---- stage ----------------------------------------------------------------

class StagePanel extends StatelessWidget {
  const StagePanel({
    super.key,
    required this.controller,
    required this.stage,
    required this.onLoad,
  });

  final WorkspaceController controller;
  final Stage stage;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    final clip = c.clipOn(stage);
    final active = c.activeStage == stage && clip != null;
    final pl = c.player(stage);
    final label = stage == Stage.a ? 'A' : 'B';

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => c.setActiveStage(stage),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: clip == null ? scheme.surfaceContainerHighest : Colors.black,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active ? scheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: clip == null
                  ? _EmptyStage(label: label, onLoad: onLoad)
                  : Stack(fit: StackFit.expand, children: [
                      pl.view(mirror: stage == Stage.b && c.mirrorB),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _StageTag(
                          label: label,
                          name: clip.displayName,
                          mirrored: stage == Stage.b && c.mirrorB,
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: IconButton(
                          key: Key('replace-$label'),
                          tooltip: 'Replace clip on $label',
                          onPressed: onLoad,
                          color: Colors.white70,
                          icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                        ),
                      ),
                    ]),
            ),
          ),
        ),
        if (clip != null)
          Timeline(
            key: Key('timeline-$label'),
            position: pl.position,
            duration: pl.duration,
            marks: c.marksFor(stage),
            active: active,
            onScrub: (d) => c.scrub(stage, d),
          ),
      ],
    );
  }
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage({required this.label, required this.onLoad});

  final String label;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: theme.textTheme.displaySmall
                ?.copyWith(color: theme.colorScheme.outlineVariant)),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          key: Key('load-$label'),
          onPressed: onLoad,
          icon: const Icon(Icons.add),
          label: Text(label == 'A' ? 'Add a clip' : 'Add a clip to compare'),
        ),
      ]),
    );
  }
}

class _StageTag extends StatelessWidget {
  const _StageTag(
      {required this.label, required this.name, required this.mirrored});

  final String label;
  final String name;
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
          color: Colors.black54, borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70)),
          ),
          if (mirrored) ...[
            const SizedBox(width: 6),
            const Icon(Icons.flip, size: 14, color: Colors.white70),
          ],
        ]),
      ),
    );
  }
}

/// Scrub bar with red/green mark ticks painted on the track.
class Timeline extends StatelessWidget {
  const Timeline({
    super.key,
    required this.position,
    required this.duration,
    required this.marks,
    required this.active,
    required this.onScrub,
  });

  final Duration position;
  final Duration duration;
  final List<Mark> marks;
  final bool active;
  final ValueChanged<Duration> onScrub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = duration.inMilliseconds;
    final value =
        total <= 0 ? 0.0 : (position.inMilliseconds / total).clamp(0.0, 1.0);
    final timeStyle = TextStyle(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontSize: 12,
      color: active ? scheme.onSurface : scheme.onSurfaceVariant,
    );
    return SizedBox(
      height: 40,
      child: Row(children: [
        SizedBox(
            width: 64,
            child: Text(formatTime(position),
                textAlign: TextAlign.right, style: timeStyle)),
        Expanded(
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _MarkTicksPainter(
                    marks: marks, totalMs: total, inset: 24),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: value,
                onChanged: total <= 0
                    ? null
                    : (v) => onScrub(Duration(milliseconds: (v * total).round())),
              ),
            ),
          ]),
        ),
        SizedBox(
            width: 64,
            child: Text(formatTime(duration), style: timeStyle)),
      ]),
    );
  }
}

class _MarkTicksPainter extends CustomPainter {
  _MarkTicksPainter(
      {required this.marks, required this.totalMs, required this.inset});

  final List<Mark> marks;
  final int totalMs;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalMs <= 0) return;
    final width = size.width - inset * 2;
    final paint = Paint()..strokeWidth = 3..strokeCap = StrokeCap.round;
    for (final m in marks) {
      final x = inset + width * (m.timeMs / totalMs).clamp(0.0, 1.0);
      paint.color = m.label == MarkLabel.green ? _markGreen : _markRed;
      canvas.drawLine(Offset(x, size.height / 2 - 10),
          Offset(x, size.height / 2 - 4), paint);
    }
  }

  @override
  bool shouldRepaint(_MarkTicksPainter old) =>
      old.marks != marks || old.totalMs != totalMs;
}

// ---- transport ------------------------------------------------------------

const playbackRates = [0.1, 0.25, 0.5, 1.0];

class TransportBar extends StatelessWidget {
  const TransportBar(
      {super.key, required this.controller, required this.onAnnotate});

  final WorkspaceController controller;
  final VoidCallback onAnnotate;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final hasClip = c.clipOn(Stage.a) != null || c.clipOn(Stage.b) != null;
    if (!hasClip) return const SizedBox(height: 8);

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          IconButton(
            key: const Key('step-back'),
            tooltip: 'Previous frame (←)',
            onPressed: () => c.stepFrame(forward: false),
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          IconButton.filled(
            key: const Key('play'),
            tooltip: c.playing ? 'Pause (Space)' : 'Play (Space)',
            iconSize: 32,
            onPressed: c.togglePlay,
            icon: Icon(c.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          IconButton(
            key: const Key('step-forward'),
            tooltip: 'Next frame (→)',
            onPressed: () => c.stepFrame(forward: true),
            icon: const Icon(Icons.skip_next_rounded),
          ),
          const SizedBox(width: 8),
          SegmentedButton<double>(
            key: const Key('rate'),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (final r in playbackRates)
                ButtonSegment(
                    value: r,
                    label: Text(r == 1.0 ? '1×' : '$r×'.replaceFirst('0.', '.'))),
            ],
            selected: {
              playbackRates.contains(c.rate) ? c.rate : 1.0,
            },
            onSelectionChanged: (s) => c.setRate(s.first),
          ),
          if (c.hasBothClips) ...[
            const SizedBox(width: 8),
            if (c.sync == null)
              FilledButton.icon(
                key: const Key('set-sync'),
                onPressed: c.setSyncPoint,
                icon: const Icon(Icons.link),
                label: const Text('Sync here'),
              )
            else ...[
              FilterChip(
                key: const Key('lock'),
                selected: c.locked,
                onSelected: c.setLocked,
                avatar: Icon(c.locked ? Icons.lock : Icons.lock_open, size: 18),
                label: Text(c.locked ? 'Locked' : 'Independent'),
                showCheckmark: false,
              ),
              IconButton(
                key: const Key('resync'),
                tooltip: 'Set sync again here (S)',
                onPressed: c.setSyncPoint,
                icon: const Icon(Icons.my_location),
              ),
              IconButton(
                key: const Key('clear-sync'),
                tooltip: 'Clear sync',
                onPressed: c.clearSync,
                icon: const Icon(Icons.link_off),
              ),
            ],
            IconButton(
              key: const Key('mirror'),
              tooltip: 'Mirror B (M)',
              isSelected: c.mirrorB,
              selectedIcon: Icon(Icons.flip, color: scheme.primary),
              onPressed: c.toggleMirrorB,
              icon: const Icon(Icons.flip),
            ),
            IconButton(
              key: const Key('swap'),
              tooltip: 'Swap A and B',
              onPressed: c.swapStages,
              icon: const Icon(Icons.swap_vert_rounded),
            ),
          ],
          IconButton(
            key: const Key('annotate'),
            tooltip: 'Add a note at this moment',
            onPressed: c.clipOn(c.activeStage) == null ? null : onAnnotate,
            icon: const Icon(Icons.sticky_note_2_outlined),
          ),
        ],
      ),
    );
  }
}

// ---- marks ----------------------------------------------------------------

/// Attribute chips + red/green, bottom-right (spatial memory rule).
class MarkBar extends StatelessWidget {
  const MarkBar({super.key, required this.controller, required this.pack});

  final WorkspaceController controller;
  final PackInfo pack;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    final extra =
        pack.moreAttributes.where((a) => !c.attributes.contains(a)).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(children: [
              for (final a in c.attributes)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: Key('attr-$a'),
                    label: Text(a),
                    selected: c.activeAttribute == a,
                    showCheckmark: false,
                    selectedColor: scheme.primaryContainer,
                    onSelected: (_) => c.selectAttribute(a),
                  ),
                ),
              if (extra.isNotEmpty)
                PopupMenuButton<String>(
                  key: const Key('attr-add'),
                  tooltip: 'Add attribute',
                  icon: const Icon(Icons.add, size: 20),
                  onSelected: c.selectAttribute,
                  itemBuilder: (_) => [
                    for (final a in extra) PopupMenuItem(value: a, child: Text(a)),
                  ],
                ),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        _MarkButton(
          key: const Key('mark-red'),
          color: _markRed,
          icon: Icons.close_rounded,
          tooltip: 'Red (R)',
          onPressed: c.activeAttribute == null ? null : () => c.mark(MarkLabel.red),
        ),
        const SizedBox(width: 10),
        _MarkButton(
          key: const Key('mark-green'),
          color: _markGreen,
          icon: Icons.check_rounded,
          tooltip: 'Green (G)',
          onPressed:
              c.activeAttribute == null ? null : () => c.mark(MarkLabel.green),
        ),
      ]),
    );
  }
}

class _MarkButton extends StatelessWidget {
  const _MarkButton({
    super.key,
    required this.color,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}

class AnnotationDialog extends StatefulWidget {
  const AnnotationDialog({super.key});

  @override
  State<AnnotationDialog> createState() => _AnnotationDialogState();
}

class _AnnotationDialogState extends State<AnnotationDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Note at this moment'),
      content: TextField(
        key: const Key('annotation-text'),
        controller: _text,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            key: const Key('annotation-save'),
            onPressed: () => Navigator.pop(context, _text.text),
            child: const Text('Save')),
      ],
    );
  }
}
