import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'social_models.dart';
import 'todo_repository.dart';

/// Profiles, connections with other people, and chat. Nothing here can read
/// another person's tasks.
abstract interface class SocialRepository {
  String get myId;

  Future<Profile> fetchMyProfile();
  Future<Profile> updateMyProfile({
    required String displayName,
    required String bio,
  });

  Future<List<Connection>> fetchConnections();

  /// Asks the person with this email to connect. For privacy it never says
  /// whether the email belongs to an account.
  Future<void> sendRequest(String email);
  Future<void> acceptRequest(String connectionId);

  /// Declines, cancels or removes a connection.
  Future<void> removeConnection(String connectionId);

  /// The latest messages with [otherId], oldest first.
  Future<List<ChatMessage>> fetchMessages(String otherId);
  Future<void> sendMessage(String otherId, String body);
  Future<void> markRead(String otherId);

  /// Unread message counts by sender id.
  Future<Map<String, int>> unreadCounts();

  /// Fires when a message or connection changes, so screens can reload.
  Stream<void> get changes;
}

class SupabaseSocialRepository implements SocialRepository {
  SupabaseSocialRepository(this._db) {
    _changes = StreamController<void>.broadcast(
      onListen: _subscribe,
      onCancel: _unsubscribe,
    );
  }

  final SupabaseClient _db;
  late final StreamController<void> _changes;
  RealtimeChannel? _channel;

  @override
  String get myId => _db.auth.currentUser!.id;

  @override
  Stream<void> get changes => _changes.stream;

  // Row level security limits these events to rows that involve this user.
  void _subscribe() {
    void ping(PostgresChangePayload _) {
      if (!_changes.isClosed) _changes.add(null);
    }

    _channel = _db
        .channel('social-$myId-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: ping,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friendships',
          callback: ping,
        )
        .subscribe();
  }

  void _unsubscribe() {
    final channel = _channel;
    _channel = null;
    if (channel != null) _db.removeChannel(channel);
  }

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw TodoException(e.message);
    } on TodoException {
      rethrow;
    } catch (e) {
      throw TodoException(
        'Could not reach the server. Check your connection. ($e)',
      );
    }
  }

  @override
  Future<Profile> fetchMyProfile() => _guard(() async {
    final row = await _db
        .from('profiles')
        .select()
        .eq('id', myId)
        .maybeSingle();
    if (row != null) return Profile.fromJson(row);
    // Older accounts may not have a profile row yet.
    final email = _db.auth.currentUser?.email ?? '';
    final created = await _db
        .from('profiles')
        .upsert({'id': myId, 'display_name': email.split('@').first})
        .select()
        .single();
    return Profile.fromJson(created);
  });

  @override
  Future<Profile> updateMyProfile({
    required String displayName,
    required String bio,
  }) => _guard(() async {
    final row = await _db
        .from('profiles')
        .update({'display_name': displayName, 'bio': bio})
        .eq('id', myId)
        .select()
        .single();
    return Profile.fromJson(row);
  });

  @override
  Future<List<Connection>> fetchConnections() => _guard(() async {
    final rows = await _db.from('friendships').select().order('created_at');
    if (rows.isEmpty) return <Connection>[];
    final me = myId;
    final otherIds = {
      for (final r in rows)
        r['requester_id'] == me
            ? r['addressee_id'] as String
            : r['requester_id'] as String,
    };
    final profileRows = await _db
        .from('profiles')
        .select()
        .inFilter('id', otherIds.toList());
    final profiles = {
      for (final p in profileRows.map(Profile.fromJson)) p.id: p,
    };
    return [for (final r in rows) Connection.fromRow(r, me, profiles)];
  });

  @override
  Future<void> sendRequest(String email) => _guard(
    () => _db.rpc('send_friend_request', params: {'target_email': email}),
  );

  @override
  Future<void> acceptRequest(String connectionId) => _guard(
    () => _db
        .from('friendships')
        .update({'status': 'accepted'})
        .eq('id', connectionId),
  );

  @override
  Future<void> removeConnection(String connectionId) =>
      _guard(() => _db.from('friendships').delete().eq('id', connectionId));

  @override
  Future<List<ChatMessage>> fetchMessages(String otherId) => _guard(() async {
    final me = myId;
    final rows = await _db
        .from('messages')
        .select()
        .or(
          'and(sender_id.eq.$me,recipient_id.eq.$otherId),'
          'and(sender_id.eq.$otherId,recipient_id.eq.$me)',
        )
        .order('created_at', ascending: false)
        .limit(200);
    return rows.map(ChatMessage.fromJson).toList().reversed.toList();
  });

  @override
  Future<void> sendMessage(String otherId, String body) => _guard(
    () => _db.from('messages').insert({'recipient_id': otherId, 'body': body}),
  );

  @override
  Future<void> markRead(String otherId) => _guard(
    () => _db
        .from('messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('recipient_id', myId)
        .eq('sender_id', otherId)
        .isFilter('read_at', null),
  );

  @override
  Future<Map<String, int>> unreadCounts() => _guard(() async {
    final rows = await _db
        .from('messages')
        .select('sender_id')
        .eq('recipient_id', myId)
        .isFilter('read_at', null);
    final counts = <String, int>{};
    for (final r in rows) {
      final sender = r['sender_id'] as String;
      counts[sender] = (counts[sender] ?? 0) + 1;
    }
    return counts;
  });
}
