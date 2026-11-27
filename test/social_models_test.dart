import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/data/social_models.dart';

void main() {
  const me = 'me-id';
  const them = 'them-id';
  final profiles = {
    them: Profile.fromJson({
      'id': them,
      'display_name': '  Simran ',
      'bio': 'Hello',
      'avatar_url': 'https://example.com/a.png',
      'created_at': '2026-11-27T08:00:00Z',
    }),
  };

  Map<String, dynamic> row(String requester, String addressee, String status) =>
      {
        'id': 'f1',
        'requester_id': requester,
        'addressee_id': addressee,
        'status': status,
      };

  test('a profile always has a name to show', () {
    expect(profiles[them]!.name, 'Simran');
    expect(profiles[them]!.avatarUrl, 'https://example.com/a.png');
    expect(const Profile(id: 'x').name, 'Someone');
    expect(Profile.fromJson({'id': 'y'}).bio, '');
  });

  test('a connection knows who the other person is and who asked', () {
    final iAsked = Connection.fromRow(row(me, them, 'pending'), me, profiles);
    expect(iAsked.status, LinkStatus.outgoing);
    expect(iAsked.person.id, them);
    expect(iAsked.person.name, 'Simran');

    final theyAsked = Connection.fromRow(
      row(them, me, 'pending'),
      me,
      profiles,
    );
    expect(theyAsked.status, LinkStatus.incoming);
    expect(theyAsked.person.id, them);

    final accepted = Connection.fromRow(
      row(them, me, 'accepted'),
      me,
      profiles,
    );
    expect(accepted.status, LinkStatus.accepted);
  });

  test('a connection without a loaded profile still shows a placeholder', () {
    final c = Connection.fromRow(row(me, 'stranger', 'accepted'), me, profiles);
    expect(c.person.id, 'stranger');
    expect(c.person.name, 'Someone');
  });

  test('messages are read from JSON', () {
    final m = ChatMessage.fromJson({
      'id': 'm1',
      'sender_id': me,
      'recipient_id': them,
      'body': 'hi',
      'created_at': '2026-11-27T08:00:00Z',
      'read_at': null,
    });
    expect(m.body, 'hi');
    expect(m.senderId, me);
    expect(m.readAt, isNull);
    expect(m.createdAt.toUtc(), DateTime.utc(2026, 11, 27, 8));
  });
}
