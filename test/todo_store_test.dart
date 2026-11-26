import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/data/models.dart';
import 'package:my_app/state/todo_store.dart';

import 'fake_todo_repository.dart';

void main() {
  final now = DateTime(2026, 11, 26, 10);
  final today = dateOnly(now);

  late FakeTodoRepository repo;
  late TodoStore store;

  setUp(() async {
    repo = FakeTodoRepository();
    store = TodoStore(repo, clock: () => now);
    await store.load();
  });

  Future<Task> add(
    String title, {
    DateTime? due,
    Priority priority = Priority.none,
    String? projectId,
    String? parentId,
  }) async => (await store.addTask(
    Task.draft(
      title: title,
      dueAt: due,
      priority: priority,
      projectId: projectId,
      parentId: parentId,
    ),
  ))!;

  List<String> titles() => store.visibleTasks.map((t) => t.title).toList();

  test('views split tasks by due date and project', () async {
    final p = (await store.addProject('Work', 0xFF2196F3))!;
    await add('overdue', due: today.subtract(const Duration(days: 2)));
    await add('today', due: today);
    await add('later', due: today.add(const Duration(days: 3)));
    await add('in project', projectId: p.id);

    store.view = TodoView.today;
    expect(titles(), ['overdue', 'today']);

    store.view = TodoView.upcoming;
    expect(titles(), ['later']);

    store.view = TodoView.inbox;
    expect(titles(), ['overdue', 'today', 'later']);

    store.view = TodoView(ViewKind.project, p.id);
    expect(titles(), ['in project']);
  });

  test('completed tasks are hidden unless asked for', () async {
    final t = await add('write report');
    await store.toggleDone(store.tasks.firstWhere((x) => x.id == t.id));

    store.view = TodoView.all;
    expect(titles(), isEmpty);
    expect(store.countFor(TodoView.all), 0);

    store.showCompleted = true;
    expect(titles(), ['write report']);

    store.showCompleted = false;
    store.view = TodoView.completed;
    expect(titles(), ['write report']);
  });

  test('smart sort puts earlier due dates and higher priority first', () async {
    await add('no date low', priority: Priority.low);
    await add('no date high', priority: Priority.high);
    await add('due tomorrow', due: today.add(const Duration(days: 1)));
    await add('due today', due: today);

    store.view = TodoView.all;
    expect(titles(), [
      'due today',
      'due tomorrow',
      'no date high',
      'no date low',
    ]);

    store.sortBy = SortBy.title;
    expect(titles().first, 'due today');
    expect(titles().last, 'no date low');
  });

  test(
    'subtasks stay out of the main list and are deleted with the parent',
    () async {
      final parent = await add('trip');
      await add('book flight', parentId: parent.id);
      await add('pack', parentId: parent.id);

      store.view = TodoView.all;
      expect(titles(), ['trip']);
      expect(store.subtasksOf(parent.id).map((t) => t.title), [
        'book flight',
        'pack',
      ]);

      final removed = await store.deleteTask(parent);
      expect(removed, hasLength(3));
      expect(store.tasks, isEmpty);

      await store.restore(removed!);
      expect(store.tasks, hasLength(3));
      expect(repo.tasks, hasLength(3));
    },
  );

  test('search looks across every view', () async {
    final p = (await store.addProject('Home', 0xFF4CAF50))!;
    await add('buy milk', projectId: p.id);
    await add('call mom');

    store.view = TodoView.today;
    store.query = 'MILK';
    expect(titles(), ['buy milk']);
  });

  test('failed update is rolled back and reported', () async {
    final t = await add('fragile');
    final errors = <String>[];
    final sub = store.errors.listen(errors.add);

    repo.failNext = true;
    await store.toggleDone(t);
    await Future<void>.delayed(Duration.zero);

    expect(store.tasks.single.done, isFalse);
    expect(errors, ['Server said no']);
    await sub.cancel();
  });

  test('deleting a project moves its tasks to the inbox', () async {
    final p = (await store.addProject('Old', 0xFF795548))!;
    await add('keep me', projectId: p.id);
    store.view = TodoView(ViewKind.project, p.id);

    await store.deleteProject(p.id);

    expect(store.view, TodoView.inbox);
    expect(titles(), ['keep me']);
  });

  test('deleting a tag removes it from tasks', () async {
    final tag = (await store.addTag('urgent', 0xFFF44336))!;
    final t = await add('fix bug');
    await store.updateTask(t.copyWith(tagIds: [tag.id]));

    store.view = TodoView(ViewKind.tag, tag.id);
    expect(titles(), ['fix bug']);

    await store.deleteTag(tag.id);
    expect(store.tasks.single.tagIds, isEmpty);
  });
}
