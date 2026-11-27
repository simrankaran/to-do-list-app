/// What other people can see about someone: never their tasks.
class Profile {
  const Profile({
    required this.id,
    this.displayName = '',
    this.bio = '',
    this.avatarUrl,
    this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    displayName: json['display_name'] as String? ?? '',
    bio: json['bio'] as String? ?? '',
    avatarUrl: json['avatar_url'] as String?,
    createdAt: json['created_at'] == null
        ? null
        : DateTime.parse(json['created_at'] as String).toLocal(),
  );

  final String id;
  final String displayName;
  final String bio;
  final String? avatarUrl;
  final DateTime? createdAt;

  /// A name that is never empty.
  String get name =>
      displayName.trim().isEmpty ? 'Someone' : displayName.trim();
}

enum LinkStatus {
  /// They asked to connect with me.
  incoming,

  /// I asked and they haven't answered.
  outgoing,

  /// We are connected and can chat.
  accepted,
}

/// My connection with another person.
class Connection {
  const Connection({
    required this.id,
    required this.person,
    required this.status,
  });

  /// Works out which side of a `friendships` row is the other person.
  factory Connection.fromRow(
    Map<String, dynamic> row,
    String myId,
    Map<String, Profile> profiles,
  ) {
    final requester = row['requester_id'] as String;
    final addressee = row['addressee_id'] as String;
    final iAsked = requester == myId;
    final otherId = iAsked ? addressee : requester;
    return Connection(
      id: row['id'] as String,
      person: profiles[otherId] ?? Profile(id: otherId),
      status: row['status'] == 'accepted'
          ? LinkStatus.accepted
          : (iAsked ? LinkStatus.outgoing : LinkStatus.incoming),
    );
  }

  final String id;
  final Profile person;
  final LinkStatus status;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    senderId: json['sender_id'] as String,
    recipientId: json['recipient_id'] as String,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    readAt: json['read_at'] == null
        ? null
        : DateTime.parse(json['read_at'] as String).toLocal(),
  );

  final String id;
  final String senderId;
  final String recipientId;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
}
