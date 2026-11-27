import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../state/todo_store.dart';
import '../common/label_actions.dart';
import '../common/user_avatar.dart';
import '../tasks/quick_add_sheet.dart';
import '../tasks/task_tile.dart';
import 'calendar_tab.dart';
import 'nav_panel.dart' show viewStyle;
import 'stats_section.dart';

/// Phone layout: bottom tab bar with Home, Search, New task and Profile.
class MobileHome extends StatefulWidget {
  const MobileHome({
    super.key,
    required this.store,
    required this.onOpenEditor,
    required this.onDelete,
    required this.onSignOut,
    this.userEmail,
    this.avatarUrl,
    this.avatarBusy = false,
    this.onChangeAvatar,
    this.onRemoveAvatar,
  });

  final TodoStore store;
  final void Function(Task? task, String? initialTitle, DateTime? initialDueAt)
  onOpenEditor;
  final Future<void> Function(Task task) onDelete;
  final VoidCallback onSignOut;
  final String? userEmail;
  final String? avatarUrl;
  final bool avatarBusy;
  final VoidCallback? onChangeAvatar;
  final VoidCallback? onRemoveAvatar;

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<MobileHome> {
  // Bottom bar positions: Home, Search, New task, Calendar, Profile.
  static const _home = 0, _new = 2;
  int _tab = _home;

  void _select(int index) {
    HapticFeedback.selectionClick();
    if (index == _new) {
      showQuickAddSheet(
        context,
        store: widget.store,
        onMoreDetails: (title) => widget.onOpenEditor(null, title, null),
      );
      return;
    }
    setState(() => _tab = index);
  }

  void _addOn(DateTime day) {
    showQuickAddSheet(
      context,
      store: widget.store,
      dueAt: day,
      onMoreDetails: (title) => widget.onOpenEditor(null, title, day),
    );
  }

  void _goHome() => setState(() => _tab = _home);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = widget.userEmail ?? '';

    return Scaffold(
      body: IndexedStack(
        // The New task slot (2) opens a sheet, so pages after it shift down.
        index: _tab > _new ? _tab - 1 : _tab,
        children: [
          _HomeTab(
            store: widget.store,
            onOpen: (t) => widget.onOpenEditor(t, null, null),
            onDelete: widget.onDelete,
          ),
          _SearchTab(
            store: widget.store,
            onOpen: (t) => widget.onOpenEditor(t, null, null),
          ),
          CalendarTab(
            store: widget.store,
            onOpen: (t) => widget.onOpenEditor(t, null, null),
            onAdd: _addOn,
          ),
          _ProfileTab(
            store: widget.store,
            email: widget.userEmail,
            avatarUrl: widget.avatarUrl,
            avatarBusy: widget.avatarBusy,
            onChangeAvatar: widget.onChangeAvatar,
            onRemoveAvatar: widget.onRemoveAvatar,
            onSignOut: widget.onSignOut,
            onShowView: (v) {
              widget.store.view = v;
              _goHome();
            },
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _select,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
              tooltip: 'Home',
            ),
            const NavigationDestination(
              icon: Icon(Icons.search_rounded),
              selectedIcon: Icon(Icons.saved_search_rounded),
              label: 'Search',
              tooltip: 'Search',
            ),
            const NavigationDestination(
              icon: Icon(Icons.add_box_outlined),
              label: 'New task',
              tooltip: 'New task',
            ),
            const NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month_rounded),
              label: 'Calendar',
              tooltip: 'Calendar',
            ),
            NavigationDestination(
              icon: UserAvatar(name: name, url: widget.avatarUrl, radius: 14),
              selectedIcon: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.onSurface, width: 2),
                ),
                child: UserAvatar(
                  name: name,
                  url: widget.avatarUrl,
                  radius: 13,
                ),
              ),
              label: 'Profile',
              tooltip: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home tab

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.store,
    required this.onOpen,
    required this.onDelete,
  });

  final TodoStore store;
  final void Function(Task task) onOpen;
  final Future<void> Function(Task task) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget body;
    if (store.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (store.loadError != null) {
      body = _Empty(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load your tasks',
        subtitle: store.loadError!,
        action: FilledButton(
          onPressed: store.load,
          child: const Text('Try again'),
        ),
      );
    } else {
      final tasks = store.visibleTasks;
      final progress = store.progressFor(store.view);
      final (_, viewColor) = viewStyle(store, store.view, scheme);
      body = RefreshIndicator(
        onRefresh: store.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _ViewStrip(store: store)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            store.titleOf(store.view),
                            style: theme.textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (progress.total > 0 &&
                            store.view.kind != ViewKind.completed)
                          Text(
                            '${progress.done} of ${progress.total} done',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    if (progress.total > 0 &&
                        store.view.kind != ViewKind.completed) ...[
                      const SizedBox(height: 8),
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: progress.done / progress.total),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: 4,
                          color: viewColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1)),
            if (tasks.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _Empty(
                  icon: Icons.wb_sunny_rounded,
                  title: 'Nothing here. Enjoy the calm.',
                  subtitle: 'Tap âŠ• below to add a task.',
                ),
              )
            else
              SliverList.separated(
                itemCount: tasks.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (context, i) {
                  final task = tasks[i];
                  return Dismissible(
                    key: ValueKey(task.id),
                    background: const _SwipeDelete(Alignment.centerLeft),
                    secondaryBackground: const _SwipeDelete(
                      Alignment.centerRight,
                    ),
                    onDismissed: (_) => onDelete(task),
                    child: _FeedItem(task: task, store: store, onOpen: onOpen),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Tasks',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          PopupMenuButton<SortBy>(
            tooltip: 'Sort',
            icon: const Icon(Icons.swap_vert_rounded),
            initialValue: store.sortBy,
            onSelected: (s) => store.sortBy = s,
            itemBuilder: (_) => [
              for (final s in SortBy.values)
                CheckedPopupMenuItem(
                  value: s,
                  checked: s == store.sortBy,
                  child: Text(s.label),
                ),
            ],
          ),
          IconButton(
            tooltip: store.showCompleted
                ? 'Hide completed tasks'
                : 'Show completed tasks',
            isSelected: store.showCompleted,
            icon: const Icon(Icons.visibility_off_outlined),
            selectedIcon: const Icon(Icons.visibility_rounded),
            onPressed: () => store.showCompleted = !store.showCompleted,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
    );
  }
}

/// Horizontally scrolling circles for views, projects and tags.
class _ViewStrip extends StatelessWidget {
  const _ViewStrip({required this.store});
  final TodoStore store;

  static const _builtIn = [
    (TodoView.inbox, 'Inbox'),
    (TodoView.today, 'Today'),
    (TodoView.upcoming, 'Upcoming'),
    (TodoView.all, 'All'),
    (TodoView.completed, 'Done'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget circle(TodoView v, String label, {VoidCallback? onLongPress}) {
      final (icon, color) = viewStyle(store, v, scheme);
      return _Circle(
        label: label,
        icon: icon,
        color: color,
        selected: store.view == v,
        count: v.kind == ViewKind.completed ? 0 : store.countFor(v),
        onTap: () {
          HapticFeedback.selectionClick();
          store.view = v;
        },
        onLongPress: onLongPress,
      );
    }

    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          for (final (v, label) in _builtIn) circle(v, label),
          for (final p in store.projects)
            circle(
              TodoView(ViewKind.project, p.id),
              p.name,
              onLongPress: () => showLabelSheet(
                context,
                title: p.name,
                onEdit: () => editProject(context, store, p.id),
                onDelete: () => deleteProject(context, store, p.id),
              ),
            ),
          for (final t in store.tags)
            circle(
              TodoView(ViewKind.tag, t.id),
              '#${t.name}',
              onLongPress: () => showLabelSheet(
                context,
                title: '#${t.name}',
                onEdit: () => editTag(context, store, t.id),
                onDelete: () => deleteTag(context, store, t.id),
              ),
            ),
          _Circle(
            label: 'New',
            icon: Icons.add_rounded,
            color: scheme.onSurfaceVariant,
            selected: false,
            dashed: true,
            tooltip: 'New project',
            onTap: () => addProject(context, store),
          ),
        ],
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.count = 0,
    this.dashed = false,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final int count;
  final bool dashed;
  final String? tooltip;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget ring = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 66,
      height: 66,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: selected
            ? LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [color, scheme.primary, scheme.tertiary],
              )
            : null,
        border: selected
            ? null
            : Border.all(
                color: dashed ? scheme.outline : scheme.outlineVariant,
                width: 1.5,
              ),
      ),
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surface,
        ),
        child: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(icon, color: color, size: 26),
        ),
      ),
    );

    if (count > 0) {
      ring = Stack(
        clipBehavior: Clip.none,
        children: [
          ring,
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              constraints: const BoxConstraints(minWidth: 22),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: scheme.surface, width: 2),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimary,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final item = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              onLongPress!();
            },
      child: SizedBox(
        width: 80,
        child: Column(
          children: [
            ring,
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
    return tooltip == null ? item : Tooltip(message: tooltip!, child: item);
  }
}

/// A task row that can be double-tapped to complete, with a check "pop".
class _FeedItem extends StatefulWidget {
  const _FeedItem({
    required this.task,
    required this.store,
    required this.onOpen,
  });

  final Task task;
  final TodoStore store;
  final void Function(Task task) onOpen;

  @override
  State<_FeedItem> createState() => _FeedItemState();
}

class _FeedItemState extends State<_FeedItem>
    with SingleTickerProviderStateMixin {
  late final _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );
  late final _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.2,
        end: 1.2,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 35,
    ),
    TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 15),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
  ]).animate(_pop);
  late final _opacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
  ]).animate(_pop);

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _doubleTap() {
    if (widget.task.done) return;
    HapticFeedback.mediumImpact();
    _pop.forward(from: 0);
    widget.store.toggleDone(widget.task);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        TaskTile(
          task: widget.task,
          store: widget.store,
          flat: true,
          onTap: () => widget.onOpen(widget.task),
          onDoubleTap: _doubleTap,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: FadeTransition(
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 56,
                    color: scheme.primary,
                    shadows: const [
                      Shadow(blurRadius: 16, color: Colors.black26),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Search tab

class _SearchTab extends StatefulWidget {
  const _SearchTab({required this.store, required this.onOpen});

  final TodoStore store;
  final void Function(Task task) onOpen;

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final _query = TextEditingController();
  final _filters = <String>{};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool _matches(Task t, String q, DateTime today) {
    if (t.isSubtask) return false;
    if (q.isNotEmpty &&
        !t.title.toLowerCase().contains(q) &&
        !t.notes.toLowerCase().contains(q)) {
      return false;
    }
    for (final f in _filters) {
      final ok = switch (f) {
        'overdue' => t.isOverdue(today),
        'high' => t.priority == Priority.high,
        'subtasks' => widget.store.subtasksOf(t.id).isNotEmpty,
        'notes' => t.notes.trim().isNotEmpty,
        _ when f.startsWith('p:') => t.projectId == f.substring(2),
        _ when f.startsWith('t:') => t.tagIds.contains(f.substring(2)),
        _ => true,
      };
      if (!ok) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final store = widget.store;
    final q = _query.text.trim().toLowerCase();
    final active = q.isNotEmpty || _filters.isNotEmpty;
    final results = active
        ? (store.tasks.where((t) => _matches(t, q, store.today)).toList()
            ..sort((a, b) => a.done == b.done ? 0 : (a.done ? 1 : -1)))
        : const <Task>[];

    final chips = <(String, String, Color?)>[
      ('overdue', 'Overdue', scheme.error),
      ('high', 'High priority', priorityColor(Priority.high, scheme)),
      ('subtasks', 'Has subtasks', null),
      ('notes', 'Has notes', null),
      for (final p in store.projects) ('p:${p.id}', p.name, Color(p.color)),
      for (final t in store.tags) ('t:${t.id}', '#${t.name}', Color(t.color)),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search tasks',
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(_query.clear),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final (key, label, color) in chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(label),
                      avatar: color == null
                          ? null
                          : CircleAvatar(backgroundColor: color, radius: 5),
                      selected: _filters.contains(key),
                      onSelected: (on) => setState(
                        () => on ? _filters.add(key) : _filters.remove(key),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: !active
                ? const _Empty(
                    icon: Icons.manage_search_rounded,
                    title: 'Find any task',
                    subtitle: 'Type a word or tap a filter above.',
                  )
                : results.isEmpty
                ? const _Empty(
                    icon: Icons.search_off_rounded,
                    title: 'No matching tasks',
                    subtitle: 'Try a different word or filter.',
                  )
                : ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: results.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 56),
                    itemBuilder: (context, i) => TaskTile(
                      key: ValueKey(results[i].id),
                      task: results[i],
                      store: store,
                      flat: true,
                      onTap: () => widget.onOpen(results[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile tab

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    required this.store,
    required this.onSignOut,
    required this.onShowView,
    this.email,
    this.avatarUrl,
    this.avatarBusy = false,
    this.onChangeAvatar,
    this.onRemoveAvatar,
  });

  final TodoStore store;
  final String? email;
  final String? avatarUrl;
  final bool avatarBusy;
  final VoidCallback? onChangeAvatar;
  final VoidCallback? onRemoveAvatar;
  final VoidCallback onSignOut;
  final void Function(TodoView view) onShowView;

  void _avatarMenu(BuildContext context) {
    if (onChangeAvatar == null || avatarBusy) return;
    showAvatarSheet(
      context,
      hasPhoto: avatarUrl != null,
      onChange: onChangeAvatar!,
      onRemove: onRemoveAvatar,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = email ?? 'You';
    final handle = name.contains('@') ? name.split('@').first : name;
    final topLevel = store.tasks.where((t) => !t.isSubtask);
    final open = topLevel.where((t) => !t.done).length;
    final done = topLevel.where((t) => t.done).length;

    Widget sectionHeader(String label, String tooltip, VoidCallback onAdd) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 4, 4),
          child: Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
              IconButton(
                tooltip: tooltip,
                icon: const Icon(Icons.add_rounded),
                onPressed: onAdd,
              ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          handle,
          style: theme.textTheme.titleLarge,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: onSignOut,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Tooltip(
                  message: 'Change profile photo',
                  child: GestureDetector(
                    onTap: () => _avatarMenu(context),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.bottomLeft,
                              end: Alignment.topRight,
                              colors: [scheme.primary, scheme.tertiary],
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.surface,
                            ),
                            child: UserAvatar(
                              name: name,
                              url: avatarUrl,
                              radius: 40,
                            ),
                          ),
                        ),
                        if (avatarBusy)
                          const Positioned.fill(
                            child: Padding(
                              padding: EdgeInsets.all(28),
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                          ),
                        if (onChangeAvatar != null && !avatarBusy)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: scheme.surface,
                                  width: 3,
                                ),
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                size: 16,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Stat(value: open, label: 'Open'),
                      _Stat(value: done, label: 'Done'),
                      _Stat(value: store.projects.length, label: 'Projects'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onChangeAvatar != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: OutlinedButton(
                onPressed: avatarBusy ? null : () => _avatarMenu(context),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Edit profile photo'),
              ),
            ),
          StatsSection(store: store),
          sectionHeader('Projects', 'New project', () async {
            final p = await addProject(context, store);
            if (p != null) onShowView(TodoView(ViewKind.project, p.id));
          }),
          if (store.projects.isEmpty)
            const _Hint('Group related tasks into projects.'),
          for (final p in store.projects)
            ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: Color(p.color).withValues(alpha: 0.15),
                child: Icon(
                  Icons.folder_rounded,
                  color: Color(p.color),
                  size: 20,
                ),
              ),
              title: Text(p.name),
              trailing: Text(
                '${store.countFor(TodoView(ViewKind.project, p.id))}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              onTap: () => onShowView(TodoView(ViewKind.project, p.id)),
              onLongPress: () => showLabelSheet(
                context,
                title: p.name,
                onEdit: () => editProject(context, store, p.id),
                onDelete: () => deleteProject(context, store, p.id),
              ),
            ),
          sectionHeader('Tags', 'New tag', () => addTag(context, store)),
          if (store.tags.isEmpty)
            const _Hint('Label tasks across projects.')
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in store.tags)
                    GestureDetector(
                      onLongPress: () => showLabelSheet(
                        context,
                        title: '#${t.name}',
                        onEdit: () => editTag(context, store, t.id),
                        onDelete: () => deleteTag(context, store, t.id),
                      ),
                      child: ActionChip(
                        avatar: CircleAvatar(
                          backgroundColor: Color(t.color),
                          radius: 5,
                        ),
                        label: Text('#${t.name}'),
                        onPressed: () =>
                            onShowView(TodoView(ViewKind.tag, t.id)),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 28),
          Center(
            child: TextButton.icon(
              onPressed: onSignOut,
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits

class _SwipeDelete extends StatelessWidget {
  const _SwipeDelete(this.alignment);
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.error,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(Icons.delete_rounded, color: scheme.onError),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.onSurface, width: 2),
              ),
              child: Icon(icon, size: 44, color: scheme.onSurface),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
