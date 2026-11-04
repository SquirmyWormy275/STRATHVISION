import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'dart:io';

import 'dart:convert';

import 'package:analysis_engine/analysis_engine.dart'
    show DriftPoint, PackDefinition, Profile, summarizeDrift;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../analysis/analysis_controller.dart';
import '../data/database.dart';
import '../packs/pack_registry.dart';
import '../packs/placeholder_pack.dart';
import '../profiles/builder_controller.dart';
import '../profiles/profile_package.dart';
import '../workspace/project.dart';
import '../profiles/clip_probe.dart';
import '../profiles/profile_export.dart';
import '../workbench/claude_compiler.dart';
import '../workbench/workbench_controller.dart';
import 'profile_builder_screen.dart';
import '../profiles/inbox.dart';
import '../profiles/package_exchange.dart';
import '../profiles/profile_health.dart';
import '../workbench/carne_controller.dart';
import 'drift_screen.dart';
import 'carne_screen.dart';
import 'workbench_screen.dart';
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
    this.workbench,
    this.carne,
    this.saveFile = savePackageCopy,
    this.pickFolder = pickInboxFolder,
    this.profileStore,
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

  /// Builds the workbench for a profile. Null: the default on desktop,
  /// hidden on phones (phones load patches and adapters, never edit).
  final WorkbenchFactory? workbench;

  /// Builds the CARNE ASADA playground (desktop default when null).
  final CarneFactory? carne;

  /// Saves an exported package wherever the user chooses.
  final Future<String?> Function(String fileName, List<int> bytes) saveFile;

  /// Picks the shared inbox folder.
  final Future<String?> Function() pickFolder;

  /// Where imported inbox packages are copied (default: app support).
  final Future<Directory> Function()? profileStore;

  Future<Directory> _store() async => profileStore != null
      ? profileStore!()
      : Directory(p.join((await getApplicationSupportDirectory()).path, 'profiles'));

  /// Export with an explicit choice and a summary before writing
  /// (DECISIONS.md). Default: coaching profile only.
  Future<void> _export(BuildContext context, ProfileRow row) async {
    final messenger = ScaffoldMessenger.of(context);
    final event = _workbenchFor(row);
    final attributes = event == null
        ? const <String>[]
        : [...event.topAttributes, ...event.moreAttributes];
    try {
      final plan = await showDialog<ExportPlan>(
        context: context,
        builder: (_) => _ExportDialog(
            plan: (choice) => planExport(db, row, choice, attributes: attributes)),
      );
      if (plan == null) return;
      final where = await saveFile(plan.fileName, plan.zip());
      if (where != null) {
        messenger.showSnackBar(SnackBar(
            content: Text('Saved ${plan.fileName}. Send it like any file.')));
      }
    } on AnalysisError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _trend(BuildContext context, ProfileRow row) async {
    final navigator = Navigator.of(context);
    final rows = await db.comparisonsForProfile(row.profileId);
    final summary = summarizeDrift([
      for (final r in rows)
        DriftPoint.fromResult(r.createdAt, jsonDecode(r.json) as Map<String, Object?>),
    ]);
    await navigator.push(MaterialPageRoute<void>(
      builder: (_) => DriftScreen(
          title: '${row.coachName} · ${_workbenchFor(row)?.event.label ?? row.eventId}',
          summary: summary,
          pack: _workbenchFor(row)),
    ));
  }

  Future<void> _setInbox(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final folder = await pickFolder();
    if (folder == null) return;
    await db.setSetting(inboxFolderKey, folder);
    final n = await scanInbox(db, folder, await _store());
    messenger.showSnackBar(SnackBar(
        content: Text(n == 0
            ? 'Inbox set. New packages dropped there will appear here.'
            : 'Inbox set. Added $n ${n == 1 ? 'package' : 'packages'}.')));
  }

  Future<List<HealthItem>> _health(ProfileRow row) async {
    final bundle = await readProfileBundle(row.sourcePath);
    final n = (await db.comparisonsForProfile(row.profileId)).length;
    return profileHealth(bundle: bundle, events: PackInfo.all(_packs), comparisons: n);
  }

  CarneFactory get _carne => carne ?? defaultCarne(db);

  Future<void> _openCarne(BuildContext context, ProfileRow row, PackInfo pack,
      WorkbenchController wb) async {
    final controller = await _carne(row, pack, wb);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          CarneScreen(controller: controller, title: '${row.coachName} · v${row.version}'),
    ));
    controller.dispose();
  }

  WorkbenchFactory? get _workbench =>
      workbench ??
      (Platform.isLinux || Platform.isMacOS || Platform.isWindows
          ? defaultWorkbench(db)
          : null);

  Future<void> _openWorkbench(
      BuildContext context, ProfileRow row, PackInfo pack) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final WorkbenchController controller;
    try {
      controller = await _workbench!(row, pack);
    } on AnalysisError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    await navigator.push(MaterialPageRoute<void>(
      builder: (ctx) => WorkbenchScreen(
          controller: controller,
          title: '${row.coachName} · v${row.version}',
          pickClips: pickClips,
          onCarne: () => _openCarne(ctx, row, pack, controller)),
    ));
    controller.dispose();
  }

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
      final installed = (await db.allProfiles()).where((r) => r.profileId == meta.profileId);
      ImportChoice? choice;
      if (installed.isNotEmpty) {
        if (!context.mounted) return;
        choice = await showDialog<ImportChoice>(
          context: context,
          builder: (_) => _ImportDialog(
              name: '${meta.coachName} · v${meta.version}',
              have: [for (final r in installed) 'v${r.version}']),
        );
        if (choice == null) return;
      }
      final msg = await applyImport(db, path, meta, choice, _store);
      messenger.showSnackBar(SnackBar(content: Text(msg)));
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

  /// The pack event a profile belongs to, if installed.
  PackInfo? _workbenchFor(ProfileRow row) => PackInfo.all(_packs)
      .where((x) => x.packId == row.packId && x.eventId == row.eventId)
      .firstOrNull;

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
          PopupMenuButton<String>(
            key: const Key('library-menu'),
            onSelected: (v) {
              if (v == 'inbox') _setInbox(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  key: Key('menu-inbox'), value: 'inbox', child: Text('Inbox folder…')),
            ],
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
                  for (final row in profiles)
                    _ProfileTile(
                      profile: row,
                      health: _health(row),
                      onTrend: () => _trend(context, row),
                      onExport: () => _export(context, row),
                      onWorkbench: _workbenchFor(row) == null || _workbench == null
                          ? null
                          : () => _openWorkbench(context, row, _workbenchFor(row)!),
                    ),
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
  const _ProfileTile({
    required this.profile,
    this.onWorkbench,
    this.onTrend,
    this.onExport,
    this.health,
  });

  final ProfileRow profile;
  final VoidCallback? onWorkbench;
  final VoidCallback? onTrend;
  final VoidCallback? onExport;
  final Future<List<HealthItem>>? health;

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
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          '${profile.packId} / ${profile.eventId}\n'
          '${profile.sourceClipCount} clips · ${profile.metricCount} metrics · '
          'schema ${profile.metricSchemaVersion}',
        ),
        if (health != null)
          FutureBuilder<List<HealthItem>>(
            future: health,
            builder: (context, snap) {
              final items = snap.data;
              if (items == null) return const SizedBox.shrink();
              final scheme = Theme.of(context).colorScheme;
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 10, runSpacing: 2, children: [
                  for (final h in items)
                    Row(
                      key: Key('health-${h.label}'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(h.ok ? Icons.check_circle_outline : Icons.error_outline,
                            size: 14, color: h.ok ? scheme.primary : scheme.error),
                        const SizedBox(width: 3),
                        Text(h.label, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                ]),
              );
            },
          ),
      ]),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Chip(
          label: Text(ready ? 'Ready' : 'Not ready'),
          visualDensity: VisualDensity.compact,
        ),
        if (onTrend != null)
          IconButton(
            key: Key('trend-${profile.profileId}-${profile.version}'),
            tooltip: 'Match trend',
            icon: const Icon(Icons.show_chart),
            onPressed: onTrend,
          ),
        if (onExport != null)
          IconButton(
            key: Key('export-${profile.profileId}-${profile.version}'),
            tooltip: 'Export package',
            icon: const Icon(Icons.ios_share),
            onPressed: onExport,
          ),
        if (onWorkbench != null && ready)
          IconButton(
            key: Key('workbench-${profile.profileId}-${profile.version}'),
            tooltip: 'Workbench',
            icon: const Icon(Icons.tune),
            onPressed: onWorkbench,
          ),
      ]),
    );
  }
}

