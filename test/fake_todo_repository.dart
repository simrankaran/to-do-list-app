import 'dart:typed_data';

import 'package:my_app/data/models.dart';
import 'package:my_app/data/todo_repository.dart';

/// In-memory repository for tests. Set [failNext] to make the next call throw.
class FakeTodoRepository implements TodoRepository {
  final projects = <Project>[];
  final tags = <Tag>[];
  final tasks = <Task>[];
  bool failNext = false;
  int _id = 0;

  String _newId() => 'id${_id++}';

  Future<T> _run<T>(T Function() op) async {
    if (failNext) {
      failNext = false;
      throw const TodoException('Server said no');
    }
    return op();
  }

  @override
  Future<List<Project>> fetchProjects() => _run(() => [...projects]);

  @override
  Future<Project> createProject(String name, int color) => _run(() {
    final p = Project(id: _newId(), name: name, color: color);
    projects.add(p);
    return p;
  });

  @override
  Future<void> updateProject(Project project) => _run(() {
    projects[projects.indexWhere((p) => p.id == project.id)] = project;
  });

  @override
  Future<void> deleteProject(String id) => _run(() {
    projects.removeWhere((p) => p.id == id);
    for (var i = 0; i < tasks.length; i++) {
      if (tasks[i].projectId == id) {
        tasks[i] = tasks[i].copyWith(projectId: null);
      }
    }
  });

  @override
  Future<List<Tag>> fetchTags() => _run(() => [...tags]);

  @override
  Future<Tag> createTag(String name, int color) => _run(() {
    final t = Tag(id: _newId(), name: name, color: color);
    tags.add(t);
    return t;
  });

  @override
  Future<void> updateTag(Tag tag) => _run(() {
    tags[tags.indexWhere((t) => t.id == tag.id)] = tag;
  });

  @override
  Future<void> deleteTag(String id) => _run(() {
    tags.removeWhere((t) => t.id == id);
  });

  @override
  Future<List<Task>> fetchTasks() => _run(() => [...tasks]);

  @override
  Future<Task> createTask(Task draft) => _run(() {
    final t = Task(
      id: _newId(),
      title: draft.title,
      createdAt: DateTime.now(),
      projectId: draft.projectId,
      parentId: draft.parentId,
      notes: draft.notes,
      priority: draft.priority,
      dueAt: draft.dueAt,
      done: draft.done,
      tagIds: draft.tagIds,
      startsAt: draft.startsAt,
      endsAt: draft.endsAt,
      remind: draft.remind,
      startMessage: draft.startMessage,
      endMessage: draft.endMessage,
      earlyMinutes: draft.earlyMinutes,
      alertStyle: draft.alertStyle,
      alertSound: draft.alertSound,
      repeat: draft.repeat,
      repeatDays: draft.repeatDays,
    );
    tasks.add(t);
    return t;
  });

  @override
  Future<void> updateTask(Task task) => _run(() {
    tasks[tasks.indexWhere((t) => t.id == task.id)] = task;
  });

  @override
  Future<void> deleteTask(String id) => _run(() {
    tasks.removeWhere((t) => t.id == id || t.parentId == id);
  });

  @override
  Future<void> restoreTasks(List<Task> restored) => _run(() {
    tasks.addAll(restored);
  });

  final attachments = <Attachment>[];

  @override
  Future<List<Attachment>> fetchAttachments() => _run(() => [...attachments]);

  @override
  Future<Attachment> addAttachment(
    String taskId,
    Uint8List bytes,
    String name,
    String mimeType,
  ) => _run(() {
    final a = Attachment(
      id: _newId(),
      taskId: taskId,
      name: name,
      path: 'fake/$taskId/$name',
      mimeType: mimeType,
      sizeBytes: bytes.length,
      createdAt: DateTime.now(),
    );
    attachments.add(a);
    return a;
  });

  @override
  Future<void> deleteAttachment(Attachment attachment) => _run(() {
    attachments.removeWhere((a) => a.id == attachment.id);
  });

  @override
  Future<void> restoreAttachments(List<Attachment> restored) => _run(() {
    attachments.addAll(restored);
  });

  @override
  Future<String> attachmentUrl(Attachment attachment) =>
      _run(() => 'https://example.com/${attachment.path}');
}
