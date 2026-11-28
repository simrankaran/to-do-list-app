import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:my_app/data/social_models.dart';
import 'package:my_app/data/social_repository.dart';
import 'package:my_app/features/social/chat_page.dart';

void main() {
  testWidgets('a message is deleted from the server once it is seen', (
    tester,
  ) async {
    final social = _FakeSocial();
    social.server.add(social.message('m1', from: 'them', body: 'Hello there'));

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          social: social,
          person: const Profile(id: 'them', displayName: 'Sam'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Shown to the reader, and gone from the server.
    expect(find.text('Hello there'), findsOneWidget);
    expect(social.server, isEmpty);
    expect(social.deleted, ['m1']);

    // It stays on screen while the chat is open, even after a reload.
    social.ping();
    await tester.pumpAndSettle();
    expect(find.text('Hello there'), findsOneWidget);
  });

  testWidgets('my message stays until the other person sees it', (
    tester,
  ) async {
    final social = _FakeSocial();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          social: social,
          person: const Profile(id: 'them', displayName: 'Sam'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Are you free?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    // Unseen: still stored, never deleted by the sender's own screen.
    expect(social.server.single.body, 'Are you free?');
    expect(social.deleted, isEmpty);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // The other person sees it, so it leaves the server; the sender's
    // screen shows it as seen.
    social.server.clear();
    social.ping();
    await tester.pumpAndSettle();
    expect(find.text('Are you free?'), findsOneWidget);
    expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
  });
}

class _FakeSocial implements SocialRepository {
  final server = <ChatMessage>[];
  final deleted = <String>[];
  final _changes = StreamController<void>.broadcast();
  var _next = 0;

  void ping() => _changes.add(null);

  ChatMessage message(String id, {required String from, required String body}) {
    return ChatMessage(
      id: id,
      senderId: from,
      recipientId: from == 'me' ? 'them' : 'me',
      body: body,
      createdAt: DateTime(2026, 11, 28, 10, _next++),
    );
  }

  @override
  String get myId => 'me';

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<ChatMessage>> fetchMessages(String otherId) async => [...server];

  @override
  Future<void> sendMessage(String otherId, String body) async {
    server.add(message('sent$_next', from: 'me', body: body));
  }

  @override
  Future<void> deleteSeen(List<String> messageIds) async {
    deleted.addAll(messageIds);
    server.removeWhere(
      (m) => m.recipientId == 'me' && messageIds.contains(m.id),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
