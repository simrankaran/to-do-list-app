import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../state/todo_store.dart';
import 'dialogs.dart';

/// Create, edit and delete flows for projects and tags, shared by the
/// desktop side panel and the mobile layout.

Future<Project?> addProject(BuildContext context, TodoStore store) async {
  final result = await showNameColorDialog(
    context,
    title: 'New project',
    confirmLabel: 'Create',
  );
  if (result == null) return null;
  final p = await store.addProject(result.$1, result.$2);
  if (p != null) store.view = TodoView(ViewKind.project, p.id);
  return p;
}

Future<void> editProject(
  BuildContext context,
  TodoStore store,
  String id,
) async {
  final p = store.projectById(id);
  if (p == null) return;
  final result = await showNameColorDialog(
    context,
    title: 'Edit project',
    confirmLabel: 'Save',
    initialName: p.name,
    initialColor: p.color,
  );
  if (result != null) {
    await store.updateProject(p.copyWith(name: result.$1, color: result.$2));
  }
}

Future<void> deleteProject(
  BuildContext context,
  TodoStore store,
  String id,
) async {
  final p = store.projectById(id);
  if (p == null) return;
  final ok = await confirm(
    context,
    title: 'Delete "${p.name}"?',
    message: 'Its tasks will move to the Inbox.',
  );
  if (ok) await store.deleteProject(id);
}

Future<void> addTag(BuildContext context, TodoStore store) async {
  final result = await showNameColorDialog(
    context,
    title: 'New tag',
    confirmLabel: 'Create',
    initialColor: 0xFF2196F3,
  );
  if (result != null) await store.addTag(result.$1, result.$2);
}

Future<void> editTag(BuildContext context, TodoStore store, String id) async {
  final t = store.tagById(id);
  if (t == null) return;
  final result = await showNameColorDialog(
    context,
    title: 'Edit tag',
    confirmLabel: 'Save',
    initialName: t.name,
    initialColor: t.color,
  );
  if (result != null) {
    await store.updateTag(t.copyWith(name: result.$1, color: result.$2));
  }
}

Future<void> deleteTag(BuildContext context, TodoStore store, String id) async {
  final t = store.tagById(id);
  if (t == null) return;
  final ok = await confirm(
    context,
    title: 'Delete #${t.name}?',
    message: 'The tag is removed from every task. The tasks stay.',
  );
  if (ok) await store.deleteTag(id);
}

/// Bottom sheet with Edit / Delete for a project or tag (mobile long-press).
Future<void> showLabelSheet(
  BuildContext context, {
  required String title,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename / color'),
            onTap: () {
              Navigator.pop(sheetContext);
              onEdit();
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () {
              Navigator.pop(sheetContext);
              onDelete();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Bottom sheet for changing or removing the profile photo.
Future<void> showAvatarSheet(
  BuildContext context, {
  required bool hasPhoto,
  required VoidCallback onChange,
  VoidCallback? onRemove,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add_a_photo_outlined),
            title: Text(hasPhoto ? 'Change photo' : 'Upload photo'),
            onTap: () {
              Navigator.pop(sheetContext);
              onChange();
            },
          ),
          if (hasPhoto && onRemove != null)
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Remove photo',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                onRemove();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
