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

/// "Compare with" picker. Lists ready profiles for this pack's event.
class _ProfileSelector extends StatelessWidget {
  const _ProfileSelector({required this.analysis});
  final AnalysisController analysis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final choices = analysis.choices;
    final error = analysis.profileError;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (choices.isEmpty)
          Text('Build or import a profile to compare against it.',
              key: const Key('no-profiles'), style: muted)
        else
          Row(children: [
            Text('Compare with', style: muted),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String>(
                key: const Key('profile-select'),
                isExpanded: true,
                isDense: true,
                underline: const SizedBox.shrink(),
                value: analysis.selectedProfile?.key ?? '',
                items: [
                  const DropdownMenuItem(value: '', child: Text('Nobody')),
                  for (final c in choices)
                    DropdownMenuItem(
                        value: c.key,
                        child: Text(c.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: analysis.running
                    ? null
                    : (k) => analysis.selectProfile(
                        choices.where((c) => c.key == k).firstOrNull),
              ),
            ),
          ]),
        if (error != null)
          Text(error.message,
              key: const Key('profile-error'),
              style: muted?.copyWith(color: theme.colorScheme.error)),
      ]),
    );
  }
}

/// Analysis output for the clip on the active stage: the style comparison
/// (Phase 5) when a profile is selected, then the raw measurements.
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
        AnalysisSuccess(:final vector) => _Metrics(
            vector: vector,
            pack: pack,
            fps: analysis.fps,
            comparison: analysis.comparison,
            profileLabel: analysis.selectedProfile?.label,
            focus: analysis.analysis?.focus,
          ),
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
          if (clip != null) _ProfileSelector(analysis: analysis),
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
  const _Metrics({
    required this.vector,
    required this.pack,
    required this.fps,
    this.comparison,
    this.profileLabel,
    this.focus,
  });

  final MetricVector vector;
  final PackInfo pack;
  final double fps;
  final ComparisonOutcome? comparison;
  final String? profileLabel;
  final String? focus;

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
        if (comparison case final c?)
          switch (c) {
            ComparisonSuccess(:final result) => _Comparison(
                result: result,
                pack: pack,
                profileLabel: profileLabel ?? '',
                focus: focus),
            ComparisonFailure(:final error) => Padding(
                key: const Key('comparison-error'),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  Icon(Icons.info_outline, color: scheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error.message)),
                  Text(error.errorCode, style: muted),
                ]),
              ),
          },
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
        section('Measurements'),
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

/// Overall score, warnings, and ranked deltas (expandable).
class _Comparison extends StatelessWidget {
  const _Comparison({
    required this.result,
    required this.pack,
    required this.profileLabel,
    this.focus,
  });

  final ComparisonResult result;
  final PackInfo pack;
  final String profileLabel;

  /// From the package's priority adapter.
  final String? focus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: _tabular);
    final defs = {for (final m in pack.analysisPack.metrics) m.key: m};
    return Column(
      key: const Key('comparison'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${(result.overallScore * 100).round()}%',
                key: const Key('overall-score'),
                style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600, fontFeatures: _tabular)),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('style match with $profileLabel',
                    style: theme.textTheme.bodyMedium),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
              '${result.metricsUsed} measurements compared'
              '${result.appliedPatches.isEmpty ? '' : ' · patches: ${result.appliedPatches.join(', ')}'}',
              key: const Key('comparison-coverage'),
              style: muted),
        ),
        if (focus != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              Icon(Icons.center_focus_strong, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text('Focus next: ', style: theme.textTheme.bodyMedium),
              Text(focus!,
                  key: const Key('focus'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
        for (final w in result.warnings)
          Container(
            key: Key('warning-${result.warnings.indexOf(w)}'),
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded,
                  size: 16, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(w,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onErrorContainer)),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
          child: Text('BIGGEST DIFFERENCES',
              style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant, letterSpacing: 0.8)),
        ),
        for (final d in result.rankedDeltas)
          _DeltaTile(delta: d, def: defs[d.metricKey], pack: pack),
      ],
    );
  }
}

class _DeltaTile extends StatelessWidget {
  const _DeltaTile({required this.delta, required this.def, required this.pack});

  final RankedDelta delta;
  final MetricDef? def;
  final PackInfo pack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = delta;
    final unit = def?.unit ?? '';
    String v(double x) => '${x.toStringAsFixed(1)}${unit == '°' ? '' : ' '}$unit';
    final (IconData icon, String dir) = switch (d.direction) {
      'higher' => (Icons.arrow_upward, 'Higher than coach'),
      'lower' => (Icons.arrow_downward, 'Lower than coach'),
      _ => (Icons.check, 'Within the coach\'s range'),
    };
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: _tabular);
    final figures = theme.textTheme.bodyMedium
        ?.copyWith(fontFeatures: _tabular, fontWeight: FontWeight.w600);
    return ExpansionTile(
      key: Key('delta-${d.metricKey}'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      leading: Icon(icon,
          size: 20,
          color: d.direction == 'neutral' ? scheme.primary : scheme.tertiary),
      title: Text(pack.metricLabel(d.metricKey), overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '${pack.phaseLabel(d.phase)} · $dir · '
          '${d.distanceSpreads.toStringAsFixed(1)} spreads',
          style: muted),
      trailing: SizedBox(
        width: 40,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: (d.contribution * 2).clamp(0.0, 1.0),
            minHeight: 4,
            color: scheme.tertiary,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ),
      children: [
        if (def != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                describeMetric(def!, phaseLabel: pack.phaseLabel),
                key: Key('definition-${d.metricKey}'),
                style: theme.textTheme.bodySmall),
          ),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('This clip', style: muted),
              Text(v(d.userValue), key: Key('user-${d.metricKey}'), style: figures),
            ]),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Coach', style: muted),
              Text('${v(d.coachCenter)} ± ${v(d.coachSpread)}',
                  key: Key('coach-${d.metricKey}'), style: figures),
            ]),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Phase', style: muted),
              Text(pack.phaseLabel(d.phase), style: figures),
            ]),
          ),
        ]),
      ],
    );
  }
}
