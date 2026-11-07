import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:analysis_engine/analysis_engine.dart' show PackDefinition;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;

import '../analysis/analysis_controller.dart';
import '../data/database.dart';
import '../design/sv_theme.dart';
import '../media/thumbnail_service.dart';
import '../packs/placeholder_pack.dart';
import '../workspace/project.dart' show Project;
import '../workspace/review_presentation.dart';
import 'workspace_route.dart';
import 'workspace_screen.dart';

/// A filmstrip over existing Projects, with existing package tools one level down.
class FootageLibraryScreen extends StatefulWidget {
  const FootageLibraryScreen({
    super.key,
    required this.db,
    required this.packs,
    required this.toolsBuilder,
    this.pickClip = pickClipFile,
    this.playerFactory = defaultStagePlayer,
    this.analysisRunner,
    this.thumbnails,
    this.sourceSignature = presentationSignature,
  });
  final AppDatabase db;
  final List<PackDefinition> packs;
  final WidgetBuilder toolsBuilder;
  final ClipPathPicker pickClip;
  final StagePlayerFactory playerFactory;
  final AnalysisRunner? analysisRunner;
  final ThumbnailService? thumbnails;
  final Future<String?> Function(String path) sourceSignature;
  @override
  State<FootageLibraryScreen> createState() => _FootageLibraryScreenState();
}

class _FootageLibraryScreenState extends State<FootageLibraryScreen> {
  late final _previews = widget.thumbnails ?? ThumbnailService();
  late final _projects = widget.db.watchProjects();
  late final _visits = ReviewStateStore(widget.db).watchVisits();
  late final _event = widget.db.watchSetting(AppDatabase.activeEventKey);
  final _scroll = ScrollController();
  bool _opening = false;
  String? _error;
  @override
  void dispose() {
    _scroll.dispose();
    if (widget.thumbnails == null) unawaited(_previews.dispose());
    super.dispose();
  }

  List<PackInfo> get _events => PackInfo.all(widget.packs);

