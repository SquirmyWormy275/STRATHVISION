import 'package:flutter/material.dart';

import '../workbench/workbench_controller.dart';
import 'profile_builder_screen.dart' show ClipsPicker, pickReferenceClips;

const _tabular = [FontFeature.tabularFigures()];

/// Desktop workbench for one profile: specialist-net harness and
/// compile-once adapters (Phase 7). Saves a new package version.
class WorkbenchScreen extends StatelessWidget {
  const WorkbenchScreen({
    super.key,
    required this.controller,
    required this.title,
    this.pickClips = pickReferenceClips,
  });

  final WorkbenchController controller;
  final String title;
  final ClipsPicker pickClips;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return Scaffold(
          appBar: AppBar(title: Text('Workbench · $title')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (c.head != null) _HarnessCard(controller: c, pickClips: pickClips),
                  const SizedBox(height: 16),
                  _AdaptersCard(controller: c),
                  const SizedBox(height: 24),
                  if (c.savedPath != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('Saved as the next version and added to your Library.',
                          key: const Key('workbench-saved'),
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  FilledButton.icon(
                    key: const Key('save-version'),
                    onPressed: c.hasChanges && !c.saving && c.savedPath == null
                        ? c.save
                        : null,
                    icon: const Icon(Icons.save_outlined),
                    label: Text('Save as v${c.bundle.profile.version + 1}'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HarnessCard extends StatelessWidget {
  const _HarnessCard({required this.controller, required this.pickClips});
  final WorkbenchController controller;
  final ClipsPicker pickClips;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final run = c.run;
    final before = run?.before ?? c.baseline;
    final probes = c.pack.probes.where((p) => p.head == c.head!.name).toList();
    String f(double? v) => v == null ? '—' : v.toStringAsFixed(3);
    return Card(
      key: const Key('harness'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Specialist net · ${c.head!.name}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
              c.currentPatch == null
                  ? 'Base weights. Add clips of this coach, then run the harness.'
                  : 'Currently ${c.currentPatch!.name}. New patches build on it.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              key: const Key('add-probe-clips'),
              onPressed: c.addingClips
                  ? null
                  : () async {
                      final paths = await pickClips();
                      if (paths.isNotEmpty) await c.addProbeClips(paths);
                    },
              icon: c.addingClips
                  ? const SizedBox.square(
                      dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add),
              label: const Text('Add coach clips'),
            ),
            const SizedBox(width: 12),
            Text('${c.probeClipCount} clips', key: const Key('probe-count')),
            const Spacer(),
            FilledButton.tonal(
              key: const Key('run-harness'),
              onPressed: c.probeClipCount > 0 && !c.addingClips ? c.runHarness : null,
              child: const Text('Run harness'),
            ),
          ]),
          if (before != null) ...[
            const SizedBox(height: 16),
            Table(
              key: const Key('probe-table'),
              columnWidths: const {0: FlexColumnWidth(2)},
              children: [
                TableRow(children: [
                  Text('Probe', style: theme.textTheme.labelMedium),
                  Text('Now', style: theme.textTheme.labelMedium),
                  Text('With patch', style: theme.textTheme.labelMedium),
                ]),
                for (final p in probes)
                  TableRow(children: [
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(p.name)),
                    Text(f(before[p.name]), style: const TextStyle(fontFeatures: _tabular)),
                    Text(run == null ? '' : f(run.after[p.name]),
                        key: Key('after-${p.name}'),
                        style: const TextStyle(fontFeatures: _tabular)),
                  ]),
              ],
            ),
          ],
          if (run != null) ...[
            const SizedBox(height: 12),
            Container(
              key: Key(run.decision.accepted ? 'patch-accepted' : 'patch-rejected'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: run.decision.accepted
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    run.decision.accepted
                        ? 'Accepted: ${run.patch!.name} (${run.newEdits} new edits)'
                        : 'Not accepted',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final r in run.decision.reasons)
                  Text('· $r', style: theme.textTheme.bodySmall),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

class _AdaptersCard extends StatelessWidget {
  const _AdaptersCard({required this.controller});
  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      key: const Key('adapters'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Adapters', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
              c.compiler == null
                  ? 'Compiling needs ANTHROPIC_API_KEY set on this computer. '
                      'Compiled adapters then run on the phone with no AI calls.'
                  : 'Compiled once here with ${c.compiler!.id}; they run on the '
                      'phone with no AI calls.',
              key: const Key('compiler-status'),
              style: muted),
          if (c.pack.adapters.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('This event has no adapter specs.', style: muted),
            ),
          for (final spec in c.pack.adapters)
            ListTile(
              key: Key('adapter-${spec.name}'),
              contentPadding: EdgeInsets.zero,
              title: Text(spec.name),
              subtitle: Text(
                  c.compileErrors[spec.name] ??
                      switch (c.adapterState(spec)) {
                        AdapterState.missing => 'Not compiled',
                        AdapterState.stale => 'Out of date: the spec changed',
                        AdapterState.compiled => 'Compiled in this package',
                        AdapterState.pending => 'Compiled · save to add it',
                      },
                  style: c.compileErrors.containsKey(spec.name)
                      ? muted?.copyWith(color: theme.colorScheme.error)
                      : muted),
              trailing: c.compiling.contains(spec.name)
                  ? const SizedBox.square(
                      dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      key: Key('compile-${spec.name}'),
                      onPressed: c.compiler == null ? null : () => c.compile(spec),
                      child: const Text('Compile'),
                    ),
            ),
        ]),
      ),
    );
  }
}
