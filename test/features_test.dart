import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_app/app.dart';
import 'package:my_app/data/models.dart';
import 'package:my_app/features/common/file_source.dart';
import 'package:my_app/features/common/user_avatar.dart';
import 'package:my_app/features/home/home_page.dart';
import 'package:my_app/features/tasks/attachments_section.dart';
import 'package:my_app/state/todo_store.dart';

import 'fake_todo_repository.dart';

void main() {
  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('calendar tab shows due tasks and adds one on a day', (
    tester,
  ) async {
    phoneSize(tester);
    final repo = FakeTodoRepository();
    final today = dateOnly(DateTime.now());
    repo.tasks.add(
      Task(id: 'x', title: 'Pay rent', createdAt: today, dueAt: today),
    );
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

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Pay rent'), findsOneWidget);
    expect(find.text('1 task'), findsOneWidget);

    await tester.tap(find.byTooltip('Add task on this day'));
    await tester.pumpAndSettle();
    expect(find.text('Due Today'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'What needs doing?'),
      'Buy flowers',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final added = repo.tasks.firstWhere((t) => t.title == 'Buy flowers');
    expect(added.dueAt, today);
    expect(find.text('2 tasks'), findsOneWidget);
  });

  testWidgets('profile tab shows streak stats', (tester) async {
    phoneSize(tester);
    final repo = FakeTodoRepository();
    final now = DateTime.now();
    repo.tasks.add(
      Task(
        id: 'd',
        title: 'Done thing',
        createdAt: now,
        done: true,
        completedAt: now,
      ),
    );
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

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(UserAvatar),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Your progress'), 200);
    expect(find.text('day streak'), findsOneWidget);
    expect(find.text('best streak'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Completed · last 7 days'), findsOneWidget);
  });

  testWidgets('attach a photo and a PDF to a task', (tester) async {
    final repo = FakeTodoRepository();
    final store = TodoStore(repo);
    await store.load();
    final task = (await store.addTask(Task.draft(title: 'Trip')))!;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentsSection(
            store: store,
            task: task,
            photoPicker: ({required bool camera}) async => PickedAttachment(
              Uint8List.fromList([1, 2, 3]),
              camera ? 'camera.jpg' : 'beach.jpg',
              'image/jpeg',
            ),
            pdfPicker: () async => PickedAttachment(
              Uint8List.fromList([4, 5]),
              'ticket.pdf',
              'application/pdf',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose photo'));
    await tester.pumpAndSettle();
    expect(repo.attachments.single.name, 'beach.jpg');

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose PDF'));
    await tester.pumpAndSettle();
    expect(repo.attachments.map((a) => a.name), ['beach.jpg', 'ticket.pdf']);
    expect(find.text('ticket.pdf'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete ticket.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repo.attachments.single.name, 'beach.jpg');
  });
}
