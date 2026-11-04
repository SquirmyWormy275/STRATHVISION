import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../profiles/profile_package.dart';
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
  });

  final AppDatabase db;
  final ProfilePathPicker pickPath;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            key: const Key('import-profile'),
            tooltip: 'Import profile',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: () => _import(context),
          ),
        ],
      ),
      body: StreamBuilder<List<Profile>>(
        stream: db.watchProfiles(),
        builder: (context, snapshot) {
          final profiles = snapshot.data ?? const <Profile>[];
          if (profiles.isEmpty) return _EmptyLibrary(onImport: () => _import(context));
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: profiles.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _ProfileTile(profile: profiles[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('open-workspace'),
        icon: const Icon(Icons.video_library_outlined),
        label: const Text('Open workspace'),
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const WorkspaceScreen())),
      ),
    );
  }
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
            Icon(Icons.person_search_outlined,
                size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('No profiles yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Import a profile package to compare against later.\n'
              'You can review video without one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.profile});

  final Profile profile;

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
