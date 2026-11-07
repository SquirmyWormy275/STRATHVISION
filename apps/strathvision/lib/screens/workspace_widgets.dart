import 'package:flutter/material.dart';
import '../packs/placeholder_pack.dart';
import '../design/sv_theme.dart';
import '../workspace/project.dart' show Mark, MarkLabel;
import '../workspace/workspace_controller.dart';

String formatTime(Duration d) {
  final sign = d.isNegative ? '−' : '';
  d = d.abs();
  return '$sign${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}.'
      '${((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0')}';
}
String formatOffset(int ms) => '${ms < 0 ? '−' : '+'}${(ms.abs() / 1000).toStringAsFixed(2)} s';

class SyncStatusPill extends StatelessWidget {
  const SyncStatusPill({super.key, required this.controller});
  final WorkspaceController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller, scheme = Theme.of(context).colorScheme;
    final sync = c.sync;
    final label = sync == null ? (c.hasBothClips ? 'Not linked' : 'Single view') :
        '${c.locked ? 'Linked' : 'Independent'} · B ${formatOffset(sync.offsetMs)}';
    return Semantics(liveRegion: true, child: Container(key: const Key('sync-status'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: c.locked ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8)),
      child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Icon(c.locked ? Icons.link : c.hasBothClips ? Icons.link_off : Icons.crop_square,
          size: 18, color: c.locked ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
        Text(label, style: TextStyle(color: c.locked ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
      ])));
  }
}

class StagePanel extends StatelessWidget {
  const StagePanel({super.key, required this.controller, required this.stage,
    required this.onLoad, this.onScrub});
  final WorkspaceController controller;
  final Stage stage;
  final VoidCallback onLoad;
  final ValueChanged<Duration>? onScrub;
  @override
  Widget build(BuildContext context) {
    final c = controller, scheme = Theme.of(context).colorScheme;
    final clip = c.clipOn(stage), player = c.player(stage);
    final active = c.activeStage == stage && clip != null;
    final label = stage == Stage.a ? 'A' : 'B';
    return Column(children: [
      Expanded(child: Semantics(button: true, selected: active, label: 'Select video $label',
        child: GestureDetector(onTap: () => c.setActiveStage(stage),
          child: Container(decoration: BoxDecoration(
            color: clip == null ? scheme.surfaceContainerHighest : SvColors.graphite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? scheme.primary : Colors.transparent, width: 2)),
            clipBehavior: Clip.antiAlias,
            child: clip == null ? Center(child: Padding(padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Review footage', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                FilledButton.icon(key: Key('load-$label'), onPressed: onLoad,
                  icon: const Icon(Icons.add), label: const Text('Add a clip')),
              ]))) : Stack(fit: StackFit.expand, children: [
                if (player.hasMedia) RepaintBoundary(child: player.view(mirror: stage == Stage.b && c.mirrorB))
                else const Center(child: Padding(padding: EdgeInsets.all(24),
                  child: Text('Source unavailable. Replace this clip to continue.', style: TextStyle(color: SvColors.white)))),
                Positioned(left: 8, right: 60, top: 8, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(color: SvColors.graphite, borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    Text(label, style: const TextStyle(color: SvColors.white, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${active ? 'Active · ' : ''}${clip.displayName}', maxLines: 1,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(color: SvColors.white))),
                    if (stage == Stage.b && c.mirrorB) const Icon(Icons.flip, size: 18, color: SvColors.white),
                  ]))),
                Positioned(right: 4, top: 4, child: IconButton(key: Key('replace-$label'),
                  tooltip: 'Replace clip on $label', onPressed: onLoad,
                  style: IconButton.styleFrom(backgroundColor: SvColors.graphite, foregroundColor: SvColors.white),
                  icon: const Icon(Icons.swap_horiz_rounded))),
              ]))))),
      if (clip != null) Timeline(key: Key('timeline-$label'), position: player.position,
        duration: player.duration, marks: c.marksFor(stage), active: active,
        onScrub: onScrub ?? (d) => c.scrub(stage, d)),
    ]);
  }
}

