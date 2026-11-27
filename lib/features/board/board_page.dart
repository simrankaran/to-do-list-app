import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../state/todo_store.dart';
import '../tasks/task_tile.dart';

/// Kanban board: To do, Doing and Done columns for the current view.
/// Long-press a card and drag it to another column.
class BoardPage extends StatefulWidget {
  const BoardPage({super.key, required this.store, required this.onOpen});

  final TodoStore store;
  final void Function(Task task) onOpen;

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  static const _wide = 760.0;
  static const _maxDone = 30;

  final _pages = PageController(viewportFraction: 0.9);
  int _page = 0;

  TodoStore get store => widget.store;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Top-level tasks of the current view, by column.
  Map<BoardColumn, List<Task>> _columns() {
    final inView = store.tasksForBoard();
    final columns = {for (final c in BoardColumn.values) c: <Task>[]};
    for (final t in inView) {
      columns[TodoStore.columnOf(t)]!.add(t);
    }
    columns[BoardColumn.done]!.sort(
      (a, b) => (b.completedAt ?? b.createdAt).compareTo(
        a.completedAt ?? a.createdAt,
      ),
    );
    if (columns[BoardColumn.done]!.length > _maxDone) {
      columns[BoardColumn.done] = columns[BoardColumn.done]!
          .take(_maxDone)
          .toList();
    }
    return columns;
  }

  Future<void> _move(Task task, BoardColumn to) async {
    if (TodoStore.columnOf(task) == to) return;
    HapticFeedback.mediumImpact();
    await store.moveOnBoard(task, to);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final columns = _columns();
        final wide = MediaQuery.sizeOf(context).width >= _wide;
        final scheme = Theme.of(context).colorScheme;

        Widget column(BoardColumn c) => _Column(
          column: c,
          tasks: columns[c]!,
          store: store,
          onOpen: widget.onOpen,
          onDrop: (t) => _move(t, c),
        );

        return Scaffold(
          appBar: AppBar(title: Text('Board · ${store.titleOf(store.view)}')),
          body: wide
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final c in BoardColumn.values)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: column(c),
                          ),
                        ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Column tabs; tapping one scrolls to it.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: [
                          for (final (i, c) in BoardColumn.values.indexed)
                            ButtonSegment(
                              value: i,
                              label: Text('${c.label} ${columns[c]!.length}'),
                            ),
                        ],
                        selected: {_page},
                        onSelectionChanged: (s) => _pages.animateToPage(
                          s.first,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                    ),
                    Expanded(
                      child: PageView(
                        controller: _pages,
                        onPageChanged: (p) => setState(() => _page = p),
                        children: [
                          for (final c in BoardColumn.values)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                              child: column(c),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Long-press a card and drag it to another column',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.column,
    required this.tasks,
    required this.store,
    required this.onOpen,
    required this.onDrop,
  });

  final BoardColumn column;
  final List<Task> tasks;
  final TodoStore store;
  final void Function(Task task) onOpen;
  final void Function(Task task) onDrop;

  static IconData _icon(BoardColumn c) => switch (c) {
    BoardColumn.todo => Icons.radio_button_unchecked_rounded,
    BoardColumn.doing => Icons.directions_run_rounded,
    BoardColumn.done => Icons.check_circle_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = switch (column) {
      BoardColumn.todo => scheme.outline,
      BoardColumn.doing => scheme.primary,
      BoardColumn.done => const Color(0xFF16A34A),
    };

    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => TodoStore.columnOf(d.data) != column,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: hovering
                ? accent.withValues(alpha: 0.12)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: hovering
                  ? accent
                  : scheme.outlineVariant.withValues(alpha: 0.5),
              width: hovering ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.22),
                      accent.withValues(alpha: 0.04),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Icon(_icon(column), color: accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        column.label,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${tasks.length}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            hovering ? 'Drop here' : 'Nothing here',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final task = tasks[i];
                          final card = TaskTile(
                            key: ValueKey(task.id),
                            task: task,
                            store: store,
                            onTap: () => onOpen(task),
                          );
                          return LongPressDraggable<Task>(
                            data: task,
                            onDragStarted: HapticFeedback.selectionClick,
                            feedback: Material(
                              color: Colors.transparent,
                              child: SizedBox(
                                width: 280,
                                child: Transform.rotate(
                                  angle: -0.03,
                                  child: Opacity(opacity: 0.95, child: card),
                                ),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.3,
                              child: card,
                            ),
                            child: card,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
