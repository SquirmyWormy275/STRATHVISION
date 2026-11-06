import 'dart:math' as math;

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/material.dart';

import '../packs/placeholder_pack.dart';

const _tabular = [FontFeature.tabularFigures()];

String _day(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[d.month - 1]} ${d.day}';
}

/// Match trend for one profile on this install (single user per install,
/// so the athlete is implicit): style-match by session plus how far each
/// measurement sits from the coach over time.
class DriftScreen extends StatefulWidget {
  const DriftScreen({
    super.key,
    required this.title,
    required this.summary,
    this.pack,
  });

  final String title;
  final DriftSummary summary;

  /// For metric labels; null falls back to keys.
  final PackInfo? pack;

  @override
  State<DriftScreen> createState() => _DriftScreenState();
}

class _DriftScreenState extends State<DriftScreen> {
  bool _table = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.summary;
    final sessions = s.sessions;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: _tabular);

    if (sessions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Match trend · ${widget.title}')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.show_chart, size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('No comparisons yet', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Compare clips with this profile in Analyze. Each day becomes a point here.',
                  key: const Key('drift-empty'),
                  textAlign: TextAlign.center,
                  style: muted),
            ]),
          ),
        ),
      );
    }

    final last = sessions.last;
    final first = sessions.first;
    final change = (last.meanScore - first.meanScore) * 100;
    final (String trend, IconData icon) = switch (s.direction) {
      DriftDirection.closer => ('Getting closer to this style', Icons.trending_up),
      DriftDirection.further => ('Drifting away from this style', Icons.trending_down),
      DriftDirection.steady => ('Holding steady', Icons.trending_flat),
      DriftDirection.unknown => ('One session so far', Icons.more_horiz),
    };
    final metricKeys = {for (final x in sessions) ...x.meanDistances.keys}.toList()
      ..sort((a, b) => (last.meanDistances[b] ?? 0).compareTo(last.meanDistances[a] ?? 0));

    return Scaffold(
      appBar: AppBar(title: Text('Match trend · ${widget.title}'), actions: [
        IconButton(
          key: const Key('drift-table-toggle'),
          tooltip: _table ? 'Show chart' : 'Show table',
          icon: Icon(_table ? Icons.show_chart : Icons.table_rows_outlined),
          onPressed: () => setState(() => _table = !_table),
        ),
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${(last.meanScore * 100).round()}%',
                    key: const Key('drift-latest'),
                    style: theme.textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.w600, fontFeatures: _tabular)),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                        'latest session · ${sessions.length > 1 ? '${change >= 0 ? '+' : '−'}${change.abs().round()} points since ${_day(first.day)}' : _day(last.day)}',
                        style: muted),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(trend, key: const Key('drift-direction'), style: theme.textTheme.bodyMedium),
              ]),
              const SizedBox(height: 16),
              Text('Style match by session', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_table)
                _SessionTable(sessions: sessions)
              else
                SizedBox(height: 220, child: _ScoreChart(sessions: sessions)),
              const SizedBox(height: 24),
              Text('Distance from the coach, by measurement', style: theme.textTheme.titleSmall),
              Text('In spreads. Lower is closer.', style: muted),
              const SizedBox(height: 8),
              for (final k in metricKeys)
                _MetricTrendRow(
                  key: Key('drift-metric-$k'),
                  label: widget.pack?.metricLabel(k) ?? k,
                  values: [for (final x in sessions) x.meanDistances[k]],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionTable extends StatelessWidget {
  const _SessionTable({required this.sessions});
  final List<DriftSession> sessions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const num = TextStyle(fontFeatures: _tabular);
    return Table(
      key: const Key('drift-table'),
      columnWidths: const {0: FlexColumnWidth(2)},
      children: [
        TableRow(children: [
          Text('Session', style: theme.textTheme.labelMedium),
          Text('Match', style: theme.textTheme.labelMedium),
          Text('Clips', style: theme.textTheme.labelMedium),
        ]),
        for (final s in sessions)
          TableRow(children: [
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(_day(s.day))),
            Text('${(s.meanScore * 100).round()}%', style: num),
            Text('${s.count}', style: num),
          ]),
      ],
    );
  }
}

/// One series, so no legend: the section title names it. Thin 2px line,
/// 8px markers, recessive grid, crosshair + tooltip on hover or tap.
class _ScoreChart extends StatefulWidget {
  const _ScoreChart({required this.sessions});
  final List<DriftSession> sessions;

  @override
  State<_ScoreChart> createState() => _ScoreChartState();
}

class _ScoreChartState extends State<_ScoreChart> {
  int? _hover;

