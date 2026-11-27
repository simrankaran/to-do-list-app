import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/data/assistant_service.dart';
import 'package:my_app/data/models.dart';
import 'package:my_app/data/recurrence.dart';
import 'package:my_app/features/assistant/assistant_actions.dart';
import 'package:my_app/services/home_widget_sync.dart';
import 'package:my_app/state/todo_store.dart';

import 'fake_todo_repository.dart';

void main() {
  // Friday 27 November 2026, 10:00.
  final now = DateTime(2026, 11, 27, 10);
  final today = DateTime(2026, 11, 27);

  group('repeat dates', () {
    test('daily, weekly and monthly step forward from the base date', () {
      expect(
        nextRepeatDate(RepeatRule.daily, 0, today, today),
        DateTime(2026, 11, 28),
      );
      expect(
        nextRepeatDate(RepeatRule.weekly, 0, today, today),
        DateTime(2026, 12, 4),
      );
      expect(
        nextRepeatDate(RepeatRule.monthly, 0, today, today),
        DateTime(2026, 12, 27),
      );
      expect(nextRepeatDate(RepeatRule.none, 0, today, today), isNull);
    });

    test('monthly keeps the day of month, clamped to shorter months', () {
      final jan31 = DateTime(2026, 1, 31);
      expect(
        nextRepeatDate(RepeatRule.monthly, 0, jan31, jan31),
        DateTime(2026, 2, 28),
      );
    });

    test('chosen days jump to the next ticked weekday', () {
      const monAndWed = 1 | 4; // bit 0 = Monday, bit 2 = Wednesday
      expect(
        nextRepeatDate(RepeatRule.days, monAndWed, today, today),
        DateTime(2026, 11, 30), // Monday
      );
      expect(
        nextRepeatDate(
          RepeatRule.days,
          monAndWed,
          DateTime(2026, 11, 30),
          today,
        ),
        DateTime(2026, 12, 2), // Wednesday
      );
    });

    test('an overdue task repeats today or later, never in the past', () {
      expect(
        nextRepeatDate(RepeatRule.daily, 0, DateTime(2026, 11, 20), today),
        today,
      );
      expect(
        nextRepeatDate(RepeatRule.weekly, 0, DateTime(2026, 11, 6), today),
        today,
      );
    });

    test('the next occurrence keeps the time of day and settings', () {
      final task = Task(
        id: 'a',
        title: 'Gym',
        createdAt: now,
        dueAt: today,
        startsAt: DateTime(2026, 11, 27, 18),
        endsAt: DateTime(2026, 11, 27, 19, 30),
        repeat: RepeatRule.daily,
        earlyMinutes: 10,
        alertSound: AlertSound.bell,
        priority: Priority.high,
      );
      final next = nextOccurrence(task, today)!;
      expect(next.dueAt, DateTime(2026, 11, 28));
      expect(next.startsAt, DateTime(2026, 11, 28, 18));
      expect(next.endsAt, DateTime(2026, 11, 28, 19, 30));
      expect(next.repeat, RepeatRule.daily);
      expect(next.earlyMinutes, 10);
      expect(next.alertSound, AlertSound.bell);
      expect(next.priority, Priority.high);
      expect(next.done, isFalse);

      expect(
        nextOccurrence(task.copyWith(repeat: RepeatRule.none), today),
        isNull,
      );
    });
  });

  group('completing a repeating task', () {
    late FakeTodoRepository repo;
    late TodoStore store;

    setUp(() async {
      repo = FakeTodoRepository();
      store = TodoStore(repo, clock: () => now);
      await store.load();
    });

    test('creates the next one with fresh subtasks, once', () async {
      final task = (await store.addTask(
        Task.draft(
          title: 'Water plants',
          dueAt: today,
          repeat: RepeatRule.daily,
        ),
      ))!;
      await store.addTask(Task.draft(title: 'Fill the can', parentId: task.id));

      await store.toggleDone(task);

      List<Task> open() => store.tasks
          .where((t) => !t.isSubtask && !t.done && t.title == 'Water plants')
          .toList();
      expect(open(), hasLength(1));
      final next = open().single;
      expect(next.dueAt, DateTime(2026, 11, 28));
      expect(next.repeat, RepeatRule.daily);
      expect(store.subtasksOf(next.id).map((s) => s.title), ['Fill the can']);
      expect(store.subtasksOf(next.id).single.done, isFalse);

      // Unticking and ticking again must not add a second copy.
      Task original() => store.tasks.firstWhere((t) => t.id == task.id);
      await store.toggleDone(original());
      await store.toggleDone(original());
      expect(
        store.tasks.where((t) => !t.isSubtask && t.title == 'Water plants'),
        hasLength(2),
      );
    });

    test('a task that does not repeat creates nothing', () async {
      final task = (await store.addTask(Task.draft(title: 'One-off')))!;
      await store.toggleDone(task);
      expect(store.tasks, hasLength(1));
    });
  });

  group('home screen widget text', () {
    Task due(String id, {DateTime? on, DateTime? start, bool done = false}) =>
        Task(
          id: id,
          title: id,
          createdAt: now,
          dueAt: on ?? today,
          startsAt: start,
          endsAt: start?.add(const Duration(hours: 1)),
          done: done,
        );

    test('shows what is on now and what is due today', () {
      final data = buildWidgetData([
        due('Gym', start: DateTime(2026, 11, 27, 9, 30)),
        due('Milk'),
        due('Tax', on: DateTime(2026, 11, 26)),
        due('Finished', done: true),
        due('Later', on: DateTime(2026, 11, 29)),
      ], now);

      expect(data['title'], 'Today · 3 to do');
      expect(data['now'], startsWith('Now: Gym until'));
      expect(data['line0'], contains('Gym'));
      final lines = [for (var i = 0; i < widgetLineCount; i++) data['line$i']!];
      expect(lines.where((l) => l.isNotEmpty), hasLength(3));
      expect(lines.join('\n'), contains('Overdue  Tax'));
      expect(lines.join('\n'), isNot(contains('Finished')));
      expect(lines.join('\n'), isNot(contains('Later')));
      expect(data['footer'], '');
    });

    test('points at the next timed task when nothing is running', () {
      final data = buildWidgetData([
        due('Lunch', start: DateTime(2026, 11, 27, 13)),
      ], now);
      expect(data['now'], startsWith('Next: Lunch at'));
    });

    test('summarises extra tasks, an empty day and signed-out state', () {
      final many = buildWidgetData([
        for (var i = 0; i < 7; i++) due('Task $i'),
      ], now);
      expect(many['title'], 'Today · 7 to do');
      expect(many['footer'], '+2 more');

      final none = buildWidgetData(const [], now);
      expect(none['title'], 'All done for today');
      expect(none['line0'], '');

      final signedOut = buildWidgetData(null, now);
      expect(signedOut['title'], 'Tasks');
      expect(signedOut['line0'], 'Open the app to sign in');
    });
  });

  group('assistant', () {
    late FakeTodoRepository repo;
    late TodoStore store;
    late Project home;
    late Task milk;

    setUp(() async {
      repo = FakeTodoRepository();
      store = TodoStore(repo, clock: () => now);
      await store.load();
      home = (await store.addProject('Home', 0xFF4CAF50))!;
      milk = (await store.addTask(
        Task.draft(title: 'Buy milk', dueAt: today),
      ))!;
    });

    AssistantAction action(Map<String, dynamic> json) =>
        AssistantAction.fromJson(json);

    test('actions are read from JSON, ignoring blanks', () {
      final a = action({
        'type': 'create_task',
        'title': '  Gym  ',
        'notes': null,
        'due_date': '',
        'clear_due': true,
        'clear_time': null,
      });
      expect(a.type, 'create_task');
      expect(a.title, 'Gym');
      expect(a.dueDate, isNull);
      expect(a.clearDue, isTrue);
      expect(a.clearTime, isFalse);
    });

    test('the snapshot lists tasks with short references', () {
      final ctx = buildAssistantContext(store);
      expect(ctx.text, contains('Now: Friday 2026-11-27 10:00'));
      expect(ctx.text, contains('Projects: Home'));
      expect(ctx.text, contains('t1 | Buy milk | due 2026-11-27'));
      expect(ctx.refs['t1']!.id, milk.id);
    });

    test('creates a timed task in a project', () async {
      final results = await runAssistantActions(store, [
        action({
          'type': 'create_task',
          'title': 'Gym',
          'due_date': '2026-11-28',
          'start_time': '18:00',
          'end_time': '19:00',
          'project': 'home',
          'priority': 'high',
          'repeat': 'weekly',
        }),
      ], const {});

      expect(results.single.ok, isTrue);
      expect(results.single.text, startsWith('Added “Gym”'));
      final gym = store.tasks.firstWhere((t) => t.title == 'Gym');
      expect(gym.startsAt, DateTime(2026, 11, 28, 18));
      expect(gym.endsAt, DateTime(2026, 11, 28, 19));
      expect(gym.dueAt, DateTime(2026, 11, 28));
      expect(gym.projectId, home.id);
      expect(gym.priority, Priority.high);
      expect(gym.repeat, RepeatRule.weekly);
    });

    test(
      'a bare time that has passed today means tomorrow, for one hour',
      () async {
        await runAssistantActions(store, [
          action({
            'type': 'create_task',
            'title': 'Call',
            'start_time': '09:00',
          }),
        ], const {});
        final call = store.tasks.firstWhere((t) => t.title == 'Call');
        expect(call.startsAt, DateTime(2026, 11, 28, 9));
        expect(call.endsAt, DateTime(2026, 11, 28, 10));
      },
    );

    test('updates, completes and deletes tasks by reference', () async {
      final refs = buildAssistantContext(store).refs;

      var results = await runAssistantActions(store, [
        action({
          'type': 'update_task',
          'task_ref': 't1',
          'title': 'Buy oat milk',
          'due_date': '2026-11-30',
        }),
        action({'type': 'complete_task', 'task_ref': 't1'}),
        action({'type': 'complete_task', 'task_ref': 't99'}),
      ], refs);
      expect(results.map((r) => r.ok), [true, true, false]);
      final updated = store.tasks.firstWhere((t) => t.id == milk.id);
      expect(updated.title, 'Buy oat milk');
      expect(updated.dueAt, DateTime(2026, 11, 30));
      expect(updated.done, isTrue);

      // Deleting needs a yes from the user.
      results = await runAssistantActions(
        store,
        [
          action({'type': 'delete_task', 'task_ref': 't1'}),
        ],
        refs,
        confirmDelete: (_) async => false,
      );
      expect(results.single.ok, isFalse);
      expect(store.tasks.any((t) => t.id == milk.id), isTrue);

      results = await runAssistantActions(
        store,
        [
          action({'type': 'delete_task', 'task_ref': 't1'}),
        ],
        refs,
        confirmDelete: (_) async => true,
      );
      expect(results.single.ok, isTrue);
      expect(store.tasks.any((t) => t.id == milk.id), isFalse);
    });

    test('creates a project once and can clear a time slot', () async {
      final refs = buildAssistantContext(store).refs;
      final results = await runAssistantActions(store, [
        action({'type': 'create_project', 'title': 'Work'}),
        action({'type': 'create_project', 'title': 'work'}),
        action({
          'type': 'update_task',
          'task_ref': 't1',
          'start_time': '15:00',
          'end_time': '15:30',
        }),
      ], refs);
      expect(results.every((r) => r.ok), isTrue);
      expect(
        store.projects.where((p) => p.name.toLowerCase() == 'work'),
        hasLength(1),
      );
      var task = store.tasks.firstWhere((t) => t.id == milk.id);
      expect(task.startsAt, DateTime(2026, 11, 27, 15));
      expect(task.endsAt, DateTime(2026, 11, 27, 15, 30));

      await runAssistantActions(store, [
        action({'type': 'update_task', 'task_ref': 't1', 'clear_time': true}),
      ], refs);
      task = store.tasks.firstWhere((t) => t.id == milk.id);
      expect(task.hasTimeSlot, isFalse);
      expect(task.dueAt, today);
    });
  });
}
