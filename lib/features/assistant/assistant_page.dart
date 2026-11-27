import 'package:material_ui/material_ui.dart';

import '../../data/assistant_service.dart';
import '../../data/models.dart';
import '../../data/todo_repository.dart';
import '../../state/todo_store.dart';
import '../common/dialogs.dart';
import 'assistant_actions.dart';

class _Message {
  _Message.user(this.text, {this.isError = false})
    : fromUser = true,
      results = const [];
  _Message.assistant(this.text, {this.results = const [], this.isError = false})
    : fromUser = false;

  final bool fromUser;
  final String text;
  final List<ActionResult> results;

  /// A failed exchange: shown in the chat but left out of later requests.
  final bool isError;

  /// What the assistant is told it said and did, on later turns.
  String get asHistory => results.isEmpty
      ? text
      : '$text\n[The app did: ${results.map((r) => r.text).join('; ')}]';
}

/// Chat with the AI assistant, which adds and changes tasks for you.
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.store, required this.service});

  final TodoStore store;
  final AssistantService service;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  static const _suggestions = [
    'What do I have today?',
    'Add gym tomorrow from 6 to 7 pm',
    'Remind me to call mom every Sunday',
    'Move my overdue tasks to tomorrow',
  ];

  final _messages = <_Message>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<bool> _confirmDelete(Task task) => confirm(
    context,
    title: 'Delete “${task.title}”?',
    message: 'The assistant wants to delete this task and its subtasks.',
  );

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    // Earlier turns, without failed attempts.
    final history = [
      for (final m in _messages)
        if (!m.isError)
          m.fromUser ? ChatTurn.user(m.text) : ChatTurn.assistant(m.asHistory),
    ];
    setState(() {
      _messages.add(_Message.user(text));
      _busy = true;
    });
    _input.clear();
    _scrollToEnd();

    final snapshot = buildAssistantContext(widget.store);
    try {
      final reply = await widget.service.send(
        message: text,
        history: history,
        context: snapshot.text,
      );
      final results = await runAssistantActions(
        widget.store,
        reply.actions,
        snapshot.refs,
        confirmDelete: _confirmDelete,
      );
      if (!mounted) return;
      setState(
        () => _messages.add(_Message.assistant(reply.text, results: results)),
      );
    } on TodoException catch (e) {
      if (!mounted) return;
      setState(() {
        // Mark the unanswered question as failed so a retry doesn't send it
        // twice as history.
        _messages.removeLast();
        _messages.add(_Message.user(text, isError: true));
        _messages.add(_Message.assistant(e.message, isError: true));
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollToEnd();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, color: scheme.primary),
            const SizedBox(width: 8),
            const Text('Assistant'),
          ],
        ),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'Start a new chat',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _busy ? null : () => setState(_messages.clear),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? _Welcome(suggestions: _suggestions, onPick: _send)
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          itemCount: _messages.length + (_busy ? 1 : 0),
                          itemBuilder: (context, i) => i == _messages.length
                              ? const _Typing()
                              : _Bubble(message: _messages[i]),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 2000,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.send,
                          decoration: const InputDecoration(
                            hintText: 'Ask me to add or change tasks',
                            counterText: '',
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Send',
                        onPressed: _busy ? null : _send,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.suggestions, required this.onPick});

  final List<String> suggestions;
  final void Function(String text) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.tertiary],
                ),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 34,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Tell me what to do',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'I can add, change, complete and delete tasks for you.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            for (final s in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => onPick(s),
                    child: Text(s, textAlign: TextAlign.center),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final _Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mine = message.fromUser;
    final background = mine
        ? scheme.primary
        : message.isError
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final foreground = mine
        ? scheme.onPrimary
        : message.isError
        ? scheme.onErrorContainer
        : scheme.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                message.text,
                style: theme.textTheme.bodyLarge?.copyWith(color: foreground),
              ),
              for (final r in message.results)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        r.ok
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        size: 16,
                        color: r.ok ? const Color(0xFF16A34A) : scheme.outline,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          r.text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text('Thinking…', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
