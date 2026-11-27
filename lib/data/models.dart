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

/// How a task's notifications get your attention.
enum AlertStyle {
  sound('Sound', 'Sound, vibration and a pop-up banner'),
  vibrate('Vibrate', 'Vibration only, no sound'),
  silent('Silent', 'Shows quietly in the notification list');

  const AlertStyle(this.label, this.description);
  final String label;
  final String description;

  static AlertStyle parse(String? value) =>
      values.firstWhere((s) => s.name == value, orElse: () => sound);
}

/// The sound a task's notifications play (when the style is [AlertStyle.sound]).
enum AlertSound {
  standard('default', 'Phone default'),
  chime('chime', 'Chime'),
  bell('bell', 'Bell'),
  beep('beep', 'Beep'),
  digital('digital', 'Digital');

  const AlertSound(this.key, this.label);

  /// Stored value, and the Android sound file name in res/raw.
  final String key;
  final String label;

  static AlertSound parse(String? value) =>
      values.firstWhere((s) => s.key == value, orElse: () => standard);
}

/// How a task repeats. Finishing a repeating task creates the next one.
enum RepeatRule {
  none('none', 'Does not repeat', ''),
  daily('daily', 'Every day', 'Daily'),
  weekly('weekly', 'Every week', 'Weekly'),
  monthly('monthly', 'Every month', 'Monthly'),
  days('days', 'On chosen days', 'Custom days');

  const RepeatRule(this.key, this.label, this.shortLabel);
  final String key;
  final String label;
  final String shortLabel;

  static RepeatRule parse(String? value) =>
      values.firstWhere((r) => r.key == value, orElse: () => none);
}

/// Minutes-before-start options for the early heads-up (0 = off).
const earlyReminderOptions = [0, 5, 10, 15, 30, 60];

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
    this.startMessage = '',
    this.endMessage = '',
    this.earlyMinutes = 0,
    this.alertStyle = AlertStyle.sound,
    this.alertSound = AlertSound.standard,
    this.repeat = RepeatRule.none,
    this.repeatDays = 0,
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
    String startMessage = '',
    String endMessage = '',
    int earlyMinutes = 0,
    AlertStyle alertStyle = AlertStyle.sound,
    AlertSound alertSound = AlertSound.standard,
    RepeatRule repeat = RepeatRule.none,
    int repeatDays = 0,
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
    startMessage: startMessage,
    endMessage: endMessage,
    earlyMinutes: earlyMinutes,
    alertStyle: alertStyle,
    alertSound: alertSound,
    repeat: repeat,
    repeatDays: repeatDays,
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
      startMessage: json['start_message'] as String? ?? '',
      endMessage: json['end_message'] as String? ?? '',
      earlyMinutes: (json['early_minutes'] as num?)?.toInt() ?? 0,
      alertStyle: AlertStyle.parse(json['alert_style'] as String?),
      alertSound: AlertSound.parse(json['alert_sound'] as String?),
      repeat: RepeatRule.parse(json['repeat_rule'] as String?),
      repeatDays: (json['repeat_days'] as num?)?.toInt() ?? 0,
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

  /// Custom notification text; empty means use the standard wording.
  final String startMessage;
  final String endMessage;

  /// Minutes before [startsAt] for an extra heads-up; 0 means none.
  final int earlyMinutes;
  final AlertStyle alertStyle;
  final AlertSound alertSound;

  final RepeatRule repeat;

  /// Weekdays for [RepeatRule.days] as a bit mask: bit 0 = Monday ... bit 6 =
  /// Sunday.
  final int repeatDays;

  /// Whether [RepeatRule.days] includes [weekday] (1 = Monday ... 7 = Sunday).
  bool repeatsOn(int weekday) => repeatDays & (1 << (weekday - 1)) != 0;

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
    'start_message': startMessage,
    'end_message': endMessage,
    'early_minutes': earlyMinutes,
    'alert_style': alertStyle.name,
    'alert_sound': alertSound.key,
    'repeat_rule': repeat.key,
    'repeat_days': repeatDays,
  };

  /// Pass `null` for [projectId], [dueAt], [startsAt] or [endsAt] to clear them.
  Task copyWith({
    String? title,
    String? notes,
    Priority? priority,
    bool? done,
    bool? remind,
    String? startMessage,
    String? endMessage,
    int? earlyMinutes,
    AlertStyle? alertStyle,
    AlertSound? alertSound,
    RepeatRule? repeat,
    int? repeatDays,
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
    startMessage: startMessage ?? this.startMessage,
    endMessage: endMessage ?? this.endMessage,
    earlyMinutes: earlyMinutes ?? this.earlyMinutes,
    alertStyle: alertStyle ?? this.alertStyle,
    alertSound: alertSound ?? this.alertSound,
    repeat: repeat ?? this.repeat,
    repeatDays: repeatDays ?? this.repeatDays,
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