class Timeline extends StatelessWidget {
  const Timeline({super.key, required this.position, required this.duration,
    required this.marks, required this.active, required this.onScrub});
  final Duration position, duration;
  final List<Mark> marks;
  final bool active;
  final ValueChanged<Duration> onScrub;
  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    final value = total <= 0 ? 0.0 : (position.inMilliseconds / total).clamp(0.0, 1.0);
    final style = TextStyle(fontSize: 14, fontFeatures: const [FontFeature.tabularFigures()],
        color: active ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant);
    final track = Semantics(label: '${marks.where((m) => m.label == MarkLabel.green).length} good marks; '
      '${marks.where((m) => m.label == MarkLabel.red).length} needs-work marks',
      child: SizedBox(height: 48, child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(child: CustomPaint(painter: _MarkTicks(marks, total))),
        Slider(value: value,
          semanticFormatterCallback: (v) => formatTime(Duration(milliseconds: (v * total).round())),
          onChanged: total <= 0 ? null : (v) => onScrub(Duration(milliseconds: (v * total).round()))),
      ])));
    if (MediaQuery.textScalerOf(context).scale(14) > 21) {
      return Column(children: [Wrap(spacing: 12, children: [
        Text(formatTime(position), style: style), Text(formatTime(duration), style: style)]), track]);
    }
    return Row(children: [SizedBox(width: 64, child: Text(formatTime(position), style: style)),
      Expanded(child: track), SizedBox(width: 64, child: Text(formatTime(duration), style: style))]);
  }
}

class _MarkTicks extends CustomPainter {
  _MarkTicks(this.marks, this.total);
  final List<Mark> marks;
  final int total;
  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final paint = Paint()..strokeWidth = 3..strokeCap = StrokeCap.round;
    for (final mark in marks) {
      final x = 24 + (size.width - 48) * (mark.timeMs / total).clamp(0.0, 1.0);
      final y = size.height / 2 - 10;
      paint.color = mark.label == MarkLabel.green ? SvColors.good : SvColors.needsWork;
      if (mark.label == MarkLabel.green) {
        canvas.drawLine(Offset(x - 3, y), Offset(x, y + 3), paint);
        canvas.drawLine(Offset(x, y + 3), Offset(x + 4, y - 3), paint);
      } else {
        canvas.drawLine(Offset(x - 3, y - 3), Offset(x + 3, y + 3), paint);
        canvas.drawLine(Offset(x - 3, y + 3), Offset(x + 3, y - 3), paint);
      }
    }
  }
  @override
  bool shouldRepaint(_MarkTicks old) => old.marks != marks || old.total != total;
}

