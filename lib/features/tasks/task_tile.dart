import 'package:flutter/services.dart';
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
    this.onDoubleTap,
    this.flat = false,
  });

  final Task task;
  final TodoStore store;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// Edge-to-edge row (mobile) instead of a rounded card (desktop).
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = store.today;
    final subtasks = store.subtasksOf(task.id);
    final project = store.projectById(task.projectId);
    final accent = priorityColor(task.priority, scheme);

    const live = Color(0xFF16A34A);
    final inProgress = task.isInProgress(store.now);
    final fromOther = store.isFromOther(task);
    final badges = <Widget>[
      if (store.partnerOf(task) case final person?)
        _Badge(
          icon: fromOther
              ? Icons.call_received_rounded
              : Icons.person_add_alt_1_rounded,
          text: fromOther ? 'From ${person.name}' : 'To ${person.name}',
          color: scheme.tertiary,
        ),
      if (task.inProgress && !task.done)
        _Badge(
          icon: Icons.directions_run_rounded,
          text: 'Doing',
          color: scheme.primary,
        ),
      if (inProgress)
        const _Badge(
          icon: Icons.play_circle_fill_rounded,
          text: 'Now',
          color: live,
        ),
      if (task.hasTimeSlot)
        _Badge(
          icon: Icons.schedule_rounded,
          text:
              '${DateFormat.jm().format(task.startsAt!)} – ${DateFormat.jm().format(task.endsAt!)}',
          color: inProgress ? live : scheme.onSurfaceVariant,
        ),
      if (task.hasTimeSlot && task.remind && !task.done)
        _Badge(
          icon: Icons.notifications_active_outlined,
          color: scheme.onSurfaceVariant,
        ),
      if (task.repeat != RepeatRule.none)
        _Badge(
          icon: Icons.repeat_rounded,
          text: task.repeat.shortLabel,
          color: scheme.onSurfaceVariant,
        ),
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
      if (store.attachmentsOf(task.id) case final files when files.isNotEmpty)
        _Badge(
          icon: Icons.attach_file_rounded,
          text: '${files.length}',
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

    // The checkbox sits outside the InkWell so a double-tap handler on the
    // row never delays ticking the box.
    final row = IntrinsicHeight(
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
              // Springs in when ticked, so finishing a task feels good.
              child: TweenAnimationBuilder<double>(
                key: ValueKey(task.done),
                tween: Tween(begin: task.done ? 0.55 : 1.0, end: 1.0),
                duration: const Duration(milliseconds: 550),
                curve: Curves.elasticOut,
                builder: (context, s, child) =>
                    Transform.scale(scale: 1.15 * s, child: child),
                child: Checkbox(
                  value: task.done,
                  activeColor: scheme.primary,
                  side: BorderSide(
                    color: task.priority == Priority.none
                        ? scheme.outline
                        : accent,
                    width: 2,
                  ),
                  onChanged: (_) {
                    HapticFeedback.lightImpact();
                    store.toggleDone(task);
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onTap,
              onDoubleTap: onDoubleTap,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                        child: Icon(
                          Icons.flag_rounded,
                          size: 20,
                          color: accent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: task.done ? 0.55 : 1,
      child: flat
          ? Material(color: scheme.surface, child: row)
          : Card(clipBehavior: Clip.antiAlias, child: row),
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
