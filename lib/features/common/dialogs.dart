import 'package:material_ui/material_ui.dart';

import '../../core/palette.dart';

/// Asks for a name and color (used for projects and tags).
Future<(String, int)?> showNameColorDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
  int? initialColor,
}) {
  return showDialog<(String, int)>(
    context: context,
    builder: (_) => _NameColorDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
      initialColor: initialColor ?? labelPalette.first,
    ),
  );
}

class _NameColorDialog extends StatefulWidget {
  const _NameColorDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.initialColor,
  });

  final String title;
  final String confirmLabel;
  final String initialName;
  final int initialColor;

  @override
  State<_NameColorDialog> createState() => _NameColorDialogState();
}

class _NameColorDialogState extends State<_NameColorDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  late int _color = widget.initialColor;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, (name, _color));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 50,
              decoration: const InputDecoration(labelText: 'Name'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in labelPalette)
                  InkResponse(
                    onTap: () => setState(() => _color = c),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(c),
                      child: c == _color
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}
