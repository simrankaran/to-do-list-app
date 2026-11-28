import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'todo_repository.dart';

class SupabaseTodoRepository implements TodoRepository {
  SupabaseTodoRepository(this._db) {
    _shared = StreamController<void>.broadcast(
      onListen: _subscribe,
      onCancel: _unsubscribe,
    );
  }

  final SupabaseClient _db;
  late final StreamController<void> _shared;
  RealtimeChannel? _channel;

  /// True once the database is known to have the `assignee_id` column, so
  /// the app keeps working against a database that hasn't been updated yet.
  bool _canAssign = false;

  static const _taskColumns = '*, task_tags(tag_id)';

  @override
  String? get currentUserId => _db.auth.currentUser?.id;

  @override
  Stream<void> get sharedChanges => _shared.stream;

  // Row level security limits these events to tasks this user may see.
  void _subscribe() {
    _channel = _db
        .channel('tasks-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tasks',
          callback: (change) {
            // Only tasks shared between two people matter here; my own
            // edits are already on screen.
            if (change.newRecord['assignee_id'] != null && !_shared.isClosed) {
              _shared.add(null);
            }
          },
        )
        .subscribe();
  }

  void _unsubscribe() {
    final channel = _channel;
    _channel = null;
    if (channel != null) _db.removeChannel(channel);
  }

  /// The row to write for [task]. The assignee is only sent when it matters.
  Map<String, dynamic> _row(Task task) => {
    ...task.toRow(),
    if (_canAssign || task.assigneeId != null) 'assignee_id': task.assigneeId,
  };

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on TodoException {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.message.contains('assignee_id')) {
        throw const TodoException(
          'Assigning tasks needs a database update that has not been run yet.',
        );
      }
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
    if (rows.isNotEmpty) _canAssign = rows.first.containsKey('assignee_id');
    final me = currentUserId;
    return [
      for (final row in rows)
        // A task someone assigned to me: their project, tags and parent
        // task are private to them, so it arrives as a plain task.
        if (me != null && row['user_id'] != me)
          Task.fromJson({
            ...row,
            'project_id': null,
            'parent_id': null,
            'task_tags': const <dynamic>[],
          })
        else
          Task.fromJson(row),
    ];
  });

  @override
  Future<Task> createTask(Task draft) => _guard(() async {
    final row = await _db
        .from('tasks')
        .insert(_row(draft))
        .select(_taskColumns)
        .single();
    final saved = Task.fromJson(row);
    if (draft.tagIds.isEmpty) return saved;
    await _insertTagLinks(saved.id, draft.tagIds);
    return saved.copyWith(tagIds: draft.tagIds);
  });

  @override
  Future<void> updateTask(Task task) => _guard(() async {
    await _db.from('tasks').update(_row(task)).eq('id', task.id);
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
      for (final t in ordered) {..._row(t), 'id': t.id},
    ]);
    final links = [
      for (final t in ordered)
        for (final tagId in t.tagIds) {'task_id': t.id, 'tag_id': tagId},
    ];
    if (links.isNotEmpty) await _db.from('task_tags').insert(links);
  });

  // Attachments --------------------------------------------------------------

  static const _bucket = 'attachments';
  static const maxAttachmentBytes = 50 * 1024 * 1024;

  @override
  Future<List<Attachment>> fetchAttachments() => _guard(() async {
    final rows = await _db
        .from('task_attachments')
        .select()
        .order('created_at');
    return rows.map(Attachment.fromJson).toList();
  });

  @override
  Future<Attachment> addAttachment(
    String taskId,
    Uint8List bytes,
    String name,
    String mimeType,
  ) => _guard(() async {
    if (bytes.length > maxAttachmentBytes) {
      throw const TodoException('Files can be up to 50 MB.');
    }
    final uid = _db.auth.currentUser!.id;
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '$uid/$taskId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    try {
      await _db.storage
          .from(_bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType),
          );
    } on StorageException catch (e) {
      throw TodoException('Upload failed: ${e.message}');
    }
    try {
      final row = await _db
          .from('task_attachments')
          .insert({
            'task_id': taskId,
            'name': name.length > 200 ? name.substring(0, 200) : name,
            'path': path,
            'mime_type': mimeType,
            'size_bytes': bytes.length,
          })
          .select()
          .single();
      return Attachment.fromJson(row);
    } catch (_) {
      // Don't leave an orphaned file behind if the record can't be saved.
      await _db.storage.from(_bucket).remove([path]);
      rethrow;
    }
  });

  @override
  Future<void> deleteAttachment(Attachment attachment) => _guard(() async {
    await _db.from('task_attachments').delete().eq('id', attachment.id);
    try {
      await _db.storage.from(_bucket).remove([attachment.path]);
    } on StorageException {
      // The record is gone; a leftover file is harmless and private.
    }
  });

  @override
  Future<void> restoreAttachments(List<Attachment> attachments) =>
      _guard(() async {
        if (attachments.isEmpty) return;
        await _db.from('task_attachments').insert([
          for (final a in attachments)
            {
              'id': a.id,
              'task_id': a.taskId,
              'name': a.name,
              'path': a.path,
              'mime_type': a.mimeType,
              'size_bytes': a.sizeBytes,
            },
        ]);
      });

  @override
  Future<String> attachmentUrl(Attachment attachment) => _guard(() async {
    try {
      return await _db.storage
          .from(_bucket)
          .createSignedUrl(attachment.path, 60 * 60);
    } on StorageException catch (e) {
      throw TodoException('Could not open the file: ${e.message}');
    }
  });

  Future<void> _insertTagLinks(String taskId, List<String> tagIds) async {
    if (tagIds.isEmpty) return;
    await _db.from('task_tags').insert([
      for (final tagId in tagIds) {'task_id': taskId, 'tag_id': tagId},
    ]);
  }
}
