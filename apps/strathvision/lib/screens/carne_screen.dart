import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../workbench/carne_controller.dart';

typedef AnyFilesPicker = Future<List<String>> Function();

Future<List<String>> pickAnyFiles() async {
  final files = await FilePicker.pickFiles(dialogTitle: 'Feed CARNE ASADA');
  return [for (final f in files) if (f.path != null) f.path!];
}

/// CARNE ASADA playground (desktop only). One drop zone, plain-language
/// status, Good/Great/Excellent meters, what-did-it-just-do, one-click undo.
class CarneScreen extends StatefulWidget {
  const CarneScreen({
    super.key,
    required this.controller,
    required this.title,
    this.pickFiles = pickAnyFiles,
  });

  final CarneController controller;
  final String title;
  final AnyFilesPicker pickFiles;

  @override
  State<CarneScreen> createState() => _CarneScreenState();
}

class _CarneScreenState extends State<CarneScreen> {
  bool _hover = false;
  CarneController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final s = c.session;
        return Scaffold(
          appBar: AppBar(title: Text('CARNE ASADA · ${widget.title}')),
          body: LayoutBuilder(builder: (context, box) {
            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: DropTarget(
                    onDragEntered: (_) => setState(() => _hover = true),
                    onDragExited: (_) => setState(() => _hover = false),
                    onDragDone: (d) {
                      setState(() => _hover = false);
                      c.drop([for (final f in d.files) f.path]);
                    },
                    child: AnimatedContainer(
                      key: const Key('drop-zone'),
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        color: _hover ? scheme.primaryContainer : scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: _hover ? scheme.primary : scheme.outlineVariant, width: 2),
                      ),
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.local_fire_department_outlined,
                              size: 48, color: scheme.primary),
                          const SizedBox(height: 8),
                          Text('Feed CARNE ASADA', style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text('Clips, packages, voice notes, text notes',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 12),
                          if (c.busy)
                            const SizedBox.square(
                                dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            OutlinedButton(
                              key: const Key('choose-files'),
                              onPressed: () async {
                                final paths = await widget.pickFiles();
                                if (paths.isNotEmpty) await c.drop(paths);
                              },
                              child: const Text('or choose files'),
                            ),
                        ]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _Meters(minutes: s.usableMinutes, good: s.meters.good, great: s.meters.great,
                    excellent: s.meters.excellent),
                const SizedBox(height: 12),
                Row(children: [
                  Text('Priority', style: theme.textTheme.labelLarge),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(spacing: 6, children: [
                      for (final a in c.priorities)
                        ChoiceChip(
                          key: Key('priority-$a'),
                          label: Text(a),
                          selected: s.priority == a,
                          onSelected: c.canChangeSettings ? (_) => c.setPriority(a) : null,
                        ),
                    ]),
                  ),
                ]),
                SwitchListTile(
                  key: const Key('chaos'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Chaos'),
                  subtitle: const Text('Loosens the coach hull for this session only.'),
                  value: s.chaos,
                  onChanged: c.canChangeSettings ? c.setChaos : null,
                ),
              ],
            );
            final right = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Status', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Expanded(
                  flex: 3,
                  child: ListView(
                    key: const Key('feed'),
                    reverse: true,
                    children: [
                      for (final line in c.feed.reversed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Text(line.text)),
                            if (line.useAnywayClip != null)
                              TextButton(
                                key: Key('use-anyway-${line.useAnywayClip}'),
                                onPressed: () => c.useAnyway(line.useAnywayClip!),
                                child: const Text('Use anyway'),
                              ),
                          ]),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                Row(children: [
                  Text('What did it just do?', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text('${s.edits.length} of ${s.limit} edits',
                      key: const Key('edit-count'), style: theme.textTheme.bodySmall),
                ]),
                Expanded(
                  flex: 2,
                  child: s.edits.isEmpty
                      ? Center(
                          child: Text('No changes yet.',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)))
                      : ListView(
                          key: const Key('edits'),
                          children: [
                            for (final e in s.edits.reversed)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.check_circle_outline),
                                title: Text(e.explanation),
                              ),
                          ],
                        ),
                ),
                Row(children: [
                  OutlinedButton.icon(
                    key: const Key('undo-edit'),
                    onPressed: s.edits.isEmpty ? null : c.undo,
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: const Key('try-update'),
                    onPressed: s.baselineMet && !s.limitReached ? c.tryUpdate : null,
                    child: const Text('Look for an update'),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('save-carne'),
                    onPressed: s.edits.isEmpty || c.savedPath != null ? null : c.save,
                    child: Text(c.savedPath != null
                        ? 'Saved'
                        : 'Save as v${c.bundle.profile.version + 1}'),
                  ),
                ]),
              ],
            );
            final wide = box.maxWidth >= 900;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: left),
                      const SizedBox(width: 24),
                      Expanded(child: right),
                    ])
                  : Column(children: [
                      Expanded(child: left),
                      const SizedBox(height: 16),
                      Expanded(child: right),
                    ]),
            );
          }),
        );
      },
    );
  }
}

class _Meters extends StatelessWidget {
  const _Meters({
    required this.minutes,
    required this.good,
    required this.great,
    required this.excellent,
  });

  final double minutes, good, great, excellent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget meter(String label, double target) {
      final v = (minutes / target).clamp(0.0, 1.0);
      return Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label · ${target.toStringAsFixed(0)} min',
              style: theme.textTheme.labelSmall?.copyWith(
                  color: v >= 1 ? scheme.primary : scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: v, minHeight: 6),
          ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${minutes.toStringAsFixed(1)} min of usable footage',
          key: const Key('usable-minutes'),
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(height: 6),
      Row(children: [
        meter('Good', good),
        const SizedBox(width: 8),
        meter('Great', great),
        const SizedBox(width: 8),
        meter('Excellent', excellent),
      ]),
    ]);
  }
}
