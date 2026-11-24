import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../workbench/carne_controller.dart';

typedef TranscriberConfigPicker = Future<String?> Function();

Future<String?> pickTranscriberConfig() async => (await FilePicker.pickFile(
  dialogTitle: 'Choose local transcriber.json',
  type: FileType.custom,
  allowedExtensions: const ['json'],
))?.path;

Future<void> showVoiceNotes(
  BuildContext context,
  CarneController controller, {
  TranscriberConfigPicker pickConfig = pickTranscriberConfig,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      VoiceNotesDialog(controller: controller, pickConfig: pickConfig),
);

class VoiceNotesDialog extends StatefulWidget {
  const VoiceNotesDialog({
    super.key,
    required this.controller,
    this.pickConfig = pickTranscriberConfig,
  });

  final CarneController controller;
  final TranscriberConfigPicker pickConfig;

  @override
  State<VoiceNotesDialog> createState() => _VoiceNotesDialogState();
}

class _VoiceNotesDialogState extends State<VoiceNotesDialog> {
  CarneController get c => widget.controller;
  String? _message;
  bool _configuring = false;

  Future<void> _configure() async {
    setState(() => _configuring = true);
    try {
      final path = await widget.pickConfig();
      if (path == null) return;
      await c.configureTranscriber(path);
      if (mounted) setState(() => _message = 'Local transcription is ready.');
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _configuring = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
  }

  Future<void> _review(String id) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VoiceReviewDialog(controller: c, noteId: id),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => AlertDialog(
      title: const Text('Voice notes'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Optional local transcription. Video review and CARNE ASADA '
                'work without a transcription model.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Transcription currently accepts 16 kHz mono PCM16 WAV files '
                'up to 10 minutes. Other audio is retained. Convert it separately, '
                'then add the converted WAV; conversion is not included.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('voice-setup'),
                  onPressed: _configuring || c.voiceBusy ? null : _configure,
                  icon: const Icon(Icons.folder_open),
                  label: Text(
                    _configuring
                        ? 'Checking local setup…'
                        : 'Choose transcriber.json',
                  ),
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(_message!, key: const Key('voice-setup-message')),
                ),
              if (c.voiceNotes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Add an audio file through “Feed CARNE ASADA” to start.',
                  ),
                ),
              for (final note in c.voiceNotes) ...[
                const Divider(),
                Text(note.name, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  note.acceptedBinding?['invalidated_at'] != null
                      ? 'Reviewed feedback — no longer used'
                      : _status(note.status),
                  key: Key('voice-status-${note.id}'),
                ),
                if (note.error != null) Text(note.error!),
                if (note.status == VoiceNoteStatus.transcribing)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (note.status == VoiceNoteStatus.received ||
                        note.status == VoiceNoteStatus.failed ||
                        note.status == VoiceNoteStatus.cancelled)
                      TextButton(
                        key: Key('voice-transcribe-${note.id}'),
                        onPressed: c.voiceBusy || c.busy
                            ? null
                            : () => _run(() => c.transcribeVoice(note.id)),
                        child: Text(
                          note.status == VoiceNoteStatus.received
                              ? 'Transcribe'
                              : 'Retry',
                        ),
                      ),
                    if (note.status == VoiceNoteStatus.transcribing)
                      TextButton(
                        key: Key('voice-cancel-${note.id}'),
                        onPressed: () => c.cancelVoice(note.id),
                        child: const Text('Cancel'),
                      ),
                    if (note.status == VoiceNoteStatus.draft ||
                        note.status == VoiceNoteStatus.accepted)
                      TextButton(
                        key: Key('voice-review-${note.id}'),
                        onPressed: () => _review(note.id),
                        child: Text(
                          note.status == VoiceNoteStatus.accepted
                              ? 'View reviewed feedback'
                              : 'Review',
                        ),
                      ),
                    if (note.status != VoiceNoteStatus.accepted &&
                        note.status != VoiceNoteStatus.rejected &&
                        note.status != VoiceNoteStatus.transcribing)
                      TextButton(
                        key: Key('voice-discard-${note.id}'),
                        onPressed: c.busy
                            ? null
                            : () => _run(() => c.rejectVoice(note.id)),
                        child: const Text('Discard'),
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
          key: const Key('voice-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

String _status(VoiceNoteStatus status) => switch (status) {
  VoiceNoteStatus.received => 'Ready to transcribe',
  VoiceNoteStatus.transcribing => 'Transcribing on this computer…',
  VoiceNoteStatus.draft => 'Draft — review before use',
  VoiceNoteStatus.accepted => 'Reviewed feedback',
  VoiceNoteStatus.rejected => 'Discarded — excluded from learning',
  VoiceNoteStatus.failed => 'Transcription needs attention',
  VoiceNoteStatus.cancelled => 'Cancelled — audio retained',
};

String _time(int ms) {
  final minutes = ms ~/ 60000;
  final seconds = (ms ~/ 1000 % 60).toString().padLeft(2, '0');
  final fraction = (ms % 1000).toString().padLeft(3, '0');
  return '$minutes:$seconds.$fraction';
}

class _VoiceReviewDialog extends StatefulWidget {
  const _VoiceReviewDialog({required this.controller, required this.noteId});
  final CarneController controller;
  final String noteId;

  @override
  State<_VoiceReviewDialog> createState() => _VoiceReviewDialogState();
}

class _VoiceReviewDialogState extends State<_VoiceReviewDialog> {
  CarneController get c => widget.controller;
  VoiceNote get note => c.voiceNotes.firstWhere((n) => n.id == widget.noteId);
  late final TextEditingController _text;
  final _author = TextEditingController();
  String? _clipId, _role, _attribute, _label, _error;
  int? _strokeIndex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Notifier updates must never replace the user's in-progress correction.
    _text = TextEditingController(text: note.draftText ?? '');
  }

  @override
  void dispose() {
    _text.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (note.status == VoiceNoteStatus.draft) {
        await c.editVoiceDraft(note.id, _text.text);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _saving = false;
        });
      }
    }
  }

  Future<void> _accept() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await c.acceptVoice(
        id: note.id,
        text: _text.text.trim(),
        clipId: _clipId!,
        strokeIndex: _strokeIndex!,
        authorName: _author.text.trim(),
        authorRole: _role!,
        attribute: _attribute!,
        label: _label!,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _saving = false;
        });
      }
    }
  }

  Widget _choice<T>({
    required String keyName,
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          key: Key(keyName),
          value: value,
          isExpanded: true,
          isDense: true,
          hint: const Text('Choose…'),
          items: items,
          onChanged: _saving ? null : onChanged,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final accepted = note.status == VoiceNoteStatus.accepted;
      final targets = c.voiceTargets;
      final sources = {
        for (final target in targets) target.clipId: target.name,
      };
      final clip = sources.containsKey(_clipId) ? _clipId : null;
      final swings = targets.where((t) => t.clipId == clip).toList();
      final selected = swings
          .where((t) => t.strokeIndex == _strokeIndex)
          .firstOrNull;
      final valid =
          _text.text.trim().isNotEmpty &&
          _text.text.length <= 32000 &&
          _author.text.trim().isNotEmpty &&
          _author.text.length <= 200 &&
          selected != null &&
          _role != null &&
          _attribute != null &&
          _label != null;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: AlertDialog(
          title: Text(
            accepted ? 'Reviewed voice feedback' : 'Review voice note',
          ),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(note.name),
                  Text(
                    'Event: ${c.pack.eventId}',
                    key: const Key('voice-event'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('voice-draft-text'),
                    controller: _text,
                    readOnly: accepted,
                    enabled: !_saving,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Reviewed transcript',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (accepted) ...[
                    const SizedBox(height: 12),
                    const Text('This reviewed note is read-only.'),
                    if (note.acceptedBinding case final binding?) ...[
                      if (binding['invalidated_reason'] case final reason?)
                        Text('This feedback is no longer used: $reason'),
                      Text('Source: ${binding['source_name']}'),
                      if (binding['stroke_index'] case final int index)
                        Text('Swing ${index + 1}'),
                      if (binding['start_ms'] case final int start)
                        if (binding['end_ms'] case final int end)
                          Text('${_time(start)}–${_time(end)}'),
                      Text(
                        'Author: ${binding['author_name']} (${binding['author_role']})',
                      ),
                      Text('Attribute: ${binding['attribute']}'),
                      Text('Label: ${binding['label']}'),
                      Text('Reviewed: ${binding['accepted_at']}'),
                      ExpansionTile(
                        title: const Text('Source record'),
                        tilePadding: EdgeInsets.zero,
                        children: [
                          SelectableText(
                            'Event: ${binding['event_id']}\n'
                            'Source: ${binding['clip_id']}\n'
                            'Audio: ${note.audioSha256}',
                          ),
                        ],
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Choose the source and swing this feedback describes. '
                      'Only your chosen red/green label is used for learning; '
                      'the transcript does not issue commands.',
                    ),
                    if (targets.isEmpty)
                      const Text(
                        'Add and analyze a clip before linking feedback to a swing.',
                      ),
                    _choice<String>(
                      keyName: 'voice-source',
                      label: 'Source clip',
                      value: clip,
                      items: [
                        for (final source in sources.entries)
                          DropdownMenuItem(
                            value: source.key,
                            child: Text(source.value),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        _clipId = value;
                        _strokeIndex = null;
                      }),
                    ),
                    _choice<int>(
                      keyName: 'voice-swing',
                      label: 'Swing',
                      value: selected?.strokeIndex,
                      items: [
                        for (final target in swings)
                          DropdownMenuItem(
                            value: target.strokeIndex,
                            child: Text(
                              'Swing ${target.strokeIndex + 1} · ${_time(target.startMs)}–${_time(target.endMs)}',
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _strokeIndex = value),
                    ),
                    if (selected != null)
                      SelectableText(
                        'Source: ${selected.name}\n${selected.clipId}\n'
                        'Swing ${selected.strokeIndex + 1}: ${_time(selected.startMs)}–${_time(selected.endMs)}',
                        key: const Key('voice-selected-target'),
                      ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const Key('voice-author-name'),
                      controller: _author,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Author name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    _choice<String>(
                      keyName: 'voice-author-role',
                      label: 'Author role',
                      value: _role,
                      items: const [
                        DropdownMenuItem(value: 'coach', child: Text('Coach')),
                        DropdownMenuItem(
                          value: 'athlete',
                          child: Text('Athlete'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _role = value),
                    ),
                    _choice<String>(
                      keyName: 'voice-attribute',
                      label: 'Attribute',
                      value: _attribute,
                      items: [
                        for (final attribute in c.attributes)
                          DropdownMenuItem(
                            value: attribute,
                            child: Text(attribute),
                          ),
                      ],
                      onChanged: (value) => setState(() => _attribute = value),
                    ),
                    _choice<String>(
                      keyName: 'voice-label',
                      label: 'Your feedback label',
                      value: _label,
                      items: const [
                        DropdownMenuItem(
                          value: 'red',
                          child: Text('Red — needs work'),
                        ),
                        DropdownMenuItem(
                          value: 'green',
                          child: Text('Green — good example'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _label = value),
                    ),
                  ],
                  if (_error != null)
                    Text(_error!, key: const Key('voice-review-error')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const Key('voice-review-close'),
              onPressed: _saving ? null : _close,
              child: Text(accepted ? 'Close' : 'Keep draft'),
            ),
            if (!accepted)
              FilledButton(
                key: const Key('voice-accept'),
                onPressed: valid && !_saving && !c.busy ? _accept : null,
                child: const Text('Use reviewed feedback'),
              ),
          ],
        ),
      );
    },
  );
}
