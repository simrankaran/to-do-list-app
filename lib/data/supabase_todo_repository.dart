import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'todo_repository.dart';

class SupabaseTodoRepository implements TodoRepository {
  SupabaseTodoRepository(this._db);

  final SupabaseClient _db;

  static const _taskColumns = '*, task_tags(tag_id)';

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw TodoException(e.message);
    } on AuthException catch (e) {
      throw TodoException(e.message);
    } catch (e) {
      throw TodoException(
        'Could not reach the server. Check your connection. ($e)',
      );
    }
  }

  // Projects -----------------------------------------------------------------

  @override
  Future<List<Project>> fetchProjects() => _guard(() async {
    final rows = await _db.from('projects').select().order('created_at');
    return rows.map(Project.fromJson).toList();
  });

  @override
  Future<Project> createProject(String name, int color) => _guard(() async {
    final row = await _db
        .from('projects')
        .insert({'name': name, 'color': color})
        .select()
        .single();
    return Project.fromJson(row);
  });

  @override
  Future<void> updateProject(Project project) => _guard(
    () => _db
        .from('projects')
        .update({'name': project.name, 'color': project.color})
        .eq('id', project.id),
  );

  @override
  Future<void> deleteProject(String id) =>
      _guard(() => _db.from('projects').delete().eq('id', id));

  // Tags ---------------------------------------------------------------------

  @override
  Future<List<Tag>> fetchTags() => _guard(() async {
    final rows = await _db.from('tags').select().order('name');
    return rows.map(Tag.fromJson).toList();
  });

  @override
  Future<Tag> createTag(String name, int color) => _guard(() async {
    final row = await _db
        .from('tags')
        .insert({'name': name, 'color': color})
        .select()
        .single();
    return Tag.fromJson(row);
  });

  @override
  Future<void> updateTag(Tag tag) => _guard(
    () => _db
        .from('tags')
        .update({'name': tag.name, 'color': tag.color})
        .eq('id', tag.id),
  );

  @override
  Future<void> deleteTag(String id) =>
      _guard(() => _db.from('tags').delete().eq('id', id));

  // Tasks --------------------------------------------------------------------

  @override
  Future<List<Task>> fetchTasks() => _guard(() async {
    final rows = await _db
        .from('tasks')
        .select(_taskColumns)
        .order('created_at');
    return rows.map(Task.fromJson).toList();
  });

  @override
  Future<Task> createTask(Task draft) => _guard(() async {
    final row = await _db
        .from('tasks')
        .insert(draft.toRow())
        .select(_taskColumns)
        .single();
    final saved = Task.fromJson(row);
    if (draft.tagIds.isEmpty) return saved;
    await _insertTagLinks(saved.id, draft.tagIds);
    return saved.copyWith(tagIds: draft.tagIds);
  });

  @override
  Future<void> updateTask(Task task) => _guard(() async {
    await _db.from('tasks').update(task.toRow()).eq('id', task.id);
    await _db.from('task_tags').delete().eq('task_id', task.id);
    await _insertTagLinks(task.id, task.tagIds);
  });

  @override
  Future<void> deleteTask(String id) =>
      _guard(() => _db.from('tasks').delete().eq('id', id));

  @override
  Future<void> restoreTasks(List<Task> tasks) => _guard(() async {
    // Parents must exist before their subtasks.
    final ordered = [
      ...tasks.where((t) => !t.isSubtask),
      ...tasks.where((t) => t.isSubtask),
    ];
    await _db.from('tasks').insert([
      for (final t in ordered) {...t.toRow(), 'id': t.id},
    ]);
    final links = [
      for (final t in ordered)
        for (final tagId in t.tagIds) {'task_id': t.id, 'tag_id': tagId},
    ];
    if (links.isNotEmpty) await _db.from('task_tags').insert(links);
  });

  Future<void> _insertTagLinks(String taskId, List<String> tagIds) async {
    if (tagIds.isEmpty) return;
    await _db.from('task_tags').insert([
      for (final tagId in tagIds) {'task_id': taskId, 'tag_id': tagId},
    ]);
  }
}
