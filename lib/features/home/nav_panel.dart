import 'package:material_ui/material_ui.dart';

import '../../state/todo_store.dart';
import '../common/label_actions.dart';
import '../common/user_avatar.dart';

/// Icon and color that represent a view.
(IconData, Color) viewStyle(TodoStore store, TodoView v, ColorScheme scheme) =>
    switch (v.kind) {
      ViewKind.inbox => (Icons.inbox_rounded, const Color(0xFF3B82F6)),
      ViewKind.today => (Icons.wb_sunny_rounded, const Color(0xFF16A34A)),
      ViewKind.upcoming => (Icons.event_rounded, const Color(0xFF8B5CF6)),
      ViewKind.all => (Icons.dashboard_rounded, const Color(0xFFF59E0B)),
      ViewKind.completed => (Icons.task_alt_rounded, scheme.outline),
      ViewKind.project => (
        Icons.folder_rounded,
        Color(store.projectById(v.id)?.color ?? scheme.primary.toARGB32()),
      ),
      ViewKind.tag => (
        Icons.label_rounded,
        Color(store.tagById(v.id!)?.color ?? scheme.primary.toARGB32()),
      ),
    };

/// Views, projects and tags. Used as the drawer on narrow screens and as a
/// fixed side panel on wide ones.
class NavPanel extends StatelessWidget {
  const NavPanel({
    super.key,
    required this.store,
    required this.onSelected,
    required this.onSignOut,
    this.userEmail,
    this.avatarUrl,
    this.avatarBusy = false,
    this.onChangeAvatar,
    this.onRemoveAvatar,
  });

  final TodoStore store;
  final VoidCallback onSelected;
  final VoidCallback onSignOut;
  final String? userEmail;
  final String? avatarUrl;
  final bool avatarBusy;

  /// Null when the photo can't be changed.
  final VoidCallback? onChangeAvatar;

  /// Null when there is no photo to remove.
  final VoidCallback? onRemoveAvatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget item(TodoView v) {
      final (icon, color) = viewStyle(store, v, scheme);
      final count = store.countFor(v);
      final selected = store.view == v;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(icon, color: color, size: 22),
          title: Text(
            store.titleOf(v),
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          trailing: count > 0
              ? _CountPill(count: count, selected: selected)
              : null,
          selected: selected,
          onTap: () {
            store.view = v;
            onSelected();
          },
        ),
      );
    }

    Widget header(String label, String tooltip, VoidCallback onAdd) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: tooltip,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded, size: 20),
            onPressed: onAdd,
          ),
        ],
      ),
    );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _ProfileCard(
            email: userEmail,
            onSignOut: onSignOut,
            avatarUrl: avatarUrl,
            busy: avatarBusy,
            onChange: onChangeAvatar,
            onRemove: onRemoveAvatar,
          ),
          const SizedBox(height: 16),
          item(TodoView.inbox),
          item(TodoView.today),
          item(TodoView.upcoming),
          item(TodoView.all),
          item(TodoView.completed),
          header('Projects', 'New project', () => _addProject(context)),
          if (store.projects.isEmpty)
            const _Hint('Group related tasks into projects.'),
          for (final p in store.projects)
            _WithMenu(
              onEdit: () => _editProject(context, p.id),
              onDelete: () => _deleteProject(context, p.id),
              child: item(TodoView(ViewKind.project, p.id)),
            ),
          header('Tags', 'New tag', () => _addTag(context)),
          if (store.tags.isEmpty) const _Hint('Label tasks across projects.'),
          for (final t in store.tags)
            _WithMenu(
              onEdit: () => _editTag(context, t.id),
              onDelete: () => _deleteTag(context, t.id),
              child: item(TodoView(ViewKind.tag, t.id)),
            ),
        ],
      ),
    );
  }

  Future<void> _addProject(BuildContext context) async {
    if (await addProject(context, store) != null) onSelected();
  }

  Future<void> _editProject(BuildContext context, String id) =>
      editProject(context, store, id);

  Future<void> _deleteProject(BuildContext context, String id) =>
      deleteProject(context, store, id);

  Future<void> _addTag(BuildContext context) => addTag(context, store);

  Future<void> _editTag(BuildContext context, String id) =>
      editTag(context, store, id);

  Future<void> _deleteTag(BuildContext context, String id) =>
      deleteTag(context, store, id);
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.email,
    required this.onSignOut,
    this.avatarUrl,
    this.busy = false,
    this.onChange,
    this.onRemove,
  });

  final String? email;
  final VoidCallback onSignOut;
  final String? avatarUrl;
  final bool busy;
  final VoidCallback? onChange;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = email ?? 'Signed in';

    Widget avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: scheme.onPrimary.withValues(alpha: 0.7),
              width: 2,
            ),
          ),
          child: UserAvatar(
            name: name,
            url: avatarUrl,
            radius: 24,
            backgroundColor: scheme.onPrimary.withValues(alpha: 0.2),
            foregroundColor: scheme.onPrimary,
          ),
        ),
        if (busy)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.45),
              ),
              padding: const EdgeInsets.all(14),
              child: const CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
          ),
        if (onChange != null && !busy)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(blurRadius: 4, color: Colors.black26),
                ],
              ),
              child: Icon(
                Icons.photo_camera_rounded,
                size: 13,
                color: scheme.primary,
              ),
            ),
          ),
      ],
    );

    if (onChange != null) {
      avatar = PopupMenuButton<String>(
        tooltip: 'Change profile photo',
        enabled: !busy,
        position: PopupMenuPosition.under,
        onSelected: (v) => v == 'remove' ? onRemove?.call() : onChange!(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'change',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_a_photo_outlined),
              title: Text(avatarUrl == null ? 'Upload photo' : 'Change photo'),
            ),
          ),
          if (onRemove != null)
            const PopupMenuItem(
              value: 'remove',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline_rounded),
                title: Text('Remove photo'),
              ),
            ),
        ],
        child: avatar,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tasks',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimary,
                  ),
                ),
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            color: scheme.onPrimary,
            icon: const Icon(Icons.logout_rounded),
            onPressed: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 0,
          color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _WithMenu extends StatelessWidget {
  const _WithMenu({
    required this.child,
    required this.onEdit,
    required this.onDelete,
  });

  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: child),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_horiz_rounded, size: 18),
          onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Rename / color')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