  int _nearest(double dx, double width) {
    final n = widget.sessions.length;
    if (n == 1) return 0;
    final plot = width - _ChartPainter.left - _ChartPainter.right;
    final i = ((dx - _ChartPainter.left) / plot * (n - 1)).round();
    return i.clamp(0, n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final painter = _ChartPainter(
        sessions: widget.sessions,
        line: scheme.primary,
        grid: scheme.outlineVariant.withValues(alpha: 0.6),
        ink: scheme.onSurfaceVariant,
        surface: scheme.surface,
        hover: _hover,
        labelStyle: theme.textTheme.labelSmall!.copyWith(
            color: scheme.onSurfaceVariant, fontFeatures: _tabular),
      );
      final h = _hover;
      return MouseRegion(
        onHover: (e) => setState(() => _hover = _nearest(e.localPosition.dx, box.maxWidth)),
        onExit: (_) => setState(() => _hover = null),
        child: GestureDetector(
          onTapDown: (e) => setState(() => _hover = _nearest(e.localPosition.dx, box.maxWidth)),
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(key: const Key('drift-chart'), painter: painter)),
            if (h != null)
              Positioned(
                left: (painter.xFor(h, box.maxWidth) - 60).clamp(0.0, math.max(0.0, box.maxWidth - 120)),
                top: 0,
                child: Container(
                  key: const Key('drift-tooltip'),
                  width: 120,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.inverseSurface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DefaultTextStyle(
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: scheme.onInverseSurface, fontFeatures: _tabular),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_day(widget.sessions[h].day)),
                      Text('${(widget.sessions[h].meanScore * 100).round()}% match'),
                      Text('${widget.sessions[h].count} clips'),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.sessions,
    required this.line,
    required this.grid,
    required this.ink,
    required this.surface,
    required this.labelStyle,
    this.hover,
  });

  static const left = 36.0, right = 12.0, top = 12.0, bottom = 24.0;
  final List<DriftSession> sessions;
  final Color line, grid, ink, surface;
  final TextStyle labelStyle;
  final int? hover;

  double xFor(int i, double width) {
    final plot = width - left - right;
    return sessions.length == 1 ? left + plot / 2 : left + plot * i / (sessions.length - 1);
  }

  double _y(double score, double height) => top + (height - top - bottom) * (1 - score);

  void _text(Canvas c, String s, Offset at, {bool right = false}) {
    final tp = TextPainter(text: TextSpan(text: s, style: labelStyle), textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, right ? at - Offset(tp.width, tp.height / 2) : at - Offset(tp.width / 2, 0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final y = _y(v, size.height);
      canvas.drawLine(Offset(left, y), Offset(size.width - right, y), g);
      _text(canvas, '${(v * 100).round()}%', Offset(left - 6, y), right: true);
    }
    final pts = [
      for (var i = 0; i < sessions.length; i++)
        Offset(xFor(i, size.width), _y(sessions[i].meanScore, size.height)),
    ];
    final labelEvery = math.max(1, (sessions.length / 6).ceil());
    for (var i = 0; i < sessions.length; i += labelEvery) {
      _text(canvas, _day(sessions[i].day), Offset(pts[i].dx, size.height - bottom + 6));
    }
    if (hover != null) {
      canvas.drawLine(Offset(pts[hover!].dx, top), Offset(pts[hover!].dx, size.height - bottom),
          Paint()
            ..color = ink.withValues(alpha: 0.5)
            ..strokeWidth = 1);
    }
    if (pts.length > 1) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = line
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round);
    }
    for (var i = 0; i < pts.length; i++) {
      final r = i == hover ? 5.0 : 4.0;
      canvas.drawCircle(pts[i], r + 2, Paint()..color = surface); // 2px surface ring
      canvas.drawCircle(pts[i], r, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.hover != hover || old.sessions != sessions || old.line != line;
}

/// Label, sparkline of distance (in spreads) per session, latest value.
class _MetricTrendRow extends StatelessWidget {
  const _MetricTrendRow({super.key, required this.label, required this.values});
  final String label;
  final List<double?> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final latest = values.lastWhere((v) => v != null, orElse: () => null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(flex: 3, child: Text(label, overflow: TextOverflow.ellipsis)),
        Expanded(
          flex: 4,
          child: SizedBox(
            height: 24,
            child: CustomPaint(
                painter: _Spark(values: values, color: scheme.primary, base: scheme.outlineVariant)),
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(latest == null ? '—' : latest.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: _tabular)),
        ),
      ]),
    );
  }
}

class _Spark extends CustomPainter {
  _Spark({required this.values, required this.color, required this.base});
  final List<double?> values;
  final Color color, base;

  @override
  void paint(Canvas canvas, Size size) {
    final vs = values.whereType<double>().toList();
    if (vs.isEmpty) return;
    final maxV = math.max(1.0, vs.reduce(math.max));
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1),
        Paint()
          ..color = base
          ..strokeWidth = 1);
    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final x = values.length == 1 ? size.width / 2 : size.width * i / (values.length - 1);
      pts.add(Offset(x, (size.height - 3) * (1 - v / maxV) + 1));
    }
    if (pts.length > 1) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke);
    }
    canvas.drawCircle(pts.last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Spark old) => old.values != values;
}
