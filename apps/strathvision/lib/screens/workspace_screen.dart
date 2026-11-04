import 'package:flutter/material.dart';

/// Dual-video workspace shell. Phase 1 is layout and navigation only;
/// video playback is forbidden until Phase 2 (docs/EXECUTION_PLAN.md).
class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workspace')),
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= constraints.maxHeight;
        const stages = [
          Expanded(child: _EmptyStage(label: 'A')),
          SizedBox(width: 8, height: 8),
          Expanded(child: _EmptyStage(label: 'B')),
        ];
        return Padding(
          padding: const EdgeInsets.all(8),
          child: wide
              ? const Row(children: stages)
              : const Column(children: stages),
        );
      }),
    );
  }
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: Key('stage-$label'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Stage $label',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('No clip loaded',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
