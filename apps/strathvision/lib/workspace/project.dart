// Project model matching docs/INTERFACES.md "Project". Immutable value types;
// toJson/fromJson round-trip the contract exactly.

String _iso(DateTime t) => t.toUtc().toIso8601String();
DateTime _date(Object? v) => DateTime.parse(v as String);

class Clip {
  const Clip({
    required this.clipId,
    required this.path,
    required this.displayName,
    required this.addedAt,
  });

  final String clipId;
  final String path;
  final String displayName;
  final DateTime addedAt;

  Map<String, Object?> toJson() => {
        'clip_id': clipId,
        'path': path,
        'display_name': displayName,
        'added_at': _iso(addedAt),
      };

  factory Clip.fromJson(Map<String, Object?> j) => Clip(
        clipId: j['clip_id'] as String,
        path: j['path'] as String,
        displayName: j['display_name'] as String,
        addedAt: _date(j['added_at']),
      );
}

class SyncRelationship {
  const SyncRelationship({
    required this.clipAId,
    required this.clipBId,
    required this.offsetMs,
    required this.createdAt,
  });

  final String clipAId;
  final String clipBId;

  /// position_b_ms - position_a_ms at the moment the sync point was set.
  final int offsetMs;
  final DateTime createdAt;

  bool pairs(String? a, String? b) => clipAId == a && clipBId == b;

  Map<String, Object?> toJson() => {
        'clip_a_id': clipAId,
        'clip_b_id': clipBId,
        'offset_ms': offsetMs,
        'created_at': _iso(createdAt),
      };

  factory SyncRelationship.fromJson(Map<String, Object?> j) => SyncRelationship(
        clipAId: j['clip_a_id'] as String,
        clipBId: j['clip_b_id'] as String,
        offsetMs: (j['offset_ms'] as num).toInt(),
        createdAt: _date(j['created_at']),
      );
}

enum MarkLabel { red, green }

enum MarkAuthor { athlete, coach }

class Mark {
  const Mark({
    required this.markId,
    required this.clipId,
    required this.timeMs,
    required this.attribute,
    required this.label,
    required this.author,
    required this.createdAt,
    this.strokeIndex,
  });

  final String markId;
  final String clipId;
  final int timeMs;
  final int? strokeIndex;
  final String attribute;
  final MarkLabel label;
  final MarkAuthor author;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'mark_id': markId,
        'clip_id': clipId,
        'time_ms': timeMs,
        'stroke_index': strokeIndex,
        'attribute': attribute,
        'label': label.name,
        'author': author.name,
        'created_at': _iso(createdAt),
      };

  factory Mark.fromJson(Map<String, Object?> j) => Mark(
        markId: j['mark_id'] as String,
        clipId: j['clip_id'] as String,
        timeMs: (j['time_ms'] as num).toInt(),
        strokeIndex: (j['stroke_index'] as num?)?.toInt(),
        attribute: j['attribute'] as String,
        label: MarkLabel.values.byName(j['label'] as String),
        author: MarkAuthor.values.byName(j['author'] as String),
        createdAt: _date(j['created_at']),
      );
}

class Annotation {
  const Annotation({
    required this.annotationId,
    required this.clipId,
    required this.timeMs,
    required this.text,
    required this.createdAt,
  });

  final String annotationId;
  final String clipId;
  final int timeMs;
  final String text;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'annotation_id': annotationId,
        'clip_id': clipId,
        'time_ms': timeMs,
        'text': text,
        'created_at': _iso(createdAt),
      };

  factory Annotation.fromJson(Map<String, Object?> j) => Annotation(
        annotationId: j['annotation_id'] as String,
        clipId: j['clip_id'] as String,
        timeMs: (j['time_ms'] as num).toInt(),
        text: j['text'] as String,
        createdAt: _date(j['created_at']),
      );
}

class WorkspaceState {
  const WorkspaceState({
    this.stageAClipId,
    this.stageBClipId,
    this.mirrorB = false,
    this.playbackRate = 1.0,
    this.locked = false,
  });

  final String? stageAClipId;
  final String? stageBClipId;
  final bool mirrorB;
  final double playbackRate;
  final bool locked;

