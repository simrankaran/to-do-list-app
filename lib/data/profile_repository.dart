import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'todo_repository.dart';

/// The signed-in user's profile picture.
abstract interface class ProfileRepository {
  /// Uploads [bytes] as the user's picture and returns its new URL.
  Future<String> uploadAvatar(Uint8List bytes, String contentType);

  Future<void> removeAvatar();
}

/// Stores the picture at `avatars/<user id>/avatar` in Supabase Storage and
/// its URL in the user's metadata (`avatar_url`).
class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  static const maxBytes = 2 * 1024 * 1024;

  String get _path => '${_client.auth.currentUser!.id}/avatar';

  @override
  Future<String> uploadAvatar(Uint8List bytes, String contentType) async {
    if (bytes.length > maxBytes) {
      throw const TodoException('That image is over 2 MB. Pick a smaller one.');
    }
    try {
      final bucket = _client.storage.from('avatars');
      await bucket.uploadBinary(
        _path,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: contentType),
      );
      // The nonce changes the URL so browsers don't show the old cached photo.
      final url = bucket.getPublicUrl(
        _path,
        cacheNonce: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      await _client.auth.updateUser(UserAttributes(data: {'avatar_url': url}));
      await _saveToProfile(url);
      return url;
    } on StorageException catch (e) {
      throw TodoException('Upload failed: ${e.message}');
    } on AuthException catch (e) {
      throw TodoException(e.message);
    } on PostgrestException catch (e) {
      throw TodoException(e.message);
    }
  }

  /// Copies the photo to the profile that connected people can see.
  Future<void> _saveToProfile(String? url) => _client.from('profiles').upsert({
    'id': _client.auth.currentUser!.id,
    'avatar_url': url,
  });

  @override
  Future<void> removeAvatar() async {
    try {
      await _client.storage.from('avatars').remove([_path]);
      await _client.auth.updateUser(UserAttributes(data: {'avatar_url': null}));
      await _saveToProfile(null);
    } on StorageException catch (e) {
      throw TodoException('Could not remove the photo: ${e.message}');
    } on AuthException catch (e) {
      throw TodoException(e.message);
    } on PostgrestException catch (e) {
      throw TodoException(e.message);
    }
  }
}
