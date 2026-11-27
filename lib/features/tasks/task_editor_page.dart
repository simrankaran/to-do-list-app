import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../state/todo_store.dart';
import '../common/dialogs.dart';
import 'attachments_section.dart';
import 'task_tile.dart';

/// Creates a task (when [task] is null) or edits an existing one.
class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({
    super.key,
    required this.store,
    this.task,
    this.initialTitle,
    this.initialDueAt,
  });

  /// Pre-filled title for a new task (from the quick-add sheet).
  final String? initialTitle;

  /// Pre-filled due date for a new task (from the calendar).
  final DateTime? initialDueAt;

  final TodoStore store;
  final Task? task;

  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  final _newSubtask = TextEditingController();
  late Priority _priority;
  DateTime? _startsAt;
  DateTime? _endsAt;
  late bool _remind;
  DateTime? _dueAt;
  String? _projectId;
  late Set<String> _tagIds;
  bool _saving = false;
  bool _titleError = false;

  TodoStore get store => widget.store;
  bool get _isNew => widget.task == null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? widget.initialTitle ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
    _priority = t?.priority ?? Priority.none;
    _startsAt = t?.startsAt;
    _endsAt = t?.endsAt;
    _remind = t?.remind ?? true;
    if (t != null) {
      _dueAt = t.dueAt;
      _projectId = t.projectId;
      _tagIds = {...t.tagIds};
    } else {
      // New tasks inherit the context of the current view.
      final v = store.view;
      _projectId = v.kind == ViewKind.project ? v.id : null;
      _tagIds = {if (v.kind == ViewKind.tag) v.id!};
      _dueAt =
          widget.initialDueAt ??
          switch (v.kind) {
            ViewKind.today => store.today,
            ViewKind.upcoming => store.today.add(const Duration(days: 1)),
            _ => null,
          };
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _newSubtask.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    setState(() => _saving = true);
    if (_startsAt != null && _endsAt != null && _remind) {
      // Ask for notification permission the first time a slot is used.
      await store.reminders.requestPermission();
    }
    final tagIds = _tagIds.toList();
    if (_isNew) {
      final saved = await store.addTask(
        Task.draft(
          title: title,
          notes: _notes.text.trim(),
          priority: _priority,
          dueAt: _dueAt,
          projectId: _projectId,
          tagIds: tagIds,
          startsAt: _startsAt,
          endsAt: _endsAt,
          remind: _remind,
        ),
      );
      if (saved == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }
    } else {
      await store.updateTask(
        widget.task!.copyWith(
          title: title,
          notes: _notes.text.trim(),
          priority: _priority,
          dueAt: _dueAt,
          projectId: _projectId,
          tagIds: tagIds,
          startsAt: _startsAt,
          endsAt: _endsAt,
          remind: _remind,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete task?',
      message: 'This also deletes its subtasks.',
    );
    if (!ok) return;
    await store.deleteTask(widget.task!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? store.today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueAt = dateOnly(picked));
  }

  Future<void> _addSubtask() async {
    final title = _newSubtask.text.trim();
    if (title.isEmpty) return;
    _newSubtask.clear();
    final parent = widget.task!;
    await store.addTask(
      Task.draft(
        title: title,
        parentId: parent.id,
        projectId: parent.projectId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = store.today;
    final quickDates = {
      'Today': today,
      'Tomorrow': today.add(const Duration(days: 1)),
      'Next week': today.add(const Duration(days: 7)),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New task' : 'Edit task'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _title,
                autofocus: _isNew,
                maxLength: 500,
                style: theme.textTheme.titleLarge,
                decoration: InputDecoration(
                  hintText: 'What needs doing?',
                  errorText: _titleError ? 'Give the task a title' : null,
                  border: InputBorder.none,
                  counterText: '',
                ),
                onChanged: (_) {
                  if (_titleError) setState(() => _titleError = false);
                },
              ),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: 'Notes',
                  prefixIcon: Icon(Icons.notes),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              _Section('Priority'),
              SegmentedButton<Priority>(
                showSelectedIcon: false,
                segments: [
                  for (final p in Priority.values)
                    ButtonSegment(
                      value: p,
                      label: Text(p.label),
                      icon: Icon(
                        Icons.flag,
                        color: priorityColor(p, theme.colorScheme),
                      ),
                    ),
                ],
                selected: {_priority},
                onSelectionChanged: (s) => setState(() => _priority = s.first),
              ),
              const SizedBox(height: 20),
              _Section('Due date'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final MapEntry(key: label, value: date)
                      in quickDates.entries)
                    ChoiceChip(
                      label: Text(label),
                      selected: _dueAt == date,
                      onSelected: (_) => setState(() => _dueAt = date),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.calendar_month, size: 18),
                    label: Text(
                      _dueAt == null || quickDates.containsValue(_dueAt)
                          ? 'Pick date'
                          : formatDue(_dueAt!, today),
                    ),
                    onPressed: _pickDate,
                  ),
                  if (_dueAt != null)
                    TextButton.icon(
                      onPressed: () => setState(() => _dueAt = null),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('No date'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _Section('Time'),
              _TimeSlotEditor(
                startsAt: _startsAt,
                endsAt: _endsAt,
                remind: _remind,
                today: today,
                onChanged: (start, end) => setState(() {
                  _startsAt = start;
                  _endsAt = end;
                  // The task is due on the day its time slot starts.
                  if (start != null) _dueAt = dateOnly(start);
                }),
                onRemindChanged: (v) => setState(() => _remind = v),
              ),
              const SizedBox(height: 20),
              _Section('Project'),
              DropdownButtonFormField<String?>(
                initialValue: _projectId,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Row(
                      children: [
                        Icon(Icons.inbox),
                        SizedBox(width: 8),
                        Text('Inbox (no project)'),
                      ],
                    ),
                  ),
                  for (final p in store.projects)
                    DropdownMenuItem(
                      value: p.id,
                      child: Row(
                        children: [
                          Icon(Icons.folder, color: Color(p.color)),
                          const SizedBox(width: 8),
                          Text(p.name),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _projectId = v),
              ),
              const SizedBox(height: 20),
              _Section('Tags'),
              if (store.tags.isEmpty)
                Text(
                  'No tags yet. Create them from the side menu.',
                  style: theme.textTheme.bodySmall,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in store.tags)
                      FilterChip(
                        label: Text('#${tag.name}'),
                        selected: _tagIds.contains(tag.id),
                        selectedColor: Color(tag.color).withValues(alpha: 0.25),
                        onSelected: (on) => setState(
                          () =>
                              on ? _tagIds.add(tag.id) : _tagIds.remove(tag.id),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              _Section('Photos & PDFs'),
              if (_isNew)
                Text(
                  'Save the task first, then attach photos or PDFs.',
                  style: theme.textTheme.bodySmall,
                )
              else
                AttachmentsSection(store: store, task: widget.task!),
              if (widget.task?.isSubtask != true) ...[
                const SizedBox(height: 20),
                _Section('Subtasks'),
                if (_isNew)
                  Text(
                    'Save the task first, then add subtasks.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  ListenableBuilder(
                    listenable: store,
                    builder: (context, _) => Column(
                      children: [
                        for (final s in store.subtasksOf(widget.task!.id))
                          CheckboxListTile(
                            key: ValueKey(s.id),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: s.done,
                            onChanged: (_) => store.toggleDone(s),
                            title: Text(
                              s.title,
                              style: s.done
                                  ? const TextStyle(
                                      decoration: TextDecoration.lineThrough,
                                    )
                                  : null,
                            ),
                            secondary: IconButton(
                              tooltip: 'Delete subtask',
                              icon: const Icon(Icons.close),
                              onPressed: () => store.deleteTask(s),
                            ),
                          ),
                        TextField(
                          controller: _newSubtask,
                          decoration: InputDecoration(
                            hintText: 'Add a subtask',
                            prefixIcon: const Icon(Icons.add),
                            suffixIcon: IconButton(
                              tooltip: 'Add subtask',
                              icon: const Icon(Icons.keyboard_return),
                              onPressed: _addSubtask,
                            ),
                          ),
                          onSubmitted: (_) => _addSubtask(),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// Start and end time for a task, with quick durations and a notify switch.
class _TimeSlotEditor extends StatelessWidget {
  const _TimeSlotEditor({
    required this.startsAt,
    required this.endsAt,
    required this.remind,
    required this.today,
    required this.onChanged,
    required this.onRemindChanged,
  });

  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool remind;
  final DateTime today;
  final void Function(DateTime? start, DateTime? end) onChanged;
  final ValueChanged<bool> onRemindChanged;

  static const _durations = [
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(minutes: 90),
    Duration(hours: 2),
    Duration(hours: 3),
  ];

  static String _label(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h $m';
  }

  Future<void> _pickStart(BuildContext context) async {
    final date = await showDatePicker(
      context: context,
      initialDate: startsAt ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return;
    final nextHour = DateTime.now().add(const Duration(hours: 1));
    final time = await showTimePicker(
      context: context,
      initialTime: startsAt != null
          ? TimeOfDay.fromDateTime(startsAt!)
          : TimeOfDay(hour: nextHour.hour, minute: 0),
      helpText: 'Start time',
    );
    if (time == null) return;
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    // Keep the current length when moving the start; default to one hour.
    final length = startsAt != null && endsAt != null
        ? endsAt!.difference(startsAt!)
        : const Duration(hours: 1);
    onChanged(start, start.add(length));
  }

  Future<void> _pickEnd(BuildContext context) async {
    final start = startsAt!;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        endsAt ?? start.add(const Duration(hours: 1)),
      ),
      helpText: 'End time',
    );
    if (time == null) return;
    var end = DateTime(
      start.year,
      start.month,
      start.day,
      time.hour,
      time.minute,
    );
    // An end time at or before the start means it runs past midnight.
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    onChanged(start, end);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (startsAt == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => _pickStart(context),
          icon: const Icon(Icons.schedule_rounded),
          label: const Text('Set start and end time'),
        ),
      );
    }

    final start = startsAt!;
    final end = endsAt ?? start.add(const Duration(hours: 1));
    final length = end.difference(start);
    final time = DateFormat.jm();

    Widget box(String label, String main, String sub, VoidCallback onTap) =>
        Expanded(
          child: Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(main, style: theme.textTheme.titleLarge),
                    Text(sub, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            box(
              'Starts',
              time.format(start),
              formatDue(start, today),
              () => _pickStart(context),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ),
            box(
              'Ends',
              time.format(end),
              dateOnly(end) == dateOnly(start)
                  ? _label(length)
                  : 'next day Â· ${_label(length)}',
              () => _pickEnd(context),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in _durations)
              ChoiceChip(
                label: Text(_label(d)),
                selected: length == d,
                onSelected: (_) => onChanged(start, start.add(d)),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            remind
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
          ),
          title: const Text('Notify me when it starts and ends'),
          subtitle: Text(
            remind
                ? 'Alerts at ${time.format(start)} and ${time.format(end)}'
                : 'No alerts for this task',
          ),
          value: remind,
          onChanged: onRemindChanged,
        ),
        TextButton.icon(
          onPressed: () => onChanged(null, null),
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Remove time'),
        ),
      ],
    );
  }
}
