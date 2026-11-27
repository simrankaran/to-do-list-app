import 'dart:typed_data';

import 'models.dart';

/// Error with a message that is safe to show to the user.
class TodoException implements Exception {
  const TodoException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Storage for the signed-in user's projects, tags and tasks.
///
/// The app talks only to this interface, so the backend can be swapped
/// (Supabase in production, an in-memory fake in tests).
abstract interface class TodoRepository {
  Future<List<Project>> fetchProjects();
  Future<Project> createProject(String name, int color);
  Future<void> updateProject(Project project);
  Future<void> deleteProject(String id);

  Future<List<Tag>> fetchTags();
  Future<Tag> createTag(String name, int color);
  Future<void> updateTag(Tag tag);
  Future<void> deleteTag(String id);

  Future<List<Task>> fetchTasks();

  /// Saves a draft and returns it with its database id.
  Future<Task> createTask(Task draft);
  Future<void> updateTask(Task task);

  /// Deletes a task; its subtasks are deleted with it.
  Future<void> deleteTask(String id);

  /// Re-inserts previously deleted tasks with their original ids (for undo).
  Future<void> restoreTasks(List<Task> tasks);

  Future<List<Attachment>> fetchAttachments();

  /// Uploads a file and records it on [taskId].
  Future<Attachment> addAttachment(
    String taskId,
    Uint8List bytes,
    String name,
    String mimeType,
  );

  Future<void> deleteAttachment(Attachment attachment);

  /// Re-creates attachment records removed along with a deleted task (undo).
  /// The files themselves are still in storage.
  Future<void> restoreAttachments(List<Attachment> attachments);

  /// A short-lived link for viewing or downloading the file.
  Future<String> attachmentUrl(Attachment attachment);
}