  Future<void> _open(
    Project project, {
    String? initialClip,
    PackInfo? event,
  }) async {
    _previews.suspend();
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkspaceRoute(
            db: widget.db,
            project: project,
            pack: event ?? placeholderPack,
            availablePacks: widget.packs,
            initialClipPath: initialClip,
            initialEventConfirmed: initialClip != null && event != null,
            pickClip: widget.pickClip,
            playerFactory: widget.playerFactory,
            analysisRunner: widget.analysisRunner,
            sourceSignature: widget.sourceSignature,
          ),
        ),
      );
    } finally {
      _previews.resume();
    }
  }

  Future<void> _add(PackInfo? event) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final path = await widget.pickClip();
      if (path == null || !mounted) return;
      await _open(
        Project(
          projectId: const Uuid().v4(),
          name: p.basenameWithoutExtension(path),
        ),
        initialClip: path,
        event: event,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not open that clip. Your files are unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _reopen(ProjectRow row) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final project = await widget.db.loadProject(row.projectId);
      if (project != null && mounted) await _open(project);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not read this saved review. Its data has not been changed.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _chooseEvent(String? selected) async {
    final key = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'For new reviews',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              title: const Text('Just video'),
              selected: selected == null,
              subtitle: const Text('Choose an event later, when you need it.'),
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final event in _events)
              ListTile(
                key: Key('event-${event.key}'),
                title: Text(event.label),
                selected: selected == event.key,
                onTap: () => Navigator.pop(context, event.key),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (key == null) return;
    try {
      await widget.db.setSetting(AppDatabase.activeEventKey, key);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the event preference.');
      }
    }
  }

  void _nudge(double direction) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + direction * 300).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: StreamBuilder<String?>(
        stream: _event,
        builder: (context, eventSnap) {
          final selected = _events
              .where((e) => e.key == eventSnap.data)
              .firstOrNull;
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final padding = wide ? 24.0 : 16.0;
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final stripHeight =
                  (constraints.maxHeight * 0.58).clamp(260.0, 460.0) +
                  math.max(0.0, scale - 1) * 70;
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(padding),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const SvWordmark(),
                          TextButton(
                            key: const Key('event-picker'),
                            onPressed: () => _chooseEvent(selected?.key),
                            child: Text(
                              selected?.event.label ?? 'Just video',
                              key: const Key('active-event'),
                            ),
                          ),
                          TextButton.icon(
                            key: const Key('library-tools'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: widget.toolsBuilder,
                              ),
                            ),
                            icon: const Icon(Icons.tune),
                            label: const Text('Profiles & tools'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        padding,
                        wide ? 32 : 8,
                        padding,
                        24,
                      ),
                      child: Text(
                        'Your footage',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(fontSize: wide ? 40 : 30),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: EdgeInsets.all(padding),
                        child: Text(_error!),
                      ),
                    StreamBuilder<Map<String, DateTime>>(
                      stream: _visits,
                      builder: (context, visitSnapshot) =>
                          StreamBuilder<List<ProjectRow>>(
                            stream: _projects,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'Saved reviews could not be read. Original videos are unchanged.',
                                  ),
                                );
                              }
                              if (!snapshot.hasData) {
                                return const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('Opening your library…'),
                                );
                              }
                              final visits =
                                  visitSnapshot.data ??
                                  const <String, DateTime>{};
                              final rows = [...snapshot.data!];
                              rows.sort((a, b) {
                                final byDate =
                                    (visits[b.projectId] ?? b.updatedAt)
                                        .compareTo(
                                          visits[a.projectId] ?? a.updatedAt,
                                        );
                                return byDate != 0
                                    ? byDate
                                    : a.projectId.compareTo(b.projectId);
                              });
                              if (rows.isEmpty) {
                                return Padding(
                                  padding: EdgeInsets.all(padding),
                                  child: Container(
                                    constraints: BoxConstraints(
                                      minHeight: stripHeight,
                                    ),
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.video_library_outlined,
                                            size: 40,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Add a clip to start',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge,
                                          ),
                                          const SizedBox(height: 24),
                                          FilledButton.icon(
                                            key: const Key('open-workspace'),
                                            onPressed: _opening
                                                ? null
                                                : () => _add(selected),
                                            icon: const Icon(Icons.add),
                                            label: Text(
                                              _opening
                                                  ? 'Opening…'
                                                  : 'Add clip',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final recentWidth = wide
                                  ? 380.0
                                  : (constraints.maxWidth - padding * 2) * 0.72;
                              return Column(
                                children: [
                                  SizedBox(
                                    height: stripHeight,
                                    child: Scrollbar(
                                      controller: _scroll,
                                      thumbVisibility: wide,
                                      child: ListView.builder(
                                        key: const PageStorageKey('filmstrip'),
                                        controller: _scroll,
                                        scrollDirection: Axis.horizontal,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: padding,
                                          vertical: 8,
                                        ),
                                        itemCount: rows.length + 1,
                                        itemBuilder: (context, index) {
                                          if (index == 0) {
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                right: 16,
                                              ),
                                              child: SizedBox(
                                                width: 80,
                                                child: OutlinedButton(
                                                  key: const Key(
                                                    'open-workspace',
                                                  ),
                                                  onPressed: _opening
                                                      ? null
                                                      : () => _add(selected),
                                                  child: const Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.add, size: 30),
                                                      SizedBox(height: 12),
                                                      Text(
                                                        'Add\nclip',
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                          final row = rows[index - 1];
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              right: 16,
                                            ),
                                            child: SizedBox(
                                              width: math.max(
                                                180.0,
                                                recentWidth *
                                                    (index == 1 ? 1 : 0.82),
                                              ),
                                              child: ReviewFilmTile(
                                                key: Key(
                                                  'project-${row.projectId}',
                                                ),
                                                row: row,
                                                previews: _previews,
                                                viewedAt: visits[row.projectId],
                                                onOpen: _opening
                                                    ? null
                                                    : () => _reopen(row),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  if (wide)
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: padding,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            onPressed: () => _nudge(-1),
                                            tooltip: 'Previous reviews',
                                            icon: const Icon(
                                              Icons.chevron_left,
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () => _nudge(1),
                                            tooltip: 'More reviews',
                                            icon: const Icon(
                                              Icons.chevron_right,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class ReviewFilmTile extends StatefulWidget {
  const ReviewFilmTile({
    super.key,
    required this.row,
    required this.previews,
    required this.onOpen,
    this.viewedAt,
  });
  final ProjectRow row;
  final DateTime? viewedAt;
  final ThumbnailService previews;
  final VoidCallback? onOpen;
  @override
  State<ReviewFilmTile> createState() => _ReviewFilmTileState();
}

class _ReviewFilmTileState extends State<ReviewFilmTile> {
  PosterRequest? _poster;
  String? _path;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ReviewFilmTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.json != widget.row.json) _load();
  }

  void _load() {
    String? path;
    try {
      final project = Project.fromJson(
        Map<String, Object?>.from(jsonDecode(widget.row.json) as Map),
      );
      path =
          (project.clipById(project.workspace.stageAClipId) ??
                  project.clipById(project.workspace.stageBClipId) ??
                  project.clips.firstOrNull)
              ?.path;
    } catch (_) {
      /* Preserve unreadable projects; never silently delete them. */
    }
    if (_path == path && _poster != null) return;
    _poster?.cancel();
    _path = path;
    _poster = path == null ? null : widget.previews.request(path);
  }

  @override
  void dispose() {
    _poster?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Open ${widget.row.name}',
    child: Material(
      color: SvColors.graphite,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FutureBuilder(
                future: _poster?.result,
                builder: (context, snapshot) {
                  if (snapshot.data != null) {
                    return Image.file(
                      snapshot.data!,
                      fit: BoxFit.cover,
                      cacheWidth: 512,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => _placeholder(),
                    );
                  }
                  return _placeholder();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.row.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: SvColors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.viewedAt == null ? 'Edited' : 'Viewed'} ${_date(widget.viewedAt ?? widget.row.updatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: const Color(0xFFAFB8BF)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _placeholder() => const Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_circle_outline, size: 40, color: SvColors.white),
          SizedBox(height: 12),
          Text('Open review', style: TextStyle(color: SvColors.white)),
        ],
      ),
    ),
  );
  String _date(DateTime value) {
    final d = value.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
