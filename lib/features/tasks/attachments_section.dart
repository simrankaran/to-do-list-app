import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../state/todo_store.dart';
import '../common/dialogs.dart';
import '../common/file_source.dart';

/// Photos, videos, PDFs and presentations saved on a task: thumbnails, add,
/// open and delete.
class AttachmentsSection extends StatefulWidget {
  const AttachmentsSection({
    super.key,
    required this.store,
    required this.task,
    this.photoPicker = pickPhoto,
    this.pdfPicker = pickPdf,
    this.videoPicker = pickVideo,
    this.presentationPicker = pickPresentation,
    this.readOnly = false,
  });

  final TodoStore store;
  final Task task;
  final Future<PickedAttachment?> Function({required bool camera}) photoPicker;
  final Future<PickedAttachment?> Function() pdfPicker;
  final Future<PickedAttachment?> Function() videoPicker;
  final Future<PickedAttachment?> Function() presentationPicker;

  /// View only: for a task another person assigned to me.
  final bool readOnly;

  @override
  State<AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends State<AttachmentsSection> {
  final _urls = <String, Future<String?>>{};
  int _uploading = 0;

  Future<String?> _url(Attachment a) =>
      _urls.putIfAbsent(a.id, () => widget.store.attachmentUrl(a));

  Future<void> _add(Future<PickedAttachment?> Function() pick) async {
    PickedAttachment? file;
    try {
      file = await pick();
    } catch (e) {
      _snack('Could not open the picker: $e');
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _uploading++);
    final saved = await widget.store.addAttachment(
      widget.task.id,
      file.bytes,
      file.name,
      file.mimeType,
    );
    if (!mounted) return;
    setState(() => _uploading--);
    if (saved != null) _snack('Saved ${saved.name}');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showAddMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        // Scrolls on short screens (a phone held sideways).
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take photo'),
                onTap: () {
                  Navigator.pop(sheet);
                  _add(() => widget.photoPicker(camera: true));
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose photo'),
                onTap: () {
                  Navigator.pop(sheet);
                  _add(() => widget.photoPicker(camera: false));
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Choose PDF'),
                onTap: () {
                  Navigator.pop(sheet);
                  _add(widget.pdfPicker);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Choose video'),
                subtitle: const Text('Up to 50 MB'),
                onTap: () {
                  Navigator.pop(sheet);
                  _add(widget.videoPicker);
                },
              ),
              ListTile(
                leading: const Icon(Icons.slideshow_outlined),
                title: const Text('Choose presentation'),
                subtitle: const Text('PowerPoint (.ppt, .pptx)'),
                onTap: () {
                  Navigator.pop(sheet);
                  _add(widget.presentationPicker);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(Attachment a) async {
    final url = await _url(a);
    if (url == null || !mounted) return;
    if (a.isImage) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _PhotoViewer(attachment: a, url: url),
        ),
      );
    } else {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) _snack('No app could open this file.');
    }
  }

  Future<void> _delete(Attachment a) async {
    final ok = await confirm(
      context,
      title: 'Delete ${a.name}?',
      message: 'The file is removed from this task.',
    );
    if (ok) {
      _urls.remove(a.id);
      await widget.store.deleteAttachment(a);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final files = widget.store.attachmentsOf(widget.task.id);
        if (widget.readOnly && files.isEmpty) {
          return Text(
            'No files on this task.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final a in files)
              _Thumb(
                key: ValueKey(a.id),
                attachment: a,
                url: a.isImage ? _url(a) : null,
                onTap: () => _open(a),
                onDelete: widget.readOnly ? null : () => _delete(a),
              ),
            for (var i = 0; i < _uploading; i++) const _UploadingThumb(),
            if (!widget.readOnly) _AddThumb(onTap: _showAddMenu),
          ],
        );
      },
    );
  }
}

const double _thumbSize = 96;

class _Thumb extends StatelessWidget {
  const _Thumb({
    super.key,
    required this.attachment,
    required this.onTap,
    this.onDelete,
    this.url,
  });

  final Attachment attachment;
  final Future<String?>? url;
  final VoidCallback onTap;

  /// Null when the file can only be viewed.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, iconColor) = attachment.isVideo
        ? (Icons.play_circle_fill_rounded, scheme.primary)
        : attachment.isPresentation
        ? (Icons.slideshow_rounded, scheme.tertiary)
        : (Icons.picture_as_pdf_rounded, scheme.error);

    final Widget content;
    if (attachment.isImage && url != null) {
      content = FutureBuilder<String?>(
        future: url,
        builder: (context, snap) => snap.data == null
            ? Center(child: Icon(Icons.image_outlined, color: scheme.outline))
            : Image.network(
                snap.data!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: scheme.outline,
                  ),
                ),
              ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 34, color: iconColor),
            const SizedBox(height: 4),
            Text(
              attachment.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0),
            ),
          ],
        ),
      );
    }

    return Tooltip(
      message: '${attachment.name} · ${attachment.sizeLabel}',
      child: SizedBox.square(
        dimension: _thumbSize,
        child: Stack(
          children: [
            Positioned.fill(
              child: Material(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  onLongPress: onDelete,
                  child: content,
                ),
              ),
            ),
            if (onDelete != null)
              Positioned(
                right: 2,
                top: 2,
                child: IconButton.filledTonal(
                  tooltip: 'Delete ${attachment.name}',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: onDelete,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UploadingThumb extends StatelessWidget {
  const _UploadingThumb();

  @override
  Widget build(BuildContext context) => Container(
    width: _thumbSize,
    height: _thumbSize,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
    ),
    padding: const EdgeInsets.all(34),
    child: const CircularProgressIndicator(strokeWidth: 2.5),
  );
}

class _AddThumb extends StatelessWidget {
  const _AddThumb({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Add photo or PDF',
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outline, width: 1.5),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          onTap: onTap,
          child: SizedBox.square(
            dimension: _thumbSize,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate_outlined, color: scheme.primary),
                const SizedBox(height: 4),
                Text('Add', style: TextStyle(color: scheme.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen photo with pinch-to-zoom and a download button.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.attachment, required this.url});

  final Attachment attachment;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(attachment.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Download',
            icon: const Icon(Icons.download_rounded),
            onPressed: () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Image.network(
            url,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const CircularProgressIndicator(color: Colors.white),
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}
