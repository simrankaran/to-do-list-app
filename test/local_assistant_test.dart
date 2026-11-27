import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/data/assistant_service.dart';
import 'package:my_app/data/local_assistant.dart';
import 'package:my_app/data/todo_repository.dart';

/// Friday 27 November 2026, 10:00.
const _context = '''
Now: Friday 2026-11-27 10:00
Projects: Home, Work
Open tasks (3):
t1 | Buy milk | due 2026-11-27
t2 | Gym | due 2026-11-27 | 18:00-19:00 | project Home
t3 | Pay rent | due 2026-11-25 | high priority
Recently completed:
t4 | Call mom | due 2026-11-26''';

AssistantAction _only(String message, [String context = _context]) {
  final reply = respondLocally(message, context);
  expect(reply.actions, hasLength(1), reason: reply.text);
  return reply.actions.single;
}

class _FailingCloud implements AssistantService {
  _FailingCloud(this.error);
  final TodoException error;
  int calls = 0;

  @override
  Future<AssistantReply> send({
    required String message,
    required List<ChatTurn> history,
    required String context,
  }) async {
    calls++;
    throw error;
  }
}

void main() {
  group('adding tasks', () {
    test('a day and a time range', () {
      final a = _only('Add gym tomorrow from 6 to 7 pm');
      expect(a.type, 'create_task');
      expect(a.title, 'Gym');
      expect(a.dueDate, '2026-11-28');
      expect(a.startTime, '18:00');
      expect(a.endTime, '19:00');
      expect(a.repeat, isNull);
    });

    test('a weekly reminder on a weekday', () {
      final a = _only('Remind me to call mom every Sunday at 9am');
      expect(a.type, 'create_task');
      expect(a.title, 'Call mom');
      expect(a.repeat, 'weekly');
      expect(a.dueDate, '2026-11-29');
      expect(a.startTime, '09:00');
      expect(a.endTime, isNull);
    });

    test('a date, a duration, a priority and a project', () {
      final a = _only(
        'add team meeting on 2026-12-01 at 14:00 for 90 minutes high priority in work',
      );
      expect(a.title, 'Team meeting');
      expect(a.dueDate, '2026-12-01');
      expect(a.startTime, '14:00');
      expect(a.endTime, '15:30');
      expect(a.priority, 'high');
      expect(a.project, 'Work');
    });

    test('daily repeats, noon and deadlines', () {
      final standup = _only('add standup every day at 9:30');
      expect(standup.title, 'Standup');
      expect(standup.repeat, 'daily');
      expect(standup.startTime, '09:30');

      final lunch = _only('add lunch at noon');
      expect(lunch.title, 'Lunch');
      expect(lunch.startTime, '12:00');
      expect(lunch.dueDate, isNull);

      final report = _only('add report by friday');
      expect(report.title, 'Report');
      expect(report.dueDate, '2026-12-04');
      expect(report.startTime, isNull);
    });

    test('a bare "dentist tomorrow at 3pm" is still a new task', () {
      final a = _only('dentist tomorrow at 3pm');
      expect(a.type, 'create_task');
      expect(a.title, 'Dentist');
      expect(a.dueDate, '2026-11-28');
      expect(a.startTime, '15:00');
    });

    test('a new project', () {
      final a = _only('create project Fitness');
      expect(a.type, 'create_project');
      expect(a.title, 'Fitness');
    });
  });

  group('changing tasks', () {
    test('complete, reopen and delete by name', () {
      expect(_only('complete buy milk').type, 'complete_task');
      expect(_only('complete buy milk').taskRef, 't1');
      expect(_only('mark gym as done').taskRef, 't2');

      final reopen = _only('reopen call mom');
      expect(reopen.type, 'reopen_task');
      expect(reopen.taskRef, 't4');

      final delete = _only('delete pay rent');
      expect(delete.type, 'delete_task');
      expect(delete.taskRef, 't3');
    });

    test('move one task to a day and time', () {
      final a = _only('move gym to monday at 5pm');
      expect(a.type, 'update_task');
      expect(a.taskRef, 't2');
      expect(a.dueDate, '2026-11-30');
      expect(a.startTime, '17:00');
      expect(a.endTime, isNull);
    });

    test('move every overdue task', () {
      final a = _only('Move my overdue tasks to tomorrow');
      expect(a.type, 'update_task');
      expect(a.taskRef, 't3');
      expect(a.dueDate, '2026-11-28');
    });

    test('asks which task when the name fits several', () {
      const context = '''
Now: Friday 2026-11-27 10:00
Projects: (none)
Open tasks (2):
t1 | Call Sam
t2 | Call Alex''';
      final reply = respondLocally('complete call', context);
      expect(reply.actions, isEmpty);
      expect(reply.text, contains('Which one'));
    });

    test('says so when the task is not there', () {
      final reply = respondLocally('delete the unicorn task', _context);
      expect(reply.actions, isEmpty);
      expect(reply.text, contains("couldn't find"));
    });
  });

  group('questions', () {
    test('what is due today, with overdue tasks mentioned', () {
      final reply = respondLocally('What do I have today?', _context);
      expect(reply.actions, isEmpty);
      expect(reply.text, contains('Buy milk'));
      expect(reply.text, contains('Gym'));
      expect(reply.text, contains('overdue'));
    });

    test('what is overdue', () {
      final reply = respondLocally("what's overdue?", _context);
      expect(reply.actions, isEmpty);
      expect(reply.text, contains('Pay rent'));
      expect(reply.text, isNot(contains('Buy milk')));
    });

    test('anything else gets a hint instead of a guess', () {
      final reply = respondLocally('blah blah', _context);
      expect(reply.actions, isEmpty);
      expect(reply.text, contains('Try'));
    });
  });

  group('choosing between the cloud and built-in assistant', () {
    test('stops asking the cloud once it says it is not set up', () async {
      final cloud = _FailingCloud(const AssistantUnavailable());
      final assistant = SmartAssistantService(cloud);

      var reply = await assistant.send(
        message: 'complete buy milk',
        history: const [],
        context: _context,
      );
      expect(reply.actions.single.taskRef, 't1');

      reply = await assistant.send(
        message: 'help',
        history: const [],
        context: _context,
      );
      expect(reply.text, contains('Try'));
      expect(cloud.calls, 1);
    });

    test(
      'answers locally after a one-off failure, then tries the cloud again',
      () async {
        final cloud = _FailingCloud(const TodoException('busy'));
        final assistant = SmartAssistantService(cloud);
        for (var i = 0; i < 2; i++) {
          final reply = await assistant.send(
            message: 'delete pay rent',
            history: const [],
            context: _context,
          );
          expect(reply.actions.single.type, 'delete_task');
        }
        expect(cloud.calls, 2);
      },
    );
  });
}