typedef WorkbenchFactory = Future<WorkbenchController> Function(
    ProfileRow row, PackInfo pack);

/// Production workbench: reads the package, probes and analyzes clips off
/// the UI isolate, compiles with Claude when ANTHROPIC_API_KEY is set, and
/// stores each saved version under app support.
WorkbenchFactory defaultWorkbench(AppDatabase db) => (row, pack) async {
      final bundle = await readProfileBundle(row.sourcePath);
      return WorkbenchController(
        pack: pack.analysisPack,
        bundle: bundle,
        probe: probeClip,
        analyze: isolateProbeAnalyzer(pack.analysisPack),
        compiler: ClaudeAdapterCompiler.fromEnvironment(),
        write: (Profile profile, patches, adapters) async {
          final support = await getApplicationSupportDirectory();
          final path = await storeProfilePackage(
              profile, Directory(p.join(support.path, 'profiles')),
              patches: patches, adapters: adapters);
          await db.saveProfile(await readProfilePackage(path), path);
          return path;
        },
      );
    };

typedef CarneFactory = Future<CarneController> Function(
    ProfileRow row, PackInfo pack, WorkbenchController workbench);

/// Production playground: strokes analyzed off the UI isolate, marks from
/// every project on the same clip file, versions stored under app support.
CarneFactory defaultCarne(AppDatabase db) => (row, pack, wb) async => CarneController(
      pack: pack.analysisPack,
      attributes: [...pack.topAttributes, ...pack.moreAttributes],
      bundle: wb.bundle,
      probe: probeClip,
      analyze: isolateStrokeAnalyzer(pack.analysisPack),
      marks: db.marksForPath,
      phaseLabel: pack.phaseLabel,
      metricLabel: pack.metricLabel,
      write: (Profile profile, patches, adapters, research) async {
        final support = await getApplicationSupportDirectory();
        final path = await storeProfilePackage(
            profile, Directory(p.join(support.path, 'profiles')),
            patches: patches, adapters: adapters, research: research);
        await db.saveProfile(await readProfilePackage(path), path);
        return path;
      },
    );