const playbackRates = [0.1, 0.25, 0.5, 1.0];
class TransportBar extends StatelessWidget {
  const TransportBar({super.key, required this.controller, required this.onAnnotate,
    this.run, this.enabled = true});
  final WorkspaceController controller;
  final VoidCallback onAnnotate;
  final Future<void> Function(Future<void> Function())? run;
  final bool enabled;
  void invoke(Future<void> Function() action) {
    if (run != null) { run!(action); } else { action(); }
  }
  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.clipOn(Stage.a) == null && c.clipOn(Stage.b) == null) return const SizedBox(height: 8);
    Widget icon(String key, String label, IconData image, Future<void> Function() action) =>
      IconButton(key: Key(key), tooltip: label, onPressed: enabled ? () => invoke(action) : null, icon: Icon(image));
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: LayoutBuilder(builder: (context, bounds) {
        final compact = bounds.maxWidth < 600 || MediaQuery.textScalerOf(context).scale(16) > 24;
        return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8, runSpacing: 4, children: [
            icon('step-back', 'Previous frame (←)', Icons.skip_previous_rounded, () => c.stepFrame(forward: false)),
            FilledButton(key: const Key('play'), onPressed: enabled ? () => invoke(c.togglePlay) : null,
              child: Semantics(label: c.playing ? 'Pause' : 'Play', child: Icon(c.playing ? Icons.pause : Icons.play_arrow, size: 28))),
            icon('step-forward', 'Next frame (→)', Icons.skip_next_rounded, () => c.stepFrame(forward: true)),
            if (compact) DropdownButton<double>(key: const Key('rate'), value: playbackRates.contains(c.rate) ? c.rate : 1,
              underline: const SizedBox(), items: [for (final r in playbackRates)
                DropdownMenuItem(value: r, child: Text('${r == 1 ? '1' : r}×'))],
              onChanged: enabled ? (r) { if (r != null) invoke(() => c.setRate(r)); } : null)
            else SegmentedButton<double>(key: const Key('rate'), showSelectedIcon: false,
              segments: [for (final r in playbackRates) ButtonSegment(value: r, label: Text(r == 1 ? '1×' : '$r×'.replaceFirst('0.', '.')))],
              selected: {playbackRates.contains(c.rate) ? c.rate : 1.0},
              onSelectionChanged: enabled ? (s) => invoke(() => c.setRate(s.first)) : null),
            if (c.hasBothClips) ...[
              if (c.sync == null) OutlinedButton.icon(key: const Key('set-sync'),
                onPressed: enabled ? () => invoke(c.setSyncPoint) : null,
                icon: const Icon(Icons.link), label: const Text('Sync here'))
              else ...[
                OutlinedButton.icon(key: const Key('lock'), onPressed: enabled ? () => invoke(() => c.setLocked(!c.locked)) : null,
                  icon: Icon(c.locked ? Icons.link : Icons.link_off), label: Text(c.locked ? 'Linked' : 'Independent')),
                icon('resync', 'Set sync again here (S)', Icons.my_location, c.setSyncPoint),
                icon('clear-sync', 'Clear sync', Icons.link_off, c.clearSync),
              ],
              icon('mirror', 'Mirror B (M)', Icons.flip, c.toggleMirrorB),
              icon('swap', 'Swap A and B', Icons.swap_horiz, c.swapStages),
            ],
            TextButton.icon(key: const Key('annotate'), onPressed: enabled ? onAnnotate : null,
              icon: const Icon(Icons.sticky_note_2_outlined), label: const Text('Note')),
          ]);
      }));
  }
}

/// Explicit human judgments, never model grades or start/contact markers.
class MarkBar extends StatelessWidget {
  const MarkBar({super.key, required this.controller, required this.pack,
    this.onMark, this.enabled = true});
  final WorkspaceController controller;
  final PackInfo pack;
  final Future<void> Function(MarkLabel)? onMark;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final extra = pack.moreAttributes.where((a) => !c.attributes.contains(a)).toList();
    Widget mark(String key, String label, IconData icon, Color color, MarkLabel value) =>
      FilledButton.icon(key: Key(key), onPressed: enabled && c.activeAttribute != null
        ? () { if (onMark != null) { onMark!(value); } else { c.mark(value); } } : null,
        style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white,
          minimumSize: const Size(140, 56)), icon: Icon(icon), label: Text(label));
    return Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: Column(children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final attribute in c.attributes) Padding(padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(key: Key('attr-$attribute'), label: Text(attribute),
            selected: c.activeAttribute == attribute, showCheckmark: false,
            selectedColor: SvColors.cobalt, labelStyle: TextStyle(
              color: c.activeAttribute == attribute ? SvColors.white : Theme.of(context).colorScheme.onSurface),
            onSelected: enabled ? (_) => c.selectAttribute(attribute) : null)),
        if (extra.isNotEmpty) PopupMenuButton<String>(key: const Key('attr-add'), tooltip: 'Add attribute',
          enabled: enabled, onSelected: c.selectAttribute, icon: const Icon(Icons.add),
          itemBuilder: (_) => [for (final attr in extra) PopupMenuItem(value: attr, child: Text(attr))]),
      ])),
      const SizedBox(height: 8),
      Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 8, children: [
        mark('mark-green', 'Good', Icons.check, SvColors.good, MarkLabel.green),
        mark('mark-red', 'Needs work', Icons.close, SvColors.needsWork, MarkLabel.red),
      ]),
    ]));
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
  void dispose() { _text.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('Note at this moment'),
    content: TextField(key: const Key('annotation-text'), controller: _text,
      autofocus: true, maxLines: 3, minLines: 1, onSubmitted: (v) => Navigator.pop(context, v)),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const Key('annotation-save'), onPressed: () => Navigator.pop(context, _text.text), child: const Text('Save'))]);
}
