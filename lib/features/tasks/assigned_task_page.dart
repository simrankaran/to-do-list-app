import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../state/todo_store.dart';
import '../common/user_avatar.dart';
import 'attachments_section.dart';
import 'task_tile.dart' show formatDue, priorityColor;

/// A task another person assigned to me. I can read it, open its files and
/// mark it started or done; only they can change or delete it.
class AssignedTaskPage extends StatelessWidget {
  const AssignedTaskPage({
    super.key,
    required this.store,
    required this.taskId,
  });

  final TodoStore store;
  final String taskId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final task = store.tasks.where((t) => t.id == taskId).firstOrNull;
        return Scaffold(
          appBar: AppBar(title: const Text('Assigned to you')),
          body: task == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'This task is no longer assigned to you.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _Body(store: store, task: task),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.store, required this.task});

  final TodoStore store;
  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final from = store.partnerOf(task);
    final fromName = from?.name ?? 'Someone';
    final time = DateFormat.jm();

    Widget fact(IconData icon, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color ?? scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        UserAvatar(
                          name: fromName,
                          url: from?.avatarUrl,
                          radius: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'From $fromName',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      task.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        decoration: task.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (task.done)
                      fact(
                        Icons.check_circle_rounded,
                        'Done',
                        color: scheme.primary,
                      )
                    else if (task.inProgress)
                      fact(
                        Icons.directions_run_rounded,
                        'You are working on this',
                        color: scheme.primary,
                      ),
                    if (task.dueAt != null)
                      fact(
                        Icons.event_rounded,
                        'Due ${formatDue(task.dueAt!, store.today)}',
                        color: task.isOverdue(store.today)
                            ? scheme.error
                            : null,
                      ),
                    if (task.hasTimeSlot)
                      fact(
                        Icons.schedule_rounded,
                        '${DateFormat.MMMEd().format(task.startsAt!)}, '
                        '${time.format(task.startsAt!)} to '
                        '${time.format(task.endsAt!)}'
                        '${task.remind ? ' · you will be reminded' : ''}',
                      ),
                    if (task.priority != Priority.none)
                      fact(
                        Icons.flag_rounded,
                        '${task.priority.label} priority',
                        color: priorityColor(task.priority, scheme),
                      ),
                    if (task.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text('Notes', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      SelectableText(
                        task.notes,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text('Files', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    AttachmentsSection(
                      store: store,
                      task: task,
                      readOnly: true,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Only $fromName can change or delete this task.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    if (!task.done) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => store.updateTask(
                            task.copyWith(inProgress: !task.inProgress),
                          ),
                          icon: Icon(
                            task.inProgress
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          label: Text(task.inProgress ? 'Pause' : 'Start'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => store.toggleDone(task),
                        icon: Icon(
                          task.done ? Icons.undo_rounded : Icons.check_rounded,
                        ),
                        label: Text(task.done ? 'Reopen' : 'Mark done'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
