import 'dart:async';
import 'dart:ui' as ui;

import 'package:analysis_engine/analysis_engine.dart';
import 'package:flutter/material.dart';

import '../vision/athlete.dart';
import '../vision/person_detector.dart';
import '../vision/pose_service.dart';

/// The result of the picker: a person to follow, or back to automatic.
sealed class AthleteChoice {
  const AthleteChoice();
}

class FollowPerson extends AthleteChoice {
  const FollowPerson(this.target);
  final AthleteTarget target;
}

class FollowAutomatic extends AthleteChoice {
  const FollowAutomatic();
}

/// Shows a frame of [clip] with the people found in it; the user taps the
/// athlete (and can turn a sideways picture upright). Returns null when
/// cancelled.
Future<AthleteChoice?> showAthletePicker(
  BuildContext context, {
  required ClipSource clip,
  required AthleteTrack found,
  bool asking = false,
  PeopleLoader? load,
}) =>
    showDialog<AthleteChoice>(
      context: context,
      builder: (_) => AthletePicker(
          clip: clip, found: found, asking: asking, load: load ?? PoseService.instance.peopleAt),
    );

class AthletePicker extends StatefulWidget {
  const AthletePicker({
    super.key,
    required this.clip,
    required this.found,
    required this.load,
    this.asking = false,
  });

  final ClipSource clip;
  final AthleteTrack found;
  final PeopleLoader load;

  /// Opened because the automatic pick was unsure.
  final bool asking;

  @override
  State<AthletePicker> createState() => _AthletePickerState();
}

class _AthletePickerState extends State<AthletePicker> {
  late int _turns = widget.found.target?.quarterTurns ?? 0;
  late final int _frame = widget.found.candidatesFrame;
  PeopleFrame? _people;
  ui.Image? _image;
  bool _loading = true;
  bool _failed = false;

  /// The selected point (0..1 of the shown view).
  (double, double)? _point;

  @override
  void initState() {
    super.initState();
    final t = widget.found.target;
    if (t != null && !widget.asking) _point = (t.x, t.y);
    _reload();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final people = await widget.load(widget.clip, _frame, _turns);
    ui.Image? image;
    if (people != null) {
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
          people.rgba, people.width, people.height, ui.PixelFormat.rgba8888, done.complete);
      image = await done.future;
    }
    if (!mounted) {
      image?.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _people = people;
      _loading = false;
      _failed = people == null;
    });
  }

  void _turn(int by) {
    _turns = (_turns + by) % 4;
    _point = null;
    _reload();
  }

  PersonBox? get _selectedBox {
    final p = _point, people = _people?.people;
    if (p == null || people == null) return null;
    PersonBox? best;
    for (final b in people) {
      if (b.contains(p.$1, p.$2) && (best == null || b.width * b.height < best.width * best.height)) {
        best = b;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = _people;
    final selected = _selectedBox;
    return AlertDialog(
      key: const Key('athlete-picker'),
      title: Text(widget.asking ? 'Who is the athlete?' : 'Choose the athlete'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            widget.asking
                ? 'More than one person is moving in this clip. Tap the person to measure.'
                : 'Tap the person to measure. If the picture is sideways, turn it upright first.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 360,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _failed || _image == null || people == null
                    ? const Center(child: Text('This frame could not be shown.'))
                    : Center(
                        child: AspectRatio(
                          aspectRatio: people.width / people.height,
                          child: LayoutBuilder(
                            builder: (context, box) => GestureDetector(
                              key: const Key('athlete-picker-image'),
                              onTapUp: (d) => setState(() => _point = (
                                    (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0),
                                    (d.localPosition.dy / box.maxHeight).clamp(0.0, 1.0),
                                  )),
                              child: CustomPaint(
                                foregroundPainter: _BoxesPainter(
                                    people.people, selected, theme.colorScheme.primary),
                                child: RawImage(image: _image, fit: BoxFit.fill),
                              ),
                            ),
                          ),
                        ),
                      ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            IconButton(
              key: const Key('athlete-turn-left'),
              tooltip: 'Turn left',
              onPressed: _loading ? null : () => _turn(3),
              icon: const Icon(Icons.rotate_left),
            ),
            IconButton(
              key: const Key('athlete-turn-right'),
              tooltip: 'Turn right',
              onPressed: _loading ? null : () => _turn(1),
              icon: const Icon(Icons.rotate_right),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                people == null || _loading
                    ? ''
                    : people.people.isEmpty
                        ? 'Nobody found in this view.'
                        : selected == null
                            ? '${people.people.length} ${people.people.length == 1 ? 'person' : 'people'} found. Tap one.'
                            : 'Selected.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(
          key: const Key('athlete-automatic'),
          onPressed: () => Navigator.of(context).pop(const FollowAutomatic()),
          child: const Text('Pick automatically'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('athlete-confirm'),
          onPressed: selected == null
              ? null
              : () => Navigator.of(context).pop(FollowPerson(AthleteTarget(
                  quarterTurns: _turns, frame: _frame, x: selected.cx, y: selected.cy))),
          child: const Text('Measure this person'),
        ),
      ],
    );
  }
}

class _BoxesPainter extends CustomPainter {
  _BoxesPainter(this.people, this.selected, this.color);
  final List<PersonBox> people;
  final PersonBox? selected;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in people) {
      final on = identical(b, selected);
      final r = Rect.fromLTRB(b.x1 * size.width, b.y1 * size.height, b.x2 * size.width, b.y2 * size.height);
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = on ? 4 : 2
            ..color = on ? color : Colors.white.withValues(alpha: 0.85));
      if (!on) {
        canvas.drawRect(
            r.deflate(2),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = Colors.black.withValues(alpha: 0.5));
      }
    }
  }

  @override
  bool shouldRepaint(_BoxesPainter old) => old.people != people || old.selected != selected;
}