  WorkspaceState copyWith({
    String? Function()? stageAClipId,
    String? Function()? stageBClipId,
    bool? mirrorB,
    double? playbackRate,
    bool? locked,
  }) =>
      WorkspaceState(
        stageAClipId: stageAClipId != null ? stageAClipId() : this.stageAClipId,
        stageBClipId: stageBClipId != null ? stageBClipId() : this.stageBClipId,
        mirrorB: mirrorB ?? this.mirrorB,
        playbackRate: playbackRate ?? this.playbackRate,
        locked: locked ?? this.locked,
      );

  Map<String, Object?> toJson() => {
        'stage_a_clip_id': stageAClipId,
        'stage_b_clip_id': stageBClipId,
        'mirror_b': mirrorB,
        'playback_rate': playbackRate,
        'locked': locked,
      };

  factory WorkspaceState.fromJson(Map<String, Object?>? j) => j == null
      ? const WorkspaceState()
      : WorkspaceState(
          stageAClipId: j['stage_a_clip_id'] as String?,
          stageBClipId: j['stage_b_clip_id'] as String?,
          mirrorB: j['mirror_b'] as bool? ?? false,
          playbackRate: (j['playback_rate'] as num?)?.toDouble() ?? 1.0,
          locked: j['locked'] as bool? ?? false,
        );
}

class Project {
  const Project({
    required this.projectId,
    required this.name,
    this.clips = const [],
    this.syncRelationships = const [],
    this.annotations = const [],
    this.linkedProfileIds = const [],
    this.marks = const [],
    this.workspace = const WorkspaceState(),
  });

  final String projectId;
  final String name;
  final List<Clip> clips;
  final List<SyncRelationship> syncRelationships;
  final List<Annotation> annotations;
  final List<String> linkedProfileIds;
  final List<Mark> marks;
  final WorkspaceState workspace;

  Clip? clipById(String? id) =>
      id == null ? null : clips.where((c) => c.clipId == id).firstOrNull;

  /// The sync relationship for the clips currently on stage A and B.
  SyncRelationship? get activeSync => syncRelationships
      .where((s) => s.pairs(workspace.stageAClipId, workspace.stageBClipId))
      .firstOrNull;

  Project copyWith({
    String? name,
    List<Clip>? clips,
    List<SyncRelationship>? syncRelationships,
    List<Annotation>? annotations,
    List<String>? linkedProfileIds,
    List<Mark>? marks,
    WorkspaceState? workspace,
  }) =>
      Project(
        projectId: projectId,
        name: name ?? this.name,
        clips: clips ?? this.clips,
        syncRelationships: syncRelationships ?? this.syncRelationships,
        annotations: annotations ?? this.annotations,
        linkedProfileIds: linkedProfileIds ?? this.linkedProfileIds,
        marks: marks ?? this.marks,
        workspace: workspace ?? this.workspace,
      );

  Map<String, Object?> toJson() => {
        'project_id': projectId,
        'name': name,
        'clips': [for (final c in clips) c.toJson()],
        'sync_relationships': [for (final s in syncRelationships) s.toJson()],
        'annotations': [for (final a in annotations) a.toJson()],
        'linked_profile_ids': linkedProfileIds,
        'marks': [for (final m in marks) m.toJson()],
        'workspace': workspace.toJson(),
      };

  factory Project.fromJson(Map<String, Object?> j) {
    List<Map<String, Object?>> list(String k) =>
        ((j[k] as List?) ?? const []).cast<Map<String, Object?>>();
    return Project(
      projectId: j['project_id'] as String,
      name: j['name'] as String,
      clips: [for (final c in list('clips')) Clip.fromJson(c)],
      syncRelationships: [
        for (final s in list('sync_relationships')) SyncRelationship.fromJson(s)
      ],
      annotations: [for (final a in list('annotations')) Annotation.fromJson(a)],
      linkedProfileIds:
          ((j['linked_profile_ids'] as List?) ?? const []).cast<String>(),
      marks: [for (final m in list('marks')) Mark.fromJson(m)],
      workspace:
          WorkspaceState.fromJson(j['workspace'] as Map<String, Object?>?),
    );
  }
}
