import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';

/// Number of task lines the Android widget layout has.
const widgetLineCount = 5;

/// The text shown on the home screen widget: a title, a "now/next" line,
/// up to [widgetLineCount] task lines and a footer. Unused slots are empty.
/// [tasks] is null when nobody is signed in.
Map<String, String> buildWidgetData(List<Task>? tasks, DateTime now) {
  final data = <String, String>{
    'title': 'Tasks',
    'now': '',
    'footer': '',
    for (var i = 0; i < widgetLineCount; i++) 'line$i': '',
  };
  if (tasks == null) {
    data['line0'] = 'Open the app to sign in';
    return data;
  }

  final today = dateOnly(now);
  final time = DateFormat.jm();
  // Open top-level tasks due today or overdue, timed ones first by start.
  final due =
      tasks
          .where(
            (t) =>
                !t.isSubtask &&
                !t.done &&
                t.dueAt != null &&
                !dateOnly(t.dueAt!).isAfter(today),
          )
          .toList()
        ..sort((a, b) {
          if (a.startsAt != null || b.startsAt != null) {
            if (a.startsAt == null) return 1;
            if (b.startsAt == null) return -1;
            return a.startsAt!.compareTo(b.startsAt!);
          }
          return b.priority.index.compareTo(a.priority.index);
        });

  data['title'] = due.isEmpty
      ? 'All done for today'
      : 'Today · ${due.length} to do';

  final current = due.where((t) => t.isInProgress(now)).firstOrNull;
  final next = due
      .where((t) => t.startsAt != null && t.startsAt!.isAfter(now))
      .firstOrNull;
  if (current != null) {
    data['now'] = 'Now: ${current.title} until ${time.format(current.endsAt!)}';
  } else if (next != null) {
    data['now'] = 'Next: ${next.title} at ${time.format(next.startsAt!)}';
  }

  for (var i = 0; i < due.length && i < widgetLineCount; i++) {
    final t = due[i];
    final overdue = dateOnly(t.dueAt!).isBefore(today);
    final prefix = t.hasTimeSlot && !overdue
        ? '${time.format(t.startsAt!)}  '
        : overdue
        ? 'Overdue  '
        : '';
    data['line$i'] = '•  $prefix${t.title}';
  }
  if (due.length > widgetLineCount) {
    data['footer'] = '+${due.length - widgetLineCount} more';
  }
  return data;
}

/// Pushes the latest tasks to the Android home screen widget. Does nothing
/// on other platforms. [tasks] is null when nobody is signed in.
Future<void> updateHomeWidget(List<Task>? tasks, DateTime now) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final data = buildWidgetData(tasks, now);
    for (final entry in data.entries) {
      await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
    }
    await HomeWidget.updateWidget(androidName: 'TasksWidgetProvider');
  } catch (e) {
    debugPrint('Could not update the home screen widget: $e');
  }
}
