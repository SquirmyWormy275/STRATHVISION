import 'package:flutter/material.dart';

import '../workbench/carne_controller.dart';

/// The reviewer's decision on one transcript.
sealed class TranscriptDecision {
  const TranscriptDecision();
}

class AcceptTranscript extends TranscriptDecision {
  const AcceptTranscript(this.text, this.author);
  final String text, author;
}

class DiscardTranscript extends TranscriptDecision {
  const DiscardTranscript();
}

String _clock(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Shows a local transcript for explicit review. Nothing is used until the
/// reviewer picks who is speaking and accepts. Returns null when dismissed.
Future<TranscriptDecision?> showTranscriptReview(
  BuildContext context,
  PendingTranscript pending,
) => showDialog<TranscriptDecision>(
  context: context,
  builder: (_) => _TranscriptReview(pending: pending),
);

class _TranscriptReview extends StatefulWidget {
  const _TranscriptReview({required this.pending});
  final PendingTranscript pending;
  @override
  State<_TranscriptReview> createState() => _TranscriptReviewState();
}

class _TranscriptReviewState extends State<_TranscriptReview> {
  late final _text = TextEditingController(
    text: widget.pending.transcript.text,
  );
  String? _author;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final segments = widget.pending.transcript.segments;
    return AlertDialog(
      title: Text('Review transcript · ${widget.pending.name}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transcribed on this computer. Check and correct it before it is used. '
                'Lines such as "priority: slope" or "ignore this clip" are applied like a text note.',
                style: muted,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('transcript-text'),
                controller: _text,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Transcript',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Text('Who is speaking?', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                key: const Key('transcript-author'),
                emptySelectionAllowed: true,
                segments: const [
                  ButtonSegment(value: 'coach', label: Text('Coach')),
                  ButtonSegment(value: 'athlete', label: Text('Athlete')),
                ],
                selected: {?_author},
                onSelectionChanged: (v) =>
                    setState(() => _author = v.firstOrNull),
              ),
              if (segments.isNotEmpty) ...[
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Timestamps (${segments.length})',
                    style: theme.textTheme.labelLarge,
                  ),
                  children: [
                    for (final s in segments)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${_clock(s.startMs)}–${_clock(s.endMs)}  ${s.text}',
                            style: muted,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('transcript-discard'),
          onPressed: () =>
              Navigator.of(context).pop(const DiscardTranscript()),
          child: const Text('Discard'),
        ),
        FilledButton(
          key: const Key('transcript-accept'),
          onPressed: _author == null || _text.text.trim().isEmpty
              ? null
              : () => Navigator.of(
                  context,
                ).pop(AcceptTranscript(_text.text, _author!)),
          child: const Text('Accept'),
        ),
      ],
    );
  }
}
