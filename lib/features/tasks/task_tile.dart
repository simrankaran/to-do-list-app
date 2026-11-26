import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../state/todo_store.dart';

String formatDue(DateTime due, DateTime today) {
  final days = dateOnly(due).difference(today).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days == -1) return 'Yesterday';
  if (days > 1 && days < 7) return DateFormat.EEEE().format(due);
  if (due.year == today.year) return DateFormat.MMMd().format(due);
  return DateFormat.yMMMd().format(due);
}

Color priorityColor(Priority p, ColorScheme scheme) => switch (p) {
  Priority.high => const Color(0xFFE5484D),
  Priority.medium => const Color(0xFFF59E0B),
  Priority.low => const Color(0xFF3B82F6),
  Priority.none => scheme.outline,
};

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.store,
    this.onTap,
  });

  final Task task;
  final TodoStore store;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = store.today;
    final subtasks = store.subtasksOf(task.id);
    final project = store.projectById(task.projectId);
    final accent = priorityColor(task.priority, scheme);

    final badges = <Widget>[
      if (task.dueAt != null)
        _Badge(
          icon: Icons.calendar_today_rounded,
          text: formatDue(task.dueAt!, today),
          color: task.isOverdue(today)
              ? scheme.error
              : dateOnly(task.dueAt!) == today
              ? const Color(0xFF16A34A)
              : scheme.onSurfaceVariant,
        ),
      if (subtasks.isNotEmpty)
        _Badge(
          icon: Icons.checklist_rounded,
          text: '${subtasks.where((s) => s.done).length}/${subtasks.length}',
          color: scheme.onSurfaceVariant,
        ),
      if (task.notes.trim().isNotEmpty)
        _Badge(
          icon: Icons.sticky_note_2_outlined,
          color: scheme.onSurfaceVariant,
        ),
      if (project != null && store.view.kind != ViewKind.project)
        _Badge(
          icon: Icons.folder_rounded,
          text: project.name,
          color: Color(project.color),
        ),
      for (final id in task.tagIds)
        if (store.tagById(id) case final tag?)
          _Badge(text: '#${tag.name}', color: Color(tag.color)),
    ];

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: task.done ? 0.55 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 5,
                  color: task.priority == Priority.none || task.done
                      ? Colors.transparent
                      : accent,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 0, 8),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Transform.scale(
                      scale: 1.15,
                      child: Checkbox(
                        value: task.done,
                        activeColor: scheme.primary,
                        side: BorderSide(
                          color: task.priority == Priority.none
                              ? scheme.outline
                              : accent,
                          width: 2,
                        ),
                        onChanged: (_) => store.toggleDone(task),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 8, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: theme.textTheme.titleMedium!.copyWith(
                            decoration: task.done
                                ? TextDecoration.lineThrough
                                : null,
                            color: task.done
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface,
                          ),
                          child: Text(task.title),
                        ),
                        if (badges.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: badges),
                        ],
                      ],
                    ),
                  ),
                ),
                if (task.priority != Priority.none)
                  Padding(
                    padding: const EdgeInsets.only(right: 14, top: 14),
                    child: Tooltip(
                      message: '${task.priority.label} priority',
                      child: Icon(Icons.flag_rounded, size: 20, color: accent),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded pill with an optional icon, tinted with [color].
class _Badge extends StatelessWidget {
  const _Badge({required this.color, this.icon, this.text});

  final Color color;
  final IconData? icon;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: text == null ? 6 : 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 14, color: color),
          if (icon != null && text != null) const SizedBox(width: 4),
          if (text != null)
            Text(
              text!,
              style: style.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}
