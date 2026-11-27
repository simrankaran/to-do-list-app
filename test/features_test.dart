import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_app/app.dart';
import 'package:my_app/data/models.dart';
import 'package:my_app/features/common/file_source.dart';
import 'package:my_app/features/common/user_avatar.dart';
import 'package:my_app/features/home/home_page.dart';
import 'package:my_app/features/tasks/attachments_section.dart';
import 'package:my_app/features/tasks/task_editor_page.dart';
import 'package:my_app/services/reminders.dart';
import 'package:my_app/state/todo_store.dart';

import 'fake_todo_repository.dart';

void main() {
  timeSlotTests();

  Task gymAt(DateTime start) => Task(
    id: 'gym',
    title: 'Gym',
    createdAt: DateTime.now(),
    dueAt: dateOnly(start),
    startsAt: start,
    endsAt: start.add(const Duration(hours: 1)),
  );

  testWidgets('reminders are scheduled after loading and cleared on sign out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeTodoRepository();
    repo.tasks.add(gymAt(DateTime.now().add(const Duration(hours: 2))));
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
    // Reminders are rescheduled shortly (500 ms) after tasks change.
    await tester.pump(const Duration(milliseconds: 600));
    expect(reminders.syncs.last.single.id, 'gym');

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

  testWidgets('editor changes the time slot length and asks to notify', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeTodoRepository();
    final start = DateTime.now().add(const Duration(hours: 2));
    repo.tasks.add(gymAt(start));
    final reminders = _FakeReminders();
    final store = TodoStore(repo)..reminders = reminders;
    await store.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        TaskEditorPage(store: store, task: store.tasks.single),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('2 h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 h'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(reminders.permissionRequests, 1);
    expect(repo.tasks.single.endsAt, start.add(const Duration(hours: 2)));
    expect(find.text('Open'), findsOneWidget); // editor closed
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
    // Bring the stats into view directly; scrollUntilVisible needs exactly
    // one scrollable on screen, which the profile tab no longer guarantees.
    await tester.ensureVisible(find.text('Your progress'));
    await tester.pumpAndSettle();
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

  final previews = <(AlertStyle, AlertSound)>[];

  @override
  Future<bool> preview(AlertStyle style, AlertSound sound) async {
    previews.add((style, sound));
    return true;
  }
}

void timeSlotTests() {
  group('planAlerts', () {
    final now = DateTime(2026, 11, 27, 8);
    final start = DateTime(2026, 11, 27, 9);
    final end = DateTime(2026, 11, 27, 10);
    Task gym() => Task(
      id: 'gym',
      title: 'Gym',
      createdAt: now,
      startsAt: start,
      endsAt: end,
    );

    test('default task gets a start and an end alert', () {
      final alerts = planAlerts([gym()], now);
      expect(alerts.map((a) => a.at), [start, end]);
      expect(alerts[0].title, '▶ Time to start: Gym');
      expect(alerts[1].title, "⏹ Time's up: Gym");
      expect(alerts.map((a) => a.id).toSet(), hasLength(2));
      expect(alerts[0].style, AlertStyle.sound);
      expect(alerts[0].sound, AlertSound.standard);
    });

    test('early reminder, custom messages, style and sound are used', () {
      final task = gym().copyWith(
        earlyMinutes: 15,
        startMessage: ' Leave for the gym now! ',
        endMessage: 'Stop and stretch',
        alertStyle: AlertStyle.vibrate,
        alertSound: AlertSound.bell,
      );
      final alerts = planAlerts([task], now);
      expect(alerts.map((a) => a.at), [
        start.subtract(const Duration(minutes: 15)),
        start,
        end,
      ]);
      expect(alerts[0].title, '⏰ In 15 min: Gym');
      expect(alerts[1].title, 'Leave for the gym now!');
      expect(alerts[1].body, startsWith('Gym'));
      expect(alerts[2].title, 'Stop and stretch');
      expect(alerts.map((a) => a.id).toSet(), hasLength(3));
      expect(alerts.every((a) => a.style == AlertStyle.vibrate), isTrue);
      expect(alerts.every((a) => a.sound == AlertSound.bell), isTrue);
    });

    test('past alerts, finished tasks and muted tasks are skipped', () {
      final midway = start.add(const Duration(minutes: 30));
      final early = gym().copyWith(earlyMinutes: 30);
      expect(planAlerts([early], midway).map((a) => a.at), [end]);
      expect(planAlerts([gym().copyWith(done: true)], now), isEmpty);
      expect(planAlerts([gym().copyWith(remind: false)], now), isEmpty);
      expect(planAlerts([gym()], end), isEmpty);
    });

    test('alert preferences are saved to and read from the database row', () {
      final row = gym()
          .copyWith(
            earlyMinutes: 10,
            startMessage: 'Go',
            alertStyle: AlertStyle.silent,
            alertSound: AlertSound.digital,
          )
          .toRow();
      expect(row['early_minutes'], 10);
      expect(row['start_message'], 'Go');
      expect(row['end_message'], '');
      expect(row['alert_style'], 'silent');
      expect(row['alert_sound'], 'digital');
      expect(AlertStyle.parse('vibrate'), AlertStyle.vibrate);
      expect(AlertStyle.parse('nonsense'), AlertStyle.sound);
      expect(AlertSound.parse('default'), AlertSound.standard);
      expect(AlertSound.parse(null), AlertSound.standard);
    });
  });

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
