import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// A file the user chose to attach.
class PickedAttachment {
  const PickedAttachment(this.bytes, this.name, this.mimeType);
  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// Takes a photo with the camera, or picks one from the gallery.
/// Large photos are scaled down so uploads stay quick.
Future<PickedAttachment?> pickPhoto({required bool camera}) async {
  final file = await ImagePicker().pickImage(
    source: camera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 85,
  );
  if (file == null) return null;
  final name = file.name.isEmpty
      ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg'
      : file.name;
  return PickedAttachment(
    await file.readAsBytes(),
    name,
    file.mimeType ?? mimeTypeFor(name),
  );
}

/// Picks a PDF from the device.
Future<PickedAttachment?> pickPdf() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  if (files.isEmpty) return null;
  final file = files.first;
  return PickedAttachment(
    await file.readAsBytes(),
    file.name,
    'application/pdf',
  );
}

String mimeTypeFor(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.heic')) return 'image/heic';
  return 'image/jpeg';
}
