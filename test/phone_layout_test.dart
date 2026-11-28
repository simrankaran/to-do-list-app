import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_app/app.dart';
import 'package:my_app/data/models.dart';
import 'package:my_app/features/home/home_page.dart';

import 'fake_todo_repository.dart';

/// The phone layout must fit every common phone size, in portrait and
/// landscape, including with a large system font. Any overflow fails the
/// test.
void main() {
  const sizes = {
    'small phone': Size(320, 640),
    'regular phone': Size(393, 852),
    'large phone': Size(430, 932),
    'phone sideways': Size(915, 412),
    'tablet': Size(820, 1180),
  };

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('$name ($size) shows the full phone layout', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = FakeTodoRepository();
      final today = DateTime.now();
      await repo.createProject('A project with a fairly long name', 0xFF2196F3);
      for (var i = 0; i < 6; i++) {
        repo.tasks.add(
          Task(
            id: 't$i',
            title: 'Task number $i with a long title that needs to wrap nicely',
            createdAt: today,
            dueAt: DateTime(today.year, today.month, today.day),
            priority: Priority.values[i % 4],
          ),
        );
      }

      await tester.pumpWidget(
        TodoApp(
          home: HomePage(
            repository: repo,
            userEmail: 'someone.with.a.long.email@example.com',
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Phones and tablets always get the bottom tab bar, never the side
      // panel, whatever their width or orientation.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
      expect(find.byTooltip('More options'), findsOneWidget);

      // Visit every tab; an overflow anywhere fails the test.
      for (final icon in [
        Icons.search_rounded,
        Icons.calendar_month_outlined,
        Icons.home_outlined,
      ]) {
        await tester.tap(find.byIcon(icon).first);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a very large system font is capped so the layout still fits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      TodoApp(
        home: HomePage(
          repository: FakeTodoRepository(),
          userEmail: 'test@example.com',
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(NavigationBar));
    expect(MediaQuery.textScalerOf(context).scale(10), 13);
    expect(tester.takeException(), isNull);
  });
}
