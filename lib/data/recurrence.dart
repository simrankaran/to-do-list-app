import 'models.dart';

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// The first date after [base] on which a task with this [rule] is due
/// again, skipping dates before [today]. Returns null if it doesn't repeat.
DateTime? nextRepeatDate(
  RepeatRule rule,
  int daysMask,
  DateTime base,
  DateTime today,
) {
  if (rule == RepeatRule.none) return null;
  final start = dateOnly(base);
  final anchorDay = start.day;

  DateTime step(DateTime d) {
    switch (rule) {
      case RepeatRule.weekly:
        return DateTime(d.year, d.month, d.day + 7);
      case RepeatRule.monthly:
        // Keep the original day of month, clamped (31st -> 30th/28th).
        final first = DateTime(d.year, d.month + 1);
        final last = _daysInMonth(first.year, first.month);
        return DateTime(
          first.year,
          first.month,
          anchorDay > last ? last : anchorDay,
        );
      case RepeatRule.days:
        if (daysMask & 127 == 0) return DateTime(d.year, d.month, d.day + 1);
        var next = DateTime(d.year, d.month, d.day + 1);
        while (daysMask & (1 << (next.weekday - 1)) == 0) {
          next = DateTime(next.year, next.month, next.day + 1);
        }
        return next;
      case RepeatRule.daily:
      case RepeatRule.none:
        return DateTime(d.year, d.month, d.day + 1);
    }
  }

  var next = step(start);
  while (next.isBefore(dateOnly(today))) {
    next = step(next);
  }
  return next;
}

/// A draft of the next occurrence of a repeating [task], or null if the
/// task doesn't repeat. The time slot keeps its time of day and length, and
/// notification settings carry over.
Task? nextOccurrence(Task task, DateTime today) {
  if (task.isSubtask) return null;
  final base = task.startsAt ?? task.dueAt ?? today;
  final date = nextRepeatDate(task.repeat, task.repeatDays, base, today);
  if (date == null) return null;

  DateTime? start, end;
  if (task.hasTimeSlot) {
    final s = task.startsAt!;
    start = DateTime(date.year, date.month, date.day, s.hour, s.minute);
    end = start.add(task.endsAt!.difference(s));
  }
  return Task.draft(
    title: task.title,
    notes: task.notes,
    priority: task.priority,
    projectId: task.projectId,
    tagIds: task.tagIds,
    dueAt: date,
    startsAt: start,
    endsAt: end,
    remind: task.remind,
    startMessage: task.startMessage,
    endMessage: task.endMessage,
    earlyMinutes: task.earlyMinutes,
    alertStyle: task.alertStyle,
    alertSound: task.alertSound,
    repeat: task.repeat,
    repeatDays: task.repeatDays,
    assigneeId: task.assigneeId,
  );
}
