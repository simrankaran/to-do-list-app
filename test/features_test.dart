import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_app/app.dart';
import 'package:my_app/data/models.dart';
import 'package:my_app/features/common/file_source.dart';
import 'package:my_app/features/common/user_avatar.dart';
import 'package:my_app/features/home/home_page.dart';
import 'package:my_app/features/tasks/attachments_section.dart';
import 'package:my_app/services/reminders.dart';
import 'package:my_app/state/todo_store.dart';

import 'fake_todo_repository.dart';

void main() {
  timeSlotTests();

  testWidgets('reminders follow task changes and clear on sign out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeTodoRepository();
    final start = DateTime.now().add(const Duration(hours: 2));
    repo.tasks.add(
      Task(
        id: 'gym',
        title: 'Gym',
        createdAt: DateTime.now(),
        dueAt: dateOnly(start),
        startsAt: start,
        endsAt: start.add(const Duration(hours: 1)),
      ),
    );
    final reminders = _FakeReminders();
    await tester.pumpWidget(
      TodoApp(
        home: HomePage(
          repository: repo,
          reminders: reminders,
          userEmail: 'test@example.com',
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    expect(reminders.syncs.last.single.id, 'gym');

    // Open the task, make it 2 hours long and save.
    // The task has no project, so it shows in the default Inbox view.
    // Rows also accept a double-tap, so a single tap only registers once
    // the double-tap window (300 ms) has passed.
    await tester.tap(find.text('Gym'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    // The editor has several scrollables (the page and its text fields), so
    // just bring the chip into view rather than scrolling a guessed one.
    await tester.ensureVisible(find.text('2 h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(reminders.permissionRequests, 1);
    expect(repo.tasks.single.endsAt, start.add(const Duration(hours: 2)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      reminders.syncs.last.single.endsAt,
      start.add(const Duration(hours: 2)),
    );

    // Signing out removes this account's reminders from the device.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(UserAvatar),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign out').first);
    await tester.pumpAndSettle();
    expect(reminders.syncs.last, isEmpty);
  });

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
    expect(find.text('Completed Â· last 7 days'), findsOneWidget);
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

class _FakeReminders implements ReminderScheduler {
  final syncs = <List<Task>>[];
  int permissionRequests = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> sync(List<Task> tasks) async => syncs.add([...tasks]);
}

void timeSlotTests() {
  test('a task is in progress only inside its time slot', () {
    final start = DateTime(2026, 11, 27, 9);
    final t = Task(
      id: 't',
      title: 'Gym',
      createdAt: start,
      startsAt: start,
      endsAt: start.add(const Duration(hours: 1)),
    );
    expect(t.isInProgress(start.subtract(const Duration(minutes: 1))), isFalse);
    expect(t.isInProgress(start), isTrue);
    expect(t.isInProgress(start.add(const Duration(minutes: 59))), isTrue);
    expect(t.isInProgress(start.add(const Duration(hours: 1))), isFalse);
    expect(t.copyWith(done: true).isInProgress(start), isFalse);

    final row = t.toRow();
    expect(row['starts_at'], start.toUtc().toIso8601String());
    expect(row['remind'], isTrue);
    expect(t.copyWith(startsAt: null, endsAt: null).hasTimeSlot, isFalse);
  });

  test('calendar lists timed tasks in start-time order', () async {
    final repo = FakeTodoRepository();
    final day = DateTime(2026, 11, 27);
    Task at(String id, int hour) => Task(
      id: id,
      title: id,
      createdAt: day,
      dueAt: day,
      startsAt: day.add(Duration(hours: hour)),
      endsAt: day.add(Duration(hours: hour + 1)),
    );
    repo.tasks.addAll([
      at('lunch', 13),
      Task(id: 'anytime', title: 'anytime', createdAt: day, dueAt: day),
      at('standup', 9),
    ]);
    final store = TodoStore(repo, clock: () => day);
    await store.load();
    expect(store.tasksDueOn(day).map((t) => t.id), [
      'standup',
      'lunch',
      'anytime',
    ]);
  });
}
