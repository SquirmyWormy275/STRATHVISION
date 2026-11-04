import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:analysis_engine/analysis_engine.dart' show PackDefinition;

import '../analysis/analysis_controller.dart';
import '../data/database.dart';
import '../packs/pack_registry.dart';
import '../packs/placeholder_pack.dart';
import '../profiles/builder_controller.dart';
import '../profiles/profile_package.dart';
import '../workspace/project.dart';
import 'profile_builder_screen.dart';
import 'workspace_route.dart';
import 'workspace_screen.dart';

/// Picks a profile package path. Injectable so tests can bypass the platform
/// file dialog.
typedef ProfilePathPicker = Future<String?> Function();

Future<String?> pickProfileFile() async {
  final file = await FilePicker.pickFile(
    dialogTitle: 'Import a profile package',
    type: FileType.custom,
    allowedExtensions: const ['json', 'zip'],
  );
  return file?.path;
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    super.key,
    required this.db,
    this.pickPath = pickProfileFile,
    this.pickClip = pickClipFile,
    this.playerFactory = defaultStagePlayer,
    this.analysisRunner,
    this.profileBuilder = defaultProfileBuilder,
    this.pickClips = pickReferenceClips,
    this.packs = const [],
  });

  final AppDatabase db;
  final ProfilePathPicker pickPath;
  final ClipPathPicker pickClip;
  final StagePlayerFactory playerFactory;
  final AnalysisRunner? analysisRunner;
  final ProfileBuilderController Function(AppDatabase db, PackInfo pack)
      profileBuilder;
  final ClipsPicker pickClips;

  /// Installed packs (empty = built-in placeholder only).
  final List<PackDefinition> packs;

  List<PackDefinition> get _packs => packs.isEmpty ? [placeholderDefinition] : packs;

  Future<void> _buildProfile(BuildContext context, PackInfo pack) async {
    final controller = profileBuilder(db, pack);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          ProfileBuilderScreen(controller: controller, pickClips: pickClips),
    ));
    controller.dispose();
  }

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final path = await pickPath();
    if (path == null) return;
    try {
      final meta = await readProfilePackage(path);
      await db.saveProfile(meta, path);
      messenger.showSnackBar(SnackBar(
          content: Text('Imported ${meta.coachName} · v${meta.version}')));
    } on AnalysisError catch (e) {
      final problems = (e.details['problems'] as List?)?.cast<String>();
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(problems == null || problems.isEmpty
            ? e.message
            : '${e.message} ${problems.first}'
                '${problems.length > 1 ? ' (+${problems.length - 1} more)' : ''}'),
      ));
    }
  }

  void _openProject(BuildContext context, Project project, PackInfo pack) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkspaceRoute(
        db: db,
        project: project,
        pack: pack,
        pickClip: pickClip,
        playerFactory: playerFactory,
        analysisRunner: analysisRunner,
      ),
    ));
  }

  Future<void> _newReview(BuildContext context, PackInfo pack) async {
    final now = DateTime.now();
    final project = Project(
      projectId: const Uuid().v4(),
      name: 'Review ${_shortDate(now)}',
    );
    await db.saveProject(project);
    if (context.mounted) _openProject(context, project, pack);
  }

  Future<void> _reopen(
      BuildContext context, String projectId, PackInfo pack) async {
    final project = await db.loadProject(projectId);
    if (project != null && context.mounted) {
      _openProject(context, project, pack);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<String?>(
        stream: db.watchSetting(AppDatabase.activeEventKey),
        builder: (context, snap) =>
            _build(context, activePack(_packs, snap.data)),
      );

  Widget _eventPicker(BuildContext context, PackInfo pack) {
    final all = PackInfo.all(_packs);
    if (all.length < 2) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      key: const Key('event-picker'),
      tooltip: 'Choose the event',
      initialValue: pack.key,
      onSelected: (k) => db.setSetting(AppDatabase.activeEventKey, k),
      itemBuilder: (_) => [
        for (final p in all)
          PopupMenuItem(
              key: Key('event-${p.key}'), value: p.key, child: Text(p.label)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(pack.event.label, key: const Key('active-event')),
          const Icon(Icons.arrow_drop_down),
        ]),
      ),
    );
  }

  Widget _build(BuildContext context, PackInfo pack) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          _eventPicker(context, pack),
          IconButton(
            key: const Key('build-profile'),
            tooltip: 'Build a profile',
            icon: const Icon(Icons.person_add_alt),
            onPressed: () => _buildProfile(context, pack),
          ),
          IconButton(
            key: const Key('import-profile'),
            tooltip: 'Import profile',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: () => _import(context),
          ),
        ],
      ),
      body: StreamBuilder<List<ProjectRow>>(
        stream: db.watchProjects(),
        builder: (context, projectSnap) => StreamBuilder<List<ProfileRow>>(
          stream: db.watchProfiles(),
          builder: (context, profileSnap) {
            final projects = projectSnap.data ?? const <ProjectRow>[];
            final profiles = profileSnap.data ?? const <ProfileRow>[];
            if (projects.isEmpty && profiles.isEmpty) {
              return _EmptyLibrary(onImport: () => _import(context));
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (projects.isNotEmpty) ...[
                  _SectionHeader('Reviews', theme: theme),
                  for (final p in projects)
                    ListTile(
                      key: Key('project-${p.projectId}'),
                      leading: const Icon(Icons.video_library_outlined),
                      title: Text(p.name),
                      subtitle: Text('Edited ${_shortDate(p.updatedAt)}'),
                      onTap: () => _reopen(context, p.projectId, pack),
                    ),
                ],
                if (profiles.isNotEmpty) ...[
                  _SectionHeader('Profiles', theme: theme),
                  for (final p in profiles) _ProfileTile(profile: p),
                ],
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('open-workspace'),
        icon: const Icon(Icons.add),
        label: const Text('New review'),
        onPressed: () => _newReview(context, pack),
      ),
    );
  }
}

String _shortDate(DateTime t) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final l = t.toLocal();
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  return '${months[l.month - 1]} ${l.day}, $hh:$mm';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.primary)),
      );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined,
                size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('Add a clip to start', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Start a review to watch and compare clips side by side.\n'
              'Profiles are optional.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import a profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.profile});

  final ProfileRow profile;

  @override
  Widget build(BuildContext context) {
    final ready = profile.minClipsMet && profile.selfConsistencyPassed;
    return ListTile(
      key: Key('profile-${profile.profileId}-${profile.version}'),
      leading: CircleAvatar(
        child: Text(profile.coachName.isEmpty
            ? '?'
            : profile.coachName.characters.first.toUpperCase()),
      ),
      title: Text('${profile.coachName} · v${profile.version}'),
      subtitle: Text(
        '${profile.packId} / ${profile.eventId}\n'
        '${profile.sourceClipCount} clips · ${profile.metricCount} metrics · '
        'schema ${profile.metricSchemaVersion}',
      ),
      isThreeLine: true,
      trailing: Chip(
        label: Text(ready ? 'Ready' : 'Not ready'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
