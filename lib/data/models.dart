/// Plain data classes mirroring the Supabase tables.
library;

const Object _keep = Object();

class Project {
  const Project({required this.id, required this.name, required this.color});

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    name: json['name'] as String,
    color: (json['color'] as num).toInt(),
  );

  final String id;
  final String name;
  final int color;

  Project copyWith({String? name, int? color}) =>
      Project(id: id, name: name ?? this.name, color: color ?? this.color);
}

class Tag {
  const Tag({required this.id, required this.name, required this.color});

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
    id: json['id'] as String,
    name: json['name'] as String,
    color: (json['color'] as num).toInt(),
  );

  final String id;
  final String name;
  final int color;

  Tag copyWith({String? name, int? color}) =>
      Tag(id: id, name: name ?? this.name, color: color ?? this.color);
}

enum Priority {
  none('None'),
  low('Low'),
  medium('Medium'),
  high('High');

  const Priority(this.label);
  final String label;
}

class Task {
  const Task({
    required this.id,
    required this.title,
    required this.createdAt,
    this.projectId,
    this.parentId,
    this.notes = '',
    this.priority = Priority.none,
    this.dueAt,
    this.done = false,
    this.completedAt,
    this.tagIds = const [],
    this.startsAt,
    this.endsAt,
    this.remind = true,
  });

  /// A task that has not been saved yet. The database assigns the real id.
  factory Task.draft({
    required String title,
    String? projectId,
    String? parentId,
    String notes = '',
    Priority priority = Priority.none,
    DateTime? dueAt,
    List<String> tagIds = const [],
    DateTime? startsAt,
    DateTime? endsAt,
    bool remind = true,
  }) => Task(
    id: '',
    title: title,
    createdAt: DateTime.now(),
    projectId: projectId,
    parentId: parentId,
    notes: notes,
    priority: priority,
    dueAt: dueAt,
    tagIds: tagIds,
    startsAt: startsAt,
    endsAt: endsAt,
    remind: remind,
  );

  factory Task.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) => json[key] == null
        ? null
        : DateTime.parse(json[key] as String).toLocal();
    final links = json['task_tags'] as List<dynamic>? ?? const [];
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: date('created_at')!,
      projectId: json['project_id'] as String?,
      parentId: json['parent_id'] as String?,
      notes: json['notes'] as String? ?? '',
      priority: Priority.values[(json['priority'] as num).toInt()],
      dueAt: date('due_at'),
      done: json['done'] as bool,
      completedAt: date('completed_at'),
      startsAt: date('starts_at'),
      endsAt: date('ends_at'),
      remind: json['remind'] as bool? ?? true,
      tagIds: [
        for (final link in links)
          (link as Map<String, dynamic>)['tag_id'] as String,
      ],
    );
  }

  final String id;
  final String title;
  final DateTime createdAt;
  final String? projectId;
  final String? parentId;
  final String notes;
  final Priority priority;

  /// Due date at local midnight (tasks have a due day, not a time).
  final DateTime? dueAt;
  final bool done;
  final DateTime? completedAt;
  final List<String> tagIds;

  /// Fixed time slot: when the work starts and when it must stop.
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// Whether to notify when the time slot starts and ends.
  final bool remind;

  bool get isSubtask => parentId != null;

  bool get hasTimeSlot => startsAt != null && endsAt != null;

  /// True while the current time is inside the task's time slot.
  bool isInProgress(DateTime now) =>
      !done && hasTimeSlot && !now.isBefore(startsAt!) && now.isBefore(endsAt!);

  bool isOverdue(DateTime today) =>
      !done && dueAt != null && dueAt!.isBefore(today);

  /// Columns written to the `tasks` table (tags live in `task_tags`).
  Map<String, dynamic> toRow() => {
    'title': title,
    'project_id': projectId,
    'parent_id': parentId,
    'notes': notes,
    'priority': priority.index,
    'due_at': dueAt?.toUtc().toIso8601String(),
    'done': done,
    'starts_at': startsAt?.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
    'remind': remind,
  };

  /// Pass `null` for [projectId], [dueAt], [startsAt] or [endsAt] to clear them.
  Task copyWith({
    String? title,
    String? notes,
    Priority? priority,
    bool? done,
    bool? remind,
    List<String>? tagIds,
    Object? projectId = _keep,
    Object? dueAt = _keep,
    Object? completedAt = _keep,
    Object? startsAt = _keep,
    Object? endsAt = _keep,
  }) => Task(
    id: id,
    createdAt: createdAt,
    parentId: parentId,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    priority: priority ?? this.priority,
    done: done ?? this.done,
    remind: remind ?? this.remind,
    tagIds: tagIds ?? this.tagIds,
    startsAt: identical(startsAt, _keep)
        ? this.startsAt
        : startsAt as DateTime?,
    endsAt: identical(endsAt, _keep) ? this.endsAt : endsAt as DateTime?,
    projectId: identical(projectId, _keep)
        ? this.projectId
        : projectId as String?,
    dueAt: identical(dueAt, _keep) ? this.dueAt : dueAt as DateTime?,
    completedAt: identical(completedAt, _keep)
        ? this.completedAt
        : completedAt as DateTime?,
  );
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// A photo or PDF saved on a task.
class Attachment {
  const Attachment({
    required this.id,
    required this.taskId,
    required this.name,
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
    id: json['id'] as String,
    taskId: json['task_id'] as String,
    name: json['name'] as String,
    path: json['path'] as String,
    mimeType: json['mime_type'] as String,
    sizeBytes: (json['size_bytes'] as num).toInt(),
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );

  final String id;
  final String taskId;
  final String name;

  /// Location in the private `attachments` storage bucket.
  final String path;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;

  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
