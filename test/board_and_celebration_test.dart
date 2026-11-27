import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_app/data/models.dart';
import 'package:my_app/services/app_settings.dart';
import 'package:my_app/state/todo_store.dart';

import 'fake_todo_repository.dart';

void main() {
  final now = DateTime(2026, 11, 27, 10);
  final today = DateTime(2026, 11, 27);

  late FakeTodoRepository repo;
  late TodoStore store;

  setUp(() async {
    repo = FakeTodoRepository();
    store = TodoStore(repo, clock: () => now);
    await store.load();
  });

  Future<Task> add(String title, {DateTime? due}) async =>
      (await store.addTask(Task.draft(title: title, dueAt: due)))!;

  Task fresh(Task t) => store.tasks.firstWhere((x) => x.id == t.id);

  group('board', () {
    test('tasks move between To do, Doing and Done', () async {
      final t = await add('Write report');
      expect(TodoStore.columnOf(fresh(t)), BoardColumn.todo);

      await store.moveOnBoard(fresh(t), BoardColumn.doing);
      expect(fresh(t).inProgress, isTrue);
      expect(TodoStore.columnOf(fresh(t)), BoardColumn.doing);
      expect(repo.tasks.single.inProgress, isTrue);

      await store.moveOnBoard(fresh(t), BoardColumn.done);
      expect(fresh(t).done, isTrue);
      expect(fresh(t).inProgress, isFalse);
      expect(TodoStore.columnOf(fresh(t)), BoardColumn.done);

      // Dragging a finished task back to Doing reopens it.
      await store.moveOnBoard(fresh(t), BoardColumn.doing);
      expect(fresh(t).done, isFalse);
      expect(fresh(t).inProgress, isTrue);

      await store.moveOnBoard(fresh(t), BoardColumn.todo);
      expect(fresh(t).done, isFalse);
      expect(fresh(t).inProgress, isFalse);
    });

    test('the board shows finished tasks of the current view too', () async {
      final a = await add('Open one');
      final b = await add('Finished one');
      await store.toggleDone(fresh(b));
      store.view = TodoView.inbox;
      expect(store.visibleTasks.map((t) => t.id), [a.id]);
      expect(store.tasksForBoard().map((t) => t.id).toSet(), {a.id, b.id});
    });

    test('"Doing" is saved to the database row', () {
      final t = Task(id: 'x', title: 'x', createdAt: now, inProgress: true);
      expect(t.toRow()['in_progress'], isTrue);
      expect(
        Task.fromJson({
          'id': 'x',
          'title': 'x',
          'created_at': '2026-11-27T10:00:00Z',
          'priority': 0,
          'done': false,
          'in_progress': true,
        }).inProgress,
        isTrue,
      );
    });
  });

  group('celebrations', () {
    test(
      'each finished task is announced; the last one clears the day',
      () async {
        final events = <Completion>[];
        final sub = store.completions.listen(events.add);
        final a = await add('Milk', due: today);
        final b = await add('Gym', due: today);
        await add('Someday');

        await store.toggleDone(fresh(a));
        await store.toggleDone(fresh(b));
        await Future<void>.delayed(Duration.zero);

        expect(events.map((e) => e.task.title), ['Milk', 'Gym']);
        expect(events.map((e) => e.clearedToday), [false, true]);
        await sub.cancel();
      },
    );

    test('reopening or finishing a subtask is not celebrated', () async {
      final events = <Completion>[];
      final sub = store.completions.listen(events.add);
      final parent = await add('Trip');
      final sub1 = (await store.addTask(
        Task.draft(title: 'Pack', parentId: parent.id),
      ))!;

      await store.toggleDone(fresh(sub1));
      await store.toggleDone(fresh(parent));
      await store.toggleDone(fresh(parent)); // reopen
      await Future<void>.delayed(Duration.zero);

      expect(events.map((e) => e.task.title), ['Trip']);
      await sub.cancel();
    });
  });

  test('settings start with the default theme, sounds and confetti on', () {
    final s = AppSettings();
    expect(s.theme.key, 'indigo');
    expect(s.themeMode, ThemeMode.system);
    expect(s.sounds, isTrue);
    expect(s.celebrations, isTrue);

    var changes = 0;
    s.addListener(() => changes++);
    s.theme = themeByKey('ocean');
    s.sounds = false;
    expect(s.theme.name, 'Ocean');
    expect(s.sounds, isFalse);
    expect(changes, 2);
    expect(themeByKey('nonsense').key, 'indigo');
  });
}
