import 'package:supabase_flutter/supabase_flutter.dart';

import 'todo_repository.dart';

/// One earlier message in the chat, sent along for context.
class ChatTurn {
  const ChatTurn.user(this.content) : role = 'user';
  const ChatTurn.assistant(this.content) : role = 'assistant';

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// A change the assistant wants made. The app carries it out.
class AssistantAction {
  const AssistantAction({
    required this.type,
    this.taskRef,
    this.title,
    this.notes,
    this.priority,
    this.dueDate,
    this.startTime,
    this.endTime,
    this.project,
    this.repeat,
    this.clearDue = false,
    this.clearTime = false,
  });

  factory AssistantAction.fromJson(Map<String, dynamic> json) {
    String? text(String key) {
      final v = json[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    return AssistantAction(
      type: text('type') ?? '',
      taskRef: text('task_ref'),
      title: text('title'),
      notes: json['notes'] is String ? json['notes'] as String : null,
      priority: text('priority'),
      dueDate: text('due_date'),
      startTime: text('start_time'),
      endTime: text('end_time'),
      project: text('project'),
      repeat: text('repeat'),
      clearDue: json['clear_due'] == true,
      clearTime: json['clear_time'] == true,
    );
  }

  /// create_task, update_task, complete_task, reopen_task, delete_task or
  /// create_project.
  final String type;

  /// Short reference of an existing task (e.g. "t3") from the snapshot.
  final String? taskRef;
  final String? title;
  final String? notes;
  final String? priority;

  /// Local date, YYYY-MM-DD.
  final String? dueDate;

  /// Local 24-hour times, HH:MM.
  final String? startTime;
  final String? endTime;
  final String? project;
  final String? repeat;
  final bool clearDue;
  final bool clearTime;
}

class AssistantReply {
  const AssistantReply({required this.text, this.actions = const []});
  final String text;
  final List<AssistantAction> actions;
}

/// Talks to the AI assistant.
abstract interface class AssistantService {
  /// Sends [message] with earlier [history] and a text [context] snapshot of
  /// the user's tasks. Throws [TodoException] with a user-facing message.
  Future<AssistantReply> send({
    required String message,
    required List<ChatTurn> history,
    required String context,
  });
}

/// Calls the `assistant` Supabase Edge Function, which holds the AI key.
class SupabaseAssistantService implements AssistantService {
  SupabaseAssistantService(this._client);

  final SupabaseClient _client;

  @override
  Future<AssistantReply> send({
    required String message,
    required List<ChatTurn> history,
    required String context,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'assistant',
        body: {
          'message': message,
          'context': context,
          'history': [for (final t in history) t.toJson()],
        },
      );
      final data = response.data;
      if (data is! Map) {
        throw const TodoException('The assistant sent an empty answer.');
      }
      final actions = data['actions'];
      return AssistantReply(
        text: data['reply'] as String? ?? '',
        actions: [
          if (actions is List)
            for (final a in actions)
              if (a is Map) AssistantAction.fromJson(a.cast<String, dynamic>()),
        ],
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['error'] : null;
      throw TodoException(switch (code) {
        'not_configured' => "The assistant isn't set up yet. It needs an AI key added in Supabase.",
        'bad_api_key' =>
          "The assistant's AI key was rejected. Check the key in Supabase.",
        'daily_limit' => "You've reached today's limit of assistant messages. Try again tomorrow.",
        'busy' => 'The assistant is busy right now. Try again in a moment.',
        'too_many_tasks' => 'There are too many tasks to send at once. Finish or delete some first.',
        'unauthorized' => 'Please sign in again to use the assistant.',
        _ => 'The assistant had a problem (error ${e.status}). Try again.',
      });
    } on TodoException {
      rethrow;
    } catch (e) {
      throw TodoException('Could not reach the assistant. ($e)');
    }
  }
}
