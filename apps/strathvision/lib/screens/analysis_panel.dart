import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/material.dart';

import '../analysis/analysis_controller.dart';
import '../packs/placeholder_pack.dart';
import '../workspace/workspace_controller.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Analyze button for the workspace top bar. Shown only when the active
/// stage has a clip.
class AnalyzeButton extends StatelessWidget {
  const AnalyzeButton({super.key, required this.analysis});

  final AnalysisController analysis;

  @override
  Widget build(BuildContext context) {
    final onPressed = analysis.running ? null : analysis.analyze;
    final icon = analysis.running
        ? const SizedBox.square(
            dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.insights, size: 18);
    // Phones: icon only, so the top bar never overflows.
    if (MediaQuery.sizeOf(context).width < 600) {
      return IconButton.filledTonal(
        key: const Key('analyze'),
        tooltip: 'Analyze',
        onPressed: onPressed,
        icon: icon,
      );
    }
    return FilledButton.tonalIcon(
      key: const Key('analyze'),
      onPressed: onPressed,
      icon: icon,
      label: const Text('Analyze'),
    );
  }
}

/// Raw analysis output for the clip on the active stage (Phase 3).
class AnalysisPanel extends StatelessWidget {
  const AnalysisPanel({super.key, required this.analysis, required this.pack});

  final AnalysisController analysis;
  final PackInfo pack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ws = analysis.workspace;
    final clip = ws.clipOn(ws.activeStage);
    final stage = ws.activeStage == Stage.a ? 'A' : 'B';
    final result = analysis.result;

    final Widget body;
    if (clip == null) {
      body = _Message(
          icon: Icons.movie_outlined,
          title: 'No clip on this stage',
          text: 'Add a clip, then tap Analyze.');
    } else if (analysis.running) {
      body = const _Running();
    } else if (result == null) {
      body = _Message(
        icon: Icons.insights,
        title: 'Not analyzed yet',
        text: 'Tap Analyze to measure this clip.',
      );
    } else {
      body = switch (result) {
        AnalysisSuccess(:final vector) =>
          _Metrics(vector: vector, pack: pack, fps: analysis.fps),
        AnalysisFailure(:final error) => _Failure(error: error),
      };
    }

    return Material(
      key: const Key('analysis-panel'),
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Analysis', style: theme.textTheme.titleSmall),
                    if (clip != null)
                      Text('$stage · ${clip.displayName}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (result != null && !analysis.running)
                IconButton(
                  key: const Key('analysis-rerun'),
                  tooltip: 'Analyze again',
                  onPressed: analysis.analyze,
                  icon: const Icon(Icons.refresh),
                ),
              IconButton(
                key: const Key('analysis-close'),
                tooltip: 'Close',
                onPressed: analysis.closePanel,
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

class _Running extends StatelessWidget {
  const _Running();

  @override
  Widget build(BuildContext context) => Column(
        key: const Key('analysis-running'),
        children: [
          const LinearProgressIndicator(),
          Expanded(
            child: Center(
              child: Text('Analyzing…',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
        ],
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 32, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.error});

  final AnalysisError error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      key: const Key('analysis-error'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Icon(Icons.info_outline, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(error.message, style: theme.textTheme.bodyLarge),
          ),
        ]),
        const SizedBox(height: 12),
        Text(error.errorCode,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.6)),
        for (final e in error.details.entries)
          Text('${e.key}: ${e.value}',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant, fontFeatures: _tabular)),
        const SizedBox(height: 16),
        Text('Review tools keep working without analysis.',
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.vector, required this.pack, required this.fps});

  final MetricVector vector;
  final PackInfo pack;
  final double fps;

  String _units(String key) {
    for (final m in pack.analysisPack.metrics) {
      if (m.key == key) return m.unit;
    }
    return '';
  }

  String _time(int frame) => '${(frame / fps).toStringAsFixed(2)} s';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: _tabular);
    final figures = theme.textTheme.bodyMedium
        ?.copyWith(fontFeatures: _tabular, fontWeight: FontWeight.w600);

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text(title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
        );

    return ListView(
      key: const Key('analysis-metrics'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8)),
          child: Text(
            'Body tracking is a stand-in in this build. Values are placeholders.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onTertiaryContainer),
          ),
        ),
        section('Body tracking'),
        _Row(
          label: 'Confidence',
          value: '${(vector.poseConfidenceSummary * 100).round()}%',
          confidence: vector.poseConfidenceSummary,
          numStyle: figures,
        ),
        section('Phases'),
        for (final e in vector.phases.entries)
          _Row(
            key: Key('phase-${e.key}'),
            label: pack.phaseLabel(e.key),
            sub: '${_time(e.value.startFrame)} – ${_time(e.value.endFrame)}'
                '  ·  frames ${e.value.startFrame}–${e.value.endFrame}',
            confidence: e.value.confidence,
            numStyle: figures,
            subStyle: muted,
          ),
        section('Metrics'),
        for (final e in vector.metrics.entries)
          _Row(
            key: Key('metric-${e.key}'),
            label: pack.metricLabel(e.key),
            sub: pack.phaseLabel(e.value.phase),
            value: '${e.value.value.toStringAsFixed(1)} ${_units(e.key)}'.trim(),
            confidence: e.value.confidence,
            numStyle: figures,
            subStyle: muted,
          ),
        section('Specialist residuals'),
        for (final e in vector.specialistResiduals.entries)
          _Row(
            key: Key('residual-${e.key}'),
            label: e.key,
            value: e.value.toStringAsFixed(3),
            numStyle: figures,
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.label,
    this.sub,
    this.value,
    this.confidence,
    this.numStyle,
    this.subStyle,
  });

  final String label;
  final String? sub;
  final String? value;
  final double? confidence;
  final TextStyle? numStyle;
  final TextStyle? subStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, overflow: TextOverflow.ellipsis),
            if (sub != null) Text(sub!, style: subStyle),
          ]),
        ),
        if (value != null) ...[
          const SizedBox(width: 8),
          Text(value!, style: numStyle),
        ],
        if (confidence != null) ...[
          const SizedBox(width: 12),
          Tooltip(
            message: 'Confidence ${(confidence! * 100).round()}%',
            child: SizedBox(
              width: 40,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: confidence,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
