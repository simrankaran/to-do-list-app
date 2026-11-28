import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../state/todo_store.dart';
import '../tasks/task_tile.dart';

/// Month calendar with dots on days that have open tasks due, and the
/// selected day's tasks underneath.
class CalendarTab extends StatefulWidget {
  const CalendarTab({
    super.key,
    required this.store,
    required this.onOpen,
    required this.onAdd,
  });

  final TodoStore store;
  final void Function(Task task) onOpen;

  /// Adds a task due on the given day.
  final void Function(DateTime day) onAdd;

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  late DateTime _selected = widget.store.today;
  late DateTime _month = DateTime(_selected.year, _selected.month);

  void _shiftMonth(int delta) {
    HapticFeedback.selectionClick();
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _goToday() {
    final today = widget.store.today;
    setState(() {
      _selected = today;
      _month = DateTime(today.year, today.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final store = widget.store;
    final today = store.today;
    final dueCounts = store.openDueCounts();
    final dayTasks = store.tasksDueOn(_selected);

    final firstWeekday = DateTime(_month.year, _month.month).weekday; // Mon = 1
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = firstWeekday - 1;
    final cells = leading + daysInMonth;

    return Scaffold(
      appBar: AppBar(
        title: Text('Calendar', style: theme.textTheme.headlineSmall),
        actions: [
          TextButton(onPressed: _goToday, child: const Text('Today')),
          IconButton(
            tooltip: 'Add task on this day',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => widget.onAdd(_selected),
          ),
          const SizedBox(width: 4),
        ],
      ),
      // One scrolling page, so the month and the day's tasks both stay
      // reachable on short screens (a phone held sideways).
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Month header.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed: () => _shiftMonth(-1),
                      ),
                      Expanded(
                        child: Text(
                          DateFormat.yMMMM().format(_month),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: () => _shiftMonth(1),
                      ),
                    ],
                  ),
                ),
                // Weekday labels.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                        Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Day grid; swipe sideways to change month.
                GestureDetector(
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -200) _shiftMonth(1);
                    if (v > 200) _shiftMonth(-1);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: (cells / 7).ceil() * 7,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisExtent: 48,
                          ),
                      itemBuilder: (context, i) {
                        final dayNum = i - leading + 1;
                        if (dayNum < 1 || dayNum > daysInMonth) {
                          return const SizedBox();
                        }
                        final day = DateTime(_month.year, _month.month, dayNum);
                        return _DayCell(
                          day: day,
                          selected: day == _selected,
                          isToday: day == today,
                          overdue: day.isBefore(today),
                          dueCount: dueCounts[day] ?? 0,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selected = day);
                          },
                        );
                      },
                    ),
                  ),
                ),
                const Divider(height: 1),
                // Selected day's tasks.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${formatDue(_selected, today)} · ${DateFormat('d MMM').format(_selected)}',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        dayTasks.isEmpty
                            ? ''
                            : '${dayTasks.length} task${dayTasks.length == 1 ? '' : 's'}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (dayTasks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: TextButton.icon(
                    onPressed: () => widget.onAdd(_selected),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nothing due. Add a task for this day'),
                  ),
                ),
              ),
            )
          else
            SliverList.separated(
              itemCount: dayTasks.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
              itemBuilder: (context, i) => TaskTile(
                key: ValueKey(dayTasks[i].id),
                task: dayTasks[i],
                store: store,
                flat: true,
                onTap: () => widget.onOpen(dayTasks[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.overdue,
    required this.dueCount,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final bool overdue;
  final int dueCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dotColor = selected
        ? scheme.onPrimary
        : overdue
        ? scheme.error
        : scheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${DateFormat.MMMMEEEEd().format(day)}${dueCount > 0 ? ', $dueCount due' : ''}',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? scheme.primary : null,
              border: isToday && !selected
                  ? Border.all(color: scheme.primary, width: 1.5)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: selected || isToday
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < dueCount.clamp(0, 3); i++)
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
