import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_app/app.dart';
import 'package:my_app/data/profile_repository.dart';
import 'package:my_app/features/common/image_source.dart';
import 'package:my_app/features/home/home_page.dart';

import 'fake_todo_repository.dart';

void main() {
  Future<FakeTodoRepository> pumpHome(
    WidgetTester tester, {
    Size size = const Size(500, 900),
  }) async {
    tester.view.physicalSize = size;
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
    return repo;
  }

  testWidgets('create, complete and swipe-delete a task with undo', (
    tester,
  ) async {
    final repo = await pumpHome(tester);
    expect(find.text('Nothing here. Enjoy the calm.'), findsOneWidget);

    await tester.tap(find.text('New task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Buy milk');
    await tester.tap(find.text('High'));
    await tester.tap(find.text('Today'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Buy milk'), findsOneWidget);
    expect(repo.tasks.single.title, 'Buy milk');
    expect(find.byTooltip('High priority'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(repo.tasks.single.done, isTrue);
    expect(find.text('Buy milk'), findsNothing); // completed tasks hidden

    await tester.tap(find.byTooltip('Show completed tasks'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Buy milk'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(repo.tasks, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repo.tasks, hasLength(1));
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('create a project and add a task with a subtask to it', (
    tester,
  ) async {
    final repo = await pumpHome(tester, size: const Size(1200, 900));

    // Wide layout shows the side panel without a drawer.
    await tester.tap(find.byTooltip('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Work');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(repo.projects.single.name, 'Work');

    await tester.tap(find.text('New task'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ship release');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.tasks.single.projectId, repo.projects.single.id);

    await tester.tap(find.text('Ship release'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a subtask'),
      'Write notes',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      repo.tasks.where((t) => t.parentId != null).single.title,
      'Write notes',
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('0/1'), findsOneWidget);
  });

  testWidgets('upload and remove a profile photo', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final profile = _FakeProfileRepository();
    await tester.pumpWidget(
      TodoApp(
        home: HomePage(
          repository: FakeTodoRepository(),
          profile: profile,
          userEmail: 'test@example.com',
          onSignOut: () async {},
          pickImage: () async =>
              PickedImage(Uint8List.fromList([1, 2, 3]), 'image/png'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Change profile photo'));
    await tester.pumpAndSettle();
    expect(find.text('Remove photo'), findsNothing);
    await tester.tap(find.text('Upload photo'));
    await tester.pumpAndSettle();

    expect(profile.uploads.single, [1, 2, 3]);
    expect(profile.contentTypes.single, 'image/png');
    expect(find.text('Profile photo updated'), findsOneWidget);

    await tester.tap(find.byTooltip('Change profile photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(profile.removed, isTrue);
    expect(find.text('Profile photo removed'), findsOneWidget);
  });
}

class _FakeProfileRepository implements ProfileRepository {
  final uploads = <List<int>>[];
  final contentTypes = <String>[];
  bool removed = false;

  @override
  Future<String> uploadAvatar(Uint8List bytes, String contentType) async {
    uploads.add(bytes);
    contentTypes.add(contentType);
    return 'https://example.com/avatar.png';
  }

  @override
  Future<void> removeAvatar() async => removed = true;
}
