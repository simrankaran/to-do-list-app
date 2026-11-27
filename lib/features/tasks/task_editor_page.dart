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
  late final TextEditingController _startMessage;
  late final TextEditingController _endMessage;
  late int _earlyMinutes;
  late AlertStyle _alertStyle;
  late AlertSound _alertSound;
  late RepeatRule _repeat;
  late int _repeatDays;
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
    _startMessage = TextEditingController(text: t?.startMessage ?? '');
    _endMessage = TextEditingController(text: t?.endMessage ?? '');
    _earlyMinutes = t?.earlyMinutes ?? 0;
    _alertStyle = t?.alertStyle ?? AlertStyle.sound;
    _alertSound = t?.alertSound ?? AlertSound.standard;
    _repeat = t?.repeat ?? RepeatRule.none;
    _repeatDays = t?.repeatDays ?? 0;
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
    _startMessage.dispose();
    _endMessage.dispose();
    super.dispose();
  }

  /// Shows a sample notification with the chosen style and sound.
  Future<void> _testAlert() async {
    final ok = await store.reminders.preview(_alertStyle, _alertSound);
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Test alerts work in the phone app, with notifications allowed.',
          ),
        ),
      );
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
    // "Chosen days" with no day ticked means it doesn't repeat.
    if (_repeat == RepeatRule.days && _repeatDays == 0) {
      _repeat = RepeatRule.none;
    }
    // A repeating task needs a date to repeat from.
    if (_repeat != RepeatRule.none && _dueAt == null) _dueAt = store.today;
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
          startMessage: _startMessage.text.trim(),
          endMessage: _endMessage.text.trim(),
          earlyMinutes: _earlyMinutes,
          alertStyle: _alertStyle,
          alertSound: _alertSound,
          repeat: _repeat,
          repeatDays: _repeatDays,
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
          startMessage: _startMessage.text.trim(),
          endMessage: _endMessage.text.trim(),
          earlyMinutes: _earlyMinutes,
          alertStyle: _alertStyle,
          alertSound: _alertSound,
          repeat: _repeat,
          repeatDays: _repeatDays,
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
              if (widget.task?.isSubtask != true) ...[
                const SizedBox(height: 20),
                _Section('Repeat'),
                _RepeatEditor(
                  rule: _repeat,
                  days: _repeatDays,
                  onRuleChanged: (r) => setState(() {
                    _repeat = r;
                    // Start "chosen days" from the task's own weekday.
                    if (r == RepeatRule.days && _repeatDays == 0) {
                      final day = _startsAt ?? _dueAt ?? today;
                      _repeatDays = 1 << (day.weekday - 1);
                    }
                  }),
                  onDaysChanged: (d) => setState(() => _repeatDays = d),
                ),
              ],
              const SizedBox(height: 20),
              _Section('Time'),
              _TimeSlotEditor(
                startsAt: _startsAt,
                endsAt: _endsAt,
                remind: _remind,
                today: today,
                defaultDay: _dueAt,
                onChanged: (start, end) => setState(() {
                  _startsAt = start;
                  _endsAt = end;
                  // The task is due on the day its time slot starts.
                  if (start != null) _dueAt = dateOnly(start);
                }),
                onRemindChanged: (v) => setState(() => _remind = v),
              ),
              if (_startsAt != null && _remind) ...[
                const SizedBox(height: 20),
                _Section('Notification'),
                _AlertOptions(
                  earlyMinutes: _earlyMinutes,
                  style: _alertStyle,
                  sound: _alertSound,
                  startMessage: _startMessage,
                  endMessage: _endMessage,
                  onEarlyChanged: (v) => setState(() => _earlyMinutes = v),
                  onStyleChanged: (v) => setState(() => _alertStyle = v),
                  onSoundChanged: (v) => setState(() => _alertSound = v),
                  onTest: _testAlert,
                ),
              ],
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
    this.defaultDay,
  });

  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool remind;
  final DateTime today;

  /// The task's due day, used for a new time slot.
  final DateTime? defaultDay;
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

  /// Starts a one-hour slot at the next full hour today, or at 9 AM on the
  /// task's due day when that is another day.
  void _addSlot() {
    final day = defaultDay == null ? today : dateOnly(defaultDay!);
    final now = DateTime.now();
    final start = day == dateOnly(now)
        ? DateTime(now.year, now.month, now.day, now.hour + 1)
        : DateTime(day.year, day.month, day.day, 9);
    onChanged(start, start.add(const Duration(hours: 1)));
  }

  /// Moves the slot to another day, keeping its times.
  Future<void> _pickDay(BuildContext context) async {
    final start = startsAt!;
    final date = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    final moved = DateTime(
      date.year,
      date.month,
      date.day,
      start.hour,
      start.minute,
    );
    onChanged(moved, moved.add(_length));
  }

  Duration get _length => startsAt != null && endsAt != null
      ? endsAt!.difference(startsAt!)
      : const Duration(hours: 1);

  /// A new start time keeps the slot's length.
  void _setStart(int hour, int minute) {
    final s = startsAt!;
    final start = DateTime(s.year, s.month, s.day, hour, minute);
    onChanged(start, start.add(_length));
  }

  void _setEnd(int hour, int minute) {
    final start = startsAt!;
    var end = DateTime(start.year, start.month, start.day, hour, minute);
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
          onPressed: _addSlot,
          icon: const Icon(Icons.schedule_rounded),
          label: const Text('Set start and end time'),
        ),
      );
    }

    final start = startsAt!;
    final end = endsAt ?? start.add(const Duration(hours: 1));
    final length = end.difference(start);
    final time = DateFormat.jm();

    final caption = theme.textTheme.labelLarge?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: () => _pickDay(context),
          icon: const Icon(Icons.calendar_month_rounded, size: 18),
          label: Text('Day: ${formatDue(start, today)}'),
        ),
        const SizedBox(height: 12),
        Text('Starts', style: caption),
        const SizedBox(height: 6),
        _TimeDropdowns(time: start, onChanged: _setStart),
        const SizedBox(height: 12),
        Text('Ends', style: caption),
        const SizedBox(height: 6),
        _TimeDropdowns(time: end, onChanged: _setEnd),
        const SizedBox(height: 8),
        Text(
          dateOnly(end) == dateOnly(start)
              ? 'Length: ${_label(length)}'
              : 'Length: ${_label(length)} · ends next day',
          style: theme.textTheme.bodySmall,
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

/// A time of day chosen with three dropdowns: hour, minute and AM/PM.
class _TimeDropdowns extends StatelessWidget {
  const _TimeDropdowns({required this.time, required this.onChanged});

  final DateTime time;

  /// Called with the chosen hour (0 to 23) and minute.
  final void Function(int hour, int minute) onChanged;

  @override
  Widget build(BuildContext context) {
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final isPm = time.hour >= 12;
    // Five-minute steps, plus the current minute if it falls between them.
    final minutes = {for (var m = 0; m < 60; m += 5) m, time.minute}.toList()
      ..sort();

    int to24(int h12, bool pm) => (h12 % 12) + (pm ? 12 : 0);

    Widget dropdown<T>({
      required String label,
      required T value,
      required List<(T, String)> options,
      required ValueChanged<T> onPicked,
    }) => Expanded(
      child: DropdownButtonFormField<T>(
        // The value also changes from outside (duration chips), so rebuild.
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
        items: [
          for (final (v, text) in options)
            DropdownMenuItem(value: v, child: Text(text)),
        ],
        onChanged: (v) {
          if (v != null) onPicked(v);
        },
      ),
    );

    return Row(
      children: [
        dropdown<int>(
          label: 'Hour',
          value: hour12,
          options: [for (var h = 1; h <= 12; h++) (h, '$h')],
          onPicked: (h) => onChanged(to24(h, isPm), time.minute),
        ),
        const SizedBox(width: 8),
        dropdown<int>(
          label: 'Minute',
          value: time.minute,
          options: [for (final m in minutes) (m, m.toString().padLeft(2, '0'))],
          onPicked: (m) => onChanged(time.hour, m),
        ),
        const SizedBox(width: 8),
        dropdown<bool>(
          label: 'AM/PM',
          value: isPm,
          options: const [(false, 'AM'), (true, 'PM')],
          onPicked: (pm) => onChanged(to24(hour12, pm), time.minute),
        ),
      ],
    );
  }
}

/// Per-task notification choices: early heads-up, how it alerts, which
/// sound it plays, and custom wording.
class _AlertOptions extends StatelessWidget {
  const _AlertOptions({
    required this.earlyMinutes,
    required this.style,
    required this.sound,
    required this.startMessage,
    required this.endMessage,
    required this.onEarlyChanged,
    required this.onStyleChanged,
    required this.onSoundChanged,
    required this.onTest,
  });

  final int earlyMinutes;
  final AlertStyle style;
  final AlertSound sound;
  final TextEditingController startMessage;
  final TextEditingController endMessage;
  final ValueChanged<int> onEarlyChanged;
  final ValueChanged<AlertStyle> onStyleChanged;
  final ValueChanged<AlertSound> onSoundChanged;
  final VoidCallback onTest;

  static String _earlyLabel(int minutes) => switch (minutes) {
    0 => 'No early reminder',
    60 => '1 hour before',
    _ => '$minutes min before',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final testButton = OutlinedButton.icon(
      onPressed: onTest,
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('Test'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          initialValue: earlyMinutes,
          // Fill the field and shorten long text instead of overflowing.
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Early reminder',
            prefixIcon: Icon(Icons.alarm_rounded),
          ),
          items: [
            for (final m in earlyReminderOptions)
              DropdownMenuItem(
                value: m,
                child: Text(_earlyLabel(m), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => onEarlyChanged(v ?? 0),
        ),
        const SizedBox(height: 14),
        SegmentedButton<AlertStyle>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: AlertStyle.sound,
              label: Text('Sound'),
              icon: Icon(Icons.volume_up_rounded),
            ),
            ButtonSegment(
              value: AlertStyle.vibrate,
              label: Text('Vibrate'),
              icon: Icon(Icons.vibration_rounded),
            ),
            ButtonSegment(
              value: AlertStyle.silent,
              label: Text('Silent'),
              icon: Icon(Icons.notifications_paused_outlined),
            ),
          ],
          selected: {style},
          onSelectionChanged: (s) => onStyleChanged(s.first),
        ),
        const SizedBox(height: 6),
        Text(style.description, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (style == AlertStyle.sound)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<AlertSound>(
                  initialValue: sound,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Alert sound',
                    prefixIcon: Icon(Icons.music_note_rounded),
                  ),
                  items: [
                    for (final s in AlertSound.values)
                      DropdownMenuItem(
                        value: s,
                        child: Text(s.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => onSoundChanged(v ?? AlertSound.standard),
                ),
              ),
              const SizedBox(width: 10),
              testButton,
            ],
          )
        else
          testButton,
        const SizedBox(height: 14),
        TextField(
          controller: startMessage,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Message when it starts (optional)',
            hintText: 'e.g. Leave for the gym now!',
          ),
        ),
        TextField(
          controller: endMessage,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Message when it ends (optional)',
            hintText: 'e.g. Stop and stretch',
          ),
        ),
      ],
    );
  }
}

/// How a task repeats, with weekday chips for "On chosen days".
class _RepeatEditor extends StatelessWidget {
  const _RepeatEditor({
    required this.rule,
    required this.days,
    required this.onRuleChanged,
    required this.onDaysChanged,
  });

  final RepeatRule rule;
  final int days;
  final ValueChanged<RepeatRule> onRuleChanged;
  final ValueChanged<int> onDaysChanged;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<RepeatRule>(
          initialValue: rule,
          isExpanded: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.repeat_rounded),
          ),
          items: [
            for (final r in RepeatRule.values)
              DropdownMenuItem(
                value: r,
                child: Text(r.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (r) => onRuleChanged(r ?? RepeatRule.none),
        ),
        if (rule == RepeatRule.days) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < 7; i++)
                FilterChip(
                  label: Text(_dayNames[i]),
                  selected: days & (1 << i) != 0,
                  onSelected: (on) =>
                      onDaysChanged(on ? days | (1 << i) : days & ~(1 << i)),
                ),
            ],
          ),
        ],
        if (rule != RepeatRule.none) ...[
          const SizedBox(height: 6),
          Text(
            'When you finish it, the next one is added automatically.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