Future<String?> pickInboxFolder() =>
    FilePicker.getDirectoryPath(dialogTitle: 'Choose a shared inbox folder');

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.plan});
  final Future<ExportPlan> Function(ExportChoice choice) plan;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  ExportChoice _choice = ExportChoice.profileOnly;
  late Future<ExportPlan> _plan = widget.plan(_choice);

  void _pick(ExportChoice? c) {
    if (c == null) return;
    setState(() {
      _choice = c;
      _plan = widget.plan(c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Export package'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          RadioGroup<ExportChoice>(
            groupValue: _choice,
            onChanged: _pick,
            child: Column(children: [
              for (final c in ExportChoice.values)
                RadioListTile<ExportChoice>(
                  key: Key('export-choice-${c.name}'),
                  contentPadding: EdgeInsets.zero,
                  value: c,
                  title: Text(c.label),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Text('This will write:', style: theme.textTheme.labelLarge),
          FutureBuilder<ExportPlan>(
            future: _plan,
            builder: (context, snap) => snap.data == null
                ? const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
                : Column(
                    key: const Key('export-summary'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final l in snap.data!.summary) Text('· $l')],
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FutureBuilder<ExportPlan>(
          future: _plan,
          builder: (context, snap) => FilledButton(
            key: const Key('export-save'),
            onPressed: snap.data == null ? null : () => Navigator.pop(context, snap.data),
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

class _ImportDialog extends StatelessWidget {
  const _ImportDialog({required this.name, required this.have});
  final String name;
  final List<String> have;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('$name is already here'),
        content: Text('You have ${have.join(', ')}. Replace removes those; Keep both '
            'installs it alongside; Merge also brings in its marks and match history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          for (final c in ImportChoice.values)
            TextButton(
              key: Key('import-${c.name}'),
              onPressed: () => Navigator.pop(context, c),
              child: Text(c.label),
            ),
        ],
      );
}
