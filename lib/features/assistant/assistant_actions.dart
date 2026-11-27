import 'package:intl/intl.dart';

import '../../core/palette.dart';
import '../../data/assistant_service.dart';
import '../../data/models.dart';
import '../../state/todo_store.dart';
import '../tasks/task_tile.dart' show formatDue;

/// A text snapshot of the user's tasks for the assistant, plus the short
/// references ("t1", "t2", ...) it uses to point at tasks.
typedef AssistantContext = ({String text, Map<String, Task> refs});

const _maxOpenTasks = 150;
const _maxDoneTasks = 15;

String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _hm(DateTime d) => DateFormat('HH:mm').format(d);

AssistantContext buildAssistantContext(TodoStore store) {
  final now = store.now;
  final refs = <String, Task>{};
  final buffer = StringBuffer()
    ..writeln('Now: ${DateFormat('EEEE yyyy-MM-dd HH:mm').format(now)}')
    ..writeln(
      'Projects: ${store.projects.isEmpty ? '(none)' : store.projects.map((p) => p.name).join(', ')}',
    );

  String line(Task t) {
    final ref = 't${refs.length + 1}';
    refs[ref] = t;
    final parts = <String>[ref, t.title];
    if (t.dueAt != null) parts.add('due ${_ymd(t.dueAt!)}');
    if (t.hasTimeSlot) parts.add('${_hm(t.startsAt!)}-${_hm(t.endsAt!)}');
    final project = store.projectById(t.projectId);
    if (project != null) parts.add('project ${project.name}');
    if (t.priority != Priority.none) parts.add('${t.priority.name} priority');
    if (t.repeat != RepeatRule.none) parts.add('repeats ${t.repeat.key}');
    final subs = store.subtasksOf(t.id);
    if (subs.isNotEmpty) {
      parts.add('${subs.where((s) => s.done).length}/${subs.length} subtasks');
    }
    return parts.join(' | ');
  }

  final topLevel = store.tasks.where((t) => !t.isSubtask).toList();
  final open = topLevel.where((t) => !t.done).toList()
    ..sort((a, b) {
      final ad = a.startsAt ?? a.dueAt, bd = b.startsAt ?? b.dueAt;
      if (ad == null && bd == null) return a.createdAt.compareTo(b.createdAt);
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
  final done = topLevel.where((t) => t.done).toList()
    ..sort(
      (a, b) => (b.completedAt ?? b.createdAt).compareTo(
        a.completedAt ?? a.createdAt,
      ),
    );

  buffer.writeln('Open tasks (${open.length}):');
  if (open.isEmpty) buffer.writeln('(none)');
  for (final t in open.take(_maxOpenTasks)) {
    buffer.writeln(line(t));
  }
  if (open.length > _maxOpenTasks) {
    buffer.writeln('(${open.length - _maxOpenTasks} more not shown)');
  }
  if (done.isNotEmpty) {
    buffer.writeln('Recently completed:');
    for (final t in done.take(_maxDoneTasks)) {
      buffer.writeln(line(t));
    }
  }
  return (text: buffer.toString().trimRight(), refs: refs);
}

/// What happened when an action was carried out, for showing in the chat.
typedef ActionResult = ({String text, bool ok});

DateTime? _parseDate(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d);
}

({int hour, int minute})? _parseTime(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
  if (m == null) return null;
  final h = int.parse(m[1]!), min = int.parse(m[2]!);
  if (h > 23 || min > 59) return null;
  return (hour: h, minute: min);
}

Priority? _parsePriority(String? value) => value == null
    ? null
    : Priority.values.where((p) => p.name == value).firstOrNull;

RepeatRule? _parseRepeat(String? value) => value == null
    ? null
    : RepeatRule.values.where((r) => r.key == value).firstOrNull;

/// A start/end pair on [day] from the action's times. With no end time the
/// slot is one hour; an end at or before the start runs past midnight.
({DateTime start, DateTime end})? _slot(
  AssistantAction a,
  DateTime day, {
  Duration length = const Duration(hours: 1),
}) {
  final s = _parseTime(a.startTime);
  if (s == null) return null;
  final start = DateTime(day.year, day.month, day.day, s.hour, s.minute);
  final e = _parseTime(a.endTime);
  if (e == null) return (start: start, end: start.add(length));
  var end = DateTime(day.year, day.month, day.day, e.hour, e.minute);
  if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
  return (start: start, end: end);
}

String _when(Task t, DateTime today) {
  final parts = <String>[
    if (t.dueAt != null) formatDue(t.dueAt!, today),
    if (t.hasTimeSlot)
      '${DateFormat.jm().format(t.startsAt!)} – ${DateFormat.jm().format(t.endsAt!)}',
    if (t.repeat != RepeatRule.none) t.repeat.shortLabel.toLowerCase(),
  ];
  return parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
}

/// Carries out the assistant's [actions] through the [store], in order.
/// [confirmDelete] is asked before each delete; without it deletes are
/// skipped.
Future<List<ActionResult>> runAssistantActions(
  TodoStore store,
  List<AssistantAction> actions,
  Map<String, Task> refs, {
  Future<bool> Function(Task task)? confirmDelete,
}) async {
  final results = <ActionResult>[];
  final today = store.today;
  var askedPermission = false;

  Future<void> askToNotify() async {
    if (askedPermission) return;
    askedPermission = true;
    await store.reminders.requestPermission();
  }

  String? projectId(String? name) => name == null
      ? null
      : store.projects
            .where((p) => p.name.toLowerCase() == name.toLowerCase())
            .firstOrNull
            ?.id;

  /// The task a reference points at, as it is in the store right now.
  Task? current(String? ref) {
    final original = refs[ref];
    if (original == null) return null;
    return store.tasks.where((t) => t.id == original.id).firstOrNull;
  }

  for (final a in actions) {
    switch (a.type) {
      case 'create_project':
        final name = a.title;
        if (name == null) {
          results.add((text: 'Skipped a project with no name', ok: false));
        } else if (projectId(name) != null) {
          results.add((text: 'Project “$name” already exists', ok: true));
        } else {
          final color =
              labelPalette[store.projects.length % labelPalette.length];
          final p = await store.addProject(name, color);
          results.add((
            text: p == null
                ? 'Could not create project “$name”'
                : 'Created project “$name”',
            ok: p != null,
          ));
        }

      case 'create_task':
        final title = a.title;
        if (title == null) {
          results.add((text: 'Skipped a task with no title', ok: false));
          break;
        }
        final date = _parseDate(a.dueDate);
        var slot = _slot(a, date ?? today);
        // A bare time that has already passed today means tomorrow.
        if (slot != null && date == null && slot.start.isBefore(store.now)) {
          slot = _slot(a, today.add(const Duration(days: 1)));
        }
        final repeat = _parseRepeat(a.repeat) ?? RepeatRule.none;
        var due = date ?? (slot == null ? null : dateOnly(slot.start));
        if (repeat != RepeatRule.none) due ??= today;
        if (slot != null) await askToNotify();
        final saved = await store.addTask(
          Task.draft(
            title: title,
            notes: a.notes ?? '',
            priority: _parsePriority(a.priority) ?? Priority.none,
            dueAt: due,
            startsAt: slot?.start,
            endsAt: slot?.end,
            projectId: projectId(a.project),
            repeat: repeat,
          ),
        );
        results.add((
          text: saved == null
              ? 'Could not add “$title”'
              : 'Added “$title”${_when(saved, today)}',
          ok: saved != null,
        ));

      case 'update_task':
        final task = current(a.taskRef);
        if (task == null) {
          results.add((text: "Couldn't find the task to change", ok: false));
          break;
        }
        final date = _parseDate(a.dueDate);
        Object? due = task.dueAt;
        var start = task.startsAt, end = task.endsAt;
        if (a.clearTime) start = end = null;
        if (a.clearDue) due = null;
        if (date != null) {
          due = date;
          // Moving the day moves an existing time slot with it.
          if (start != null && end != null) {
            final length = end.difference(start);
            start = DateTime(
              date.year,
              date.month,
              date.day,
              start.hour,
              start.minute,
            );
            end = start.add(length);
          }
        }
        final day = date ?? start ?? task.dueAt ?? today;
        final slot = _slot(
          a,
          day,
          length: task.hasTimeSlot
              ? task.endsAt!.difference(task.startsAt!)
              : const Duration(hours: 1),
        );
        if (slot != null) {
          start = slot.start;
          end = slot.end;
          due = dateOnly(slot.start);
          await askToNotify();
        } else {
          // Only the end time changed.
          final newEndTime = _parseTime(a.endTime);
          final s = start;
          if (s != null && newEndTime != null) {
            var newEnd = DateTime(
              s.year,
              s.month,
              s.day,
              newEndTime.hour,
              newEndTime.minute,
            );
            if (!newEnd.isAfter(s)) {
              newEnd = newEnd.add(const Duration(days: 1));
            }
            end = newEnd;
          }
        }
        final project = a.project;
        final updated = task.copyWith(
          title: a.title,
          notes: a.notes,
          priority: _parsePriority(a.priority),
          repeat: _parseRepeat(a.repeat),
          dueAt: due,
          startsAt: start,
          endsAt: end,
          projectId: project == null
              ? task.projectId
              : (projectId(project) ?? task.projectId),
        );
        await store.updateTask(updated);
        results.add((
          text: 'Updated “${updated.title}”${_when(updated, today)}',
          ok: true,
        ));

      case 'complete_task':
      case 'reopen_task':
        final task = current(a.taskRef);
        final wantDone = a.type == 'complete_task';
        if (task == null) {
          results.add((text: "Couldn't find that task", ok: false));
        } else {
          if (task.done != wantDone) await store.toggleDone(task);
          results.add((
            text: wantDone
                ? 'Completed “${task.title}”'
                : 'Reopened “${task.title}”',
            ok: true,
          ));
        }

      case 'delete_task':
        final task = current(a.taskRef);
        if (task == null) {
          results.add((text: "Couldn't find the task to delete", ok: false));
        } else if (confirmDelete == null || !await confirmDelete(task)) {
          results.add((text: 'Kept “${task.title}”', ok: false));
        } else {
          final removed = await store.deleteTask(task);
          results.add((
            text: removed == null
                ? 'Could not delete “${task.title}”'
                : 'Deleted “${task.title}”',
            ok: removed != null,
          ));
        }

      default:
        results.add((
          text: 'Skipped something I don\'t know how to do',
          ok: false,
        ));
    }
  }
  return results;
}
