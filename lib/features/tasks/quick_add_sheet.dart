import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/todo_store.dart';

/// Bottom sheet for adding a task quickly. "More details" hands the typed
/// title to [onMoreDetails] to open the full editor.
Future<void> showQuickAddSheet(
  BuildContext context, {
  required TodoStore store,
  required void Function(String title) onMoreDetails,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _QuickAddSheet(store: store, onMoreDetails: onMoreDetails),
  );
}

class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet({required this.store, required this.onMoreDetails});

  final TodoStore store;
  final void Function(String title) onMoreDetails;

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    final saved = await widget.store.addTask(widget.store.draftForView(title));
    if (!mounted) return;
    if (saved != null) {
      HapticFeedback.lightImpact();
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  void _moreDetails() {
    final title = _controller.text.trim();
    Navigator.pop(context);
    widget.onMoreDetails(title);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = widget.store;
    final where =
        store.view.kind == ViewKind.project || store.view.kind == ViewKind.tag
        ? store.titleOf(store.view)
        : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New task', style: theme.textTheme.titleLarge),
          if (where != null)
            Text(
              'Adding to $where',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'What needs doing?'),
            onSubmitted: (_) => _add(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton.icon(
                onPressed: _saving ? null : _moreDetails,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('More details'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _add,
                child: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
