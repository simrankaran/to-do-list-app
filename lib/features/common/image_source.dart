import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// An image the user chose, ready to upload.
class PickedImage {
  const PickedImage(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

/// Opens the system picker for a profile photo, scaled down to at most
/// 512×512 so uploads stay small. Returns null if the user cancels.
Future<PickedImage?> pickProfileImage() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 512,
    maxHeight: 512,
    imageQuality: 85,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return PickedImage(bytes, file.mimeType ?? _guessType(file.name));
}

String _guessType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}
