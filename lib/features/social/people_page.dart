import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/social_models.dart';
import '../../data/social_repository.dart';
import '../../data/todo_repository.dart';
import '../common/dialogs.dart';
import '../common/user_avatar.dart';
import 'chat_page.dart';

/// Shows what you are allowed to see about another person: their profile.
Future<void> showProfileSheet(BuildContext context, Profile person) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UserAvatar(name: person.name, url: person.avatarUrl, radius: 48),
              const SizedBox(height: 12),
              Text(
                person.name,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              if (person.bio.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  person.bio.trim(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (person.createdAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Joined ${DateFormat.yMMMM().format(person.createdAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tasks are private. You can see each other\'s '
                        'profile and chat, but never each other\'s tasks.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Friends, requests, and adding people by email.
class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key, required this.social, this.myEmail});

  final SocialRepository social;
  final String? myEmail;

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  List<Connection> _connections = [];
  Map<String, int> _unread = {};
  bool _loading = true;
  String? _error;
  StreamSubscription<void>? _sub;

  SocialRepository get social => widget.social;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = social.changes.listen((_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final connections = await social.fetchConnections();
      final unread = await social.unreadCounts();
      if (!mounted) return;
      setState(() {
        _connections = connections;
        _unread = unread;
        _error = null;
        _loading = false;
      });
    } on TodoException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, [String? done]) async {
    try {
      await action();
      if (done != null) _snack(done);
      await _load(quiet: true);
    } on TodoException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _addPerson() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a person'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the email they use for Tasks. They get a request and '
                'can chat with you once they accept.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Their email',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                onSubmitted: (v) => Navigator.pop(context, v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    final typed = email?.trim().toLowerCase() ?? '';
    if (typed.isEmpty) return;
    if (!typed.contains('@')) {
      _snack('That doesn\'t look like an email address.');
      return;
    }
    if (typed == widget.myEmail?.toLowerCase()) {
      _snack('That\'s your own email.');
      return;
    }
    await _run(
      () => social.sendRequest(typed),
      'If $typed has a Tasks account, they\'ll get your request.',
    );
  }

  Future<void> _remove(Connection c, String title, String message) async {
    final ok = await confirm(
      context,
      title: title,
      message: message,
      action: 'Remove',
    );
    if (ok) await _run(() => social.removeConnection(c.id));
  }

  void _openChat(Connection c) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ChatPage(social: social, person: c.person),
          ),
        )
        .then((_) => _load(quiet: true));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final incoming = _connections
        .where((c) => c.status == LinkStatus.incoming)
        .toList();
    final friends = _connections
        .where((c) => c.status == LinkStatus.accepted)
        .toList();
    final outgoing = _connections
        .where((c) => c.status == LinkStatus.outgoing)
        .toList();

    Widget header(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    Widget avatar(Connection c) => GestureDetector(
      onTap: () => showProfileSheet(context, c.person),
      child: UserAvatar(
        name: c.person.name,
        url: c.person.avatarUrl,
        radius: 22,
      ),
    );

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    } else if (_connections.isEmpty) {
      body = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_alt_outlined, size: 56, color: scheme.outline),
              const SizedBox(height: 12),
              Text('No people yet', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Add someone by email to chat with them. '
                'Your tasks stay private.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _addPerson,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Add a person'),
              ),
            ],
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (incoming.isNotEmpty) header('Requests'),
            for (final c in incoming)
              ListTile(
                leading: avatar(c),
                title: Text(c.person.name, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Wants to connect'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Decline',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () =>
                          _run(() => social.removeConnection(c.id)),
                    ),
                    IconButton.filled(
                      tooltip: 'Accept',
                      icon: const Icon(Icons.check_rounded),
                      onPressed: () => _run(
                        () => social.acceptRequest(c.id),
                        'You and ${c.person.name} can now chat.',
                      ),
                    ),
                  ],
                ),
              ),
            if (friends.isNotEmpty) header('Friends'),
            for (final c in friends)
              ListTile(
                leading: avatar(c),
                title: Text(c.person.name, overflow: TextOverflow.ellipsis),
                subtitle: c.person.bio.trim().isEmpty
                    ? null
                    : Text(
                        c.person.bio.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((_unread[c.person.id] ?? 0) > 0)
                      Badge(label: Text('${_unread[c.person.id]}')),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      onSelected: (v) => v == 'profile'
                          ? showProfileSheet(context, c.person)
                          : _remove(
                              c,
                              'Remove ${c.person.name}?',
                              'You won\'t be able to chat until you connect again.',
                            ),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'profile',
                          child: Text('View profile'),
                        ),
                        PopupMenuItem(value: 'remove', child: Text('Remove')),
                      ],
                    ),
                  ],
                ),
                onTap: () => _openChat(c),
              ),
            if (outgoing.isNotEmpty) header('Waiting for a reply'),
            for (final c in outgoing)
              ListTile(
                // Their profile stays hidden until they accept.
                leading: const CircleAvatar(
                  radius: 22,
                  child: Icon(Icons.hourglass_top_rounded),
                ),
                title: Text(c.label, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Request sent'),
                trailing: TextButton(
                  onPressed: () => _run(() => social.removeConnection(c.id)),
                  child: const Text('Cancel'),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          IconButton(
            tooltip: 'Add a person',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: _addPerson,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: body,
        ),
      ),
    );
  }
}
