import 'dart:io';
import 'dart:typed_data';

import 'package:analysis_engine/analysis_engine.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../packs/placeholder_pack.dart';
import '../profiles/builder_controller.dart';
import '../profiles/clip_probe.dart';
import '../profiles/profile_export.dart';

typedef ClipsPicker = Future<List<String>> Function();

Future<List<String>> pickReferenceClips() async {
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Choose reference clips',
    type: FileType.video,
  );
  return [for (final f in files) if (f.path != null) f.path!];
}

Future<String?> savePackageCopy(String fileName, List<int> bytes) async {
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Save profile package',
    fileName: fileName,
    bytes: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    mimeType: 'application/zip',
  );
  return uri?.toFilePath();
}

/// The production builder: probes and analyzes off the UI isolate, stores
/// packages under app support, and lists them in the Library.
ProfileBuilderController defaultProfileBuilder(AppDatabase db, PackInfo pack) =>
    ProfileBuilderController(
      pack: pack.analysisPack,
      probe: probeClip,
      evaluate: isolateEvaluator(pack.analysisPack),
      store: (profile) async {
        final support = await getApplicationSupportDirectory();
        return storeProfilePackage(
            profile, Directory(p.join(support.path, 'profiles')));
      },
      save: savePackageCopy,
      install: (meta, path) => db.saveProfile(meta, path),
    );

/// Build a coach profile from reference clips (Phase 4).
class ProfileBuilderScreen extends StatefulWidget {
  const ProfileBuilderScreen({
    super.key,
    required this.controller,
    this.pickClips = pickReferenceClips,
  });

  final ProfileBuilderController controller;
  final ClipsPicker pickClips;

  @override
  State<ProfileBuilderScreen> createState() => _ProfileBuilderScreenState();
}

class _ProfileBuilderScreenState extends State<ProfileBuilderScreen> {
  ProfileBuilderController get c => widget.controller;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final paths = await widget.pickClips();
    if (paths.isNotEmpty) await c.addClips(paths);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(title: const Text('Build a profile')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      key: const Key('coach-name'),
                      controller: _name,
                      onChanged: c.setCoachName,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Whose style is this?',
                        hintText: 'Coach name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  _Progress(controller: c),
                  Expanded(
                    child: c.clips.isEmpty
                        ? _EmptyClips(minClips: c.minClips, onAdd: _add)
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 16),
                            children: [
                              for (final clip in c.clips)
                                _ClipTile(
                                  key: Key('clip-${clip.displayName}'),
                                  clip: clip,
                                  onRemove: () => c.removeClip(clip),
                                ),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    key: const Key('add-clips'),
                                    onPressed: _add,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add more clips'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  if (c.outcome != null) _Outcome(controller: c),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      key: const Key('build'),
                      onPressed: c.canBuild ? c.build : null,
                      icon: c.building
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.person_pin_outlined),
                      label: Text(c.checking
                          ? 'Checking clips…'
                          : 'Build profile'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          textStyle: theme.textTheme.titleSmall),
                    ),
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

class _Progress extends StatelessWidget {
  const _Progress({required this.controller});
  final ProfileBuilderController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.clips.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final ratio = (c.usableCount / c.minClips).clamp(0.0, 1.0);
    final enough = c.usableCount >= c.minClips;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          key: const Key('builder-progress'),
          enough
              ? '${c.usableCount} clean clips · enough to build'
              : '${c.usableCount} of ${c.minClips} clean clips',
          style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: ratio, minHeight: 6),
        ),
      ]),
    );
  }
}

class _EmptyClips extends StatelessWidget {
  const _EmptyClips({required this.minClips, required this.onAdd});
  final int minClips;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.video_collection_outlined,
              size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('Add $minClips or more clips of one person',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Same movement, clearly visible. Each clip is checked as it comes in.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            key: const Key('add-clips'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add clips'),
          ),
        ]),
      ),
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({super.key, required this.clip, required this.onRemove});
  final BuilderClip clip;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = clip.quality;
    final Widget leading;
    final String subtitle;
    if (clip.status == ClipStatus.checking) {
      leading = const SizedBox.square(
          dimension: 20, child: CircularProgressIndicator(strokeWidth: 2));
      subtitle = 'Checking…';
    } else if (clip.usable) {
      leading = Icon(Icons.check_circle, color: scheme.primary);
      subtitle = 'Clean';
    } else {
      leading = Icon(Icons.remove_circle_outline, color: scheme.error);
      subtitle = q?.reasons.join(' ') ?? 'Not usable';
    }
    return ListTile(
      leading: leading,
      title: Text(clip.displayName, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      trailing: IconButton(
        tooltip: 'Remove',
        onPressed: onRemove,
        icon: const Icon(Icons.close),
      ),
    );
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.controller});
  final ProfileBuilderController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return switch (c.outcome!) {
      BuildReady(:final profile, :final consistency) => Card(
          key: const Key('build-ready'),
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${profile.coachName} · v${profile.version} is ready',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: scheme.onPrimaryContainer)),
              const SizedBox(height: 4),
              Text(
                '${profile.sourceClipCount} clips · held-out match '
                '${(consistency.meanScore * 100).round()}%. '
                'Added to your Library.',
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 12),
              Row(children: [
                OutlinedButton.icon(
                  key: const Key('save-package'),
                  onPressed: c.exportCopy,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save a copy'),
                ),
                const SizedBox(width: 12),
                if (c.savedTo != null)
                  Expanded(
                    child: Text('Saved',
                        key: const Key('saved'),
                        style: TextStyle(color: scheme.onPrimaryContainer)),
                  ),
              ]),
            ]),
          ),
        ),
      BuildRejected(:final error) => Card(
          key: const Key('build-rejected'),
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          color: scheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.info_outline, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(error.message, style: theme.textTheme.bodyLarge)),
              ]),
              const SizedBox(height: 6),
              Text(error.errorCode,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant, letterSpacing: 0.6)),
            ]),
          ),
        ),
    };
  }
}
