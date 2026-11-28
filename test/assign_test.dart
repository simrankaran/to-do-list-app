import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_app/app.dart';
import 'package:my_app/data/models.dart';
import 'package:my_app/data/social_models.dart';
import 'package:my_app/features/home/home_page.dart';
import 'package:my_app/features/tasks/task_editor_page.dart';
import 'package:my_app/state/todo_store.dart';

import 'fake_todo_repository.dart';

/// A task that Sam owns and has assigned to me.
Task fromSam(String id, String title, {RepeatRule repeat = RepeatRule.none}) =>
    Task(
      id: id,
      title: title,
      createdAt: DateTime(2026, 11, 28),
      dueAt: DateTime(2026, 11, 28),
      ownerId: 'sam',
      assigneeId: 'me',
      repeat: repeat,
    );

const sam = Profile(id: 'sam', displayName: 'Sam');

void main() {
  test('a task assigned to me can be finished but not deleted', () async {
    final repo = FakeTodoRepository()
      ..tasks.add(fromSam('t1', 'Review deck', repeat: RepeatRule.daily));
    final store = TodoStore(repo)..people = [sam];
    await store.load();
    final task = store.tasks.single;

    expect(store.isFromOther(task), isTrue);
    expect(store.partnerOf(task)?.name, 'Sam');

    final errors = <String>[];
    store.errors.listen(errors.add);
    expect(await store.deleteTask(task), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(repo.tasks, hasLength(1));
    expect(errors.single, 'Only Sam can delete this task.');

    // Finishing it must not start a repeating copy in my own list.
    await store.toggleDone(task);
    expect(repo.tasks.single.done, isTrue);
    expect(store.tasks, hasLength(1));
  });

  test('my own tasks are not treated as assigned to me', () async {
    final repo = FakeTodoRepository();
    final store = TodoStore(repo)..people = [sam];
    await store.load();
    final mine = (await store.addTask(
      Task.draft(title: 'Plan launch', assigneeId: 'sam'),
    ))!;

    expect(store.isFromOther(mine), isFalse);
    expect(store.partnerOf(mine)?.name, 'Sam'); // who I gave it to
    expect(await store.deleteTask(mine), isNotNull);
  });

  test('a refresh reports tasks newly assigned to me', () async {
    final repo = FakeTodoRepository();
    final store = TodoStore(repo);
    await store.load();

    repo.tasks.add(fromSam('t1', 'Review deck'));
    final arrived = await store.refreshShared();
    expect(arrived.single.title, 'Review deck');
    expect(await store.refreshShared(), isEmpty); // only reported once
  });

  testWidgets('the editor assigns a task to a connected person', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = FakeTodoRepository();
    final store = TodoStore(repo)..people = [sam];
    await store.load();

    await tester.pumpWidget(MaterialApp(home: TaskEditorPage(store: store)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Prepare slides');
    await tester.tap(find.text('Just me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sam').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Your other tasks stay private'), findsOne);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.tasks.single.title, 'Prepare slides');
    expect(repo.tasks.single.assigneeId, 'sam');
  });

  testWidgets('a task assigned to me opens read-only and can be marked done', (
    tester,
  ) async {
    final repo = FakeTodoRepository()
      ..tasks.add(fromSam('t1', 'Review deck'))
      ..attachments.add(
        Attachment(
          id: 'a1',
          taskId: 't1',
          name: 'demo.mp4',
          path: 'sam/t1/demo.mp4',
          mimeType: 'video/mp4',
          sizeBytes: 2048,
          createdAt: DateTime(2026, 11, 28),
        ),
      );
    final store = TodoStore(repo)..people = [sam];
    await store.load();

    await tester.pumpWidget(
      MaterialApp(
        home: TaskEditorPage(store: store, task: store.tasks.single),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('From Sam'), findsOneWidget);
    expect(find.text('Review deck'), findsOneWidget);
    expect(find.text('demo.mp4'), findsOneWidget); // their file, view only
    expect(find.text('Save'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.byTooltip('Delete demo.mp4'), findsNothing);
    expect(find.text('Add'), findsNothing);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(repo.tasks.single.inProgress, isTrue);

    await tester.tap(find.text('Mark done'));
    await tester.pumpAndSettle();
    expect(repo.tasks.single.done, isTrue);
    expect(find.text('Reopen'), findsOneWidget);
  });

  testWidgets('a newly assigned task appears on the home screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = FakeTodoRepository();
    await tester.pumpWidget(
      TodoApp(
        home: HomePage(
          repository: repo,
          userEmail: 'test@example.com',
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Review deck'), findsNothing);

    // The server says a shared task changed.
    repo.tasks.add(fromSam('t1', 'Review deck'));
    repo.shared.add(null);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Review deck'), findsOneWidget);
    expect(find.text('From Someone'), findsOneWidget);
    expect(find.text('Someone assigned you "Review deck"'), findsOneWidget);
  });
}
