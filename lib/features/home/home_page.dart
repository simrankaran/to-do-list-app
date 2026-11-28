import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/assistant_service.dart';
import '../../data/models.dart';
import '../../data/profile_repository.dart';
import '../../data/todo_repository.dart';
import '../../data/social_models.dart';
import '../../data/social_repository.dart';
import '../../services/app_settings.dart';
import '../../services/reminders.dart';
import '../../services/sound_effects.dart';
import '../../state/todo_store.dart';
import '../assistant/assistant_page.dart';
import '../board/board_page.dart';
import '../common/celebration.dart';
import '../common/image_source.dart';
import '../common/user_avatar.dart';
import '../social/people_page.dart';
import '../social/settings_page.dart';
import '../tasks/task_editor_page.dart';
import '../tasks/task_tile.dart';
import 'mobile_home.dart';
import 'nav_panel.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.onSignOut,
    this.userEmail,
    this.avatarUrl,
    this.profile,
    this.pickImage = pickProfileImage,
    this.reminders = const NoReminders(),
    this.assistant,
    this.homeWidget,
    this.social,
    this.settings,
    this.sounds = const SilentSoundPlayer(),
    this.allowDesktopLayout,
  });

  /// Whether a wide window may use the desktop layout (side panel). Phones
  /// and tablets always get the full-featured phone layout, in any
  /// orientation; the desktop layout is for browsers and computers. Null
  /// decides from the platform.
  final bool? allowDesktopLayout;

  static bool get _desktopPlatform =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  /// Theme, sound and confetti choices; without it there are no
  /// celebrations and Settings has no Appearance section.
  final AppSettings? settings;
  final SoundPlayer sounds;

  /// The AI assistant; without it the assistant button is hidden.
  final AssistantService? assistant;

  /// Refreshes the home screen widget; called with null tasks on sign-out.
  final Future<void> Function(List<Task>? tasks, DateTime now)? homeWidget;

  /// People, chat and the shared profile; without it those screens are hidden.
  final SocialRepository? social;

  final TodoRepository repository;
  final Future<void> Function() onSignOut;
  final String? userEmail;
  final String? avatarUrl;

  /// Profile-picture storage. Without it the photo can't be changed.
  final ProfileRepository? profile;

  /// Lets the user choose a photo (replaced in tests).
  final Future<PickedImage?> Function() pickImage;

  /// Phone notifications for task start and end times.
  final ReminderScheduler reminders;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _wideLayout = 900.0;

  late final TodoStore _store;
  late final StreamSubscription<String> _errorSub;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _search = TextEditingController();
  late String? _avatarUrl = widget.avatarUrl;

  // Kept from the first build so its live connection isn't recreated.
  late final SocialRepository? _social = widget.social;
  final _celebration = GlobalKey<CelebrationOverlayState>();
  final _boardCelebration = GlobalKey<CelebrationOverlayState>();
  late final StreamSubscription<Completion> _completionSub;
  StreamSubscription<void>? _socialSub;

  /// Unread chat messages plus requests waiting for an answer.
  int _peopleBadge = 0;
  bool _avatarBusy = false;

  @override
  void initState() {
    super.initState();
    _store = TodoStore(widget.repository)..load();
    _errorSub = _store.errors.listen(_showMessage);
    _completionSub = _store.completions.listen(_celebrate);
    _store.reminders = widget.reminders;
    _store.addListener(_queueReminderSync);
    final social = _social;
    if (social != null) {
      _refreshPeopleBadge();
      _socialSub = social.changes.listen((_) => _refreshPeopleBadge());
    }
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.avatarUrl != oldWidget.avatarUrl) _avatarUrl = widget.avatarUrl;
  }

  Future<void> _changeAvatar() async {
    final profile = widget.profile;
    if (profile == null || _avatarBusy) return;
    final image = await widget.pickImage();
    if (image == null || !mounted) return;
    setState(() => _avatarBusy = true);
    try {
      final url = await profile.uploadAvatar(image.bytes, image.contentType);
      if (mounted) setState(() => _avatarUrl = url);
      _showMessage('Profile photo updated');
    } on TodoException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Could not upload the photo: $e');
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    final profile = widget.profile;
    if (profile == null || _avatarBusy) return;
    setState(() => _avatarBusy = true);
    try {
      await profile.removeAvatar();
      if (mounted) setState(() => _avatarUrl = null);
      _showMessage('Profile photo removed');
    } on TodoException catch (e) {
      _showMessage(e.message);
    } catch (e) {
      _showMessage('Could not remove the photo: $e');
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  @override
  void dispose() {
    _errorSub.cancel();
    _completionSub.cancel();
    _reminderTimer?.cancel();
    _socialSub?.cancel();
    _store.removeListener(_queueReminderSync);
    _store.dispose();
    _search.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openEditor([Task? task, String? initialTitle, DateTime? initialDueAt]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: task == null,
        builder: (_) => TaskEditorPage(
          store: _store,
          task: task,
          initialTitle: initialTitle,
          initialDueAt: initialDueAt,
        ),
      ),
    );
  }

  Future<void> _delete(Task task) async {
    final messenger = ScaffoldMessenger.of(context);
    final removed = await _store.deleteTask(task);
    if (removed == null || !mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${task.title}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _store.restore(removed),
          ),
        ),
      );
  }

  Timer? _reminderTimer;

  /// Reschedules notifications shortly after tasks change, once per burst.
  void _queueReminderSync() {
    if (_store.loading) return;
    _reminderTimer?.cancel();
    _reminderTimer = Timer(const Duration(milliseconds: 500), () {
      widget.reminders.sync(_store.tasks);
      widget.homeWidget?.call(_store.tasks, DateTime.now());
    });
  }

  Future<void> _refreshPeopleBadge() async {
    final social = _social;
    if (social == null) return;
    try {
      final unread = await social.unreadCounts();
      final connections = await social.fetchConnections();
      final count =
          unread.values.fold<int>(0, (sum, n) => sum + n) +
          connections.where((c) => c.status == LinkStatus.incoming).length;
      if (mounted && count != _peopleBadge) {
        setState(() => _peopleBadge = count);
      }
    } on TodoException {
      // The badge is a nicety; the People screen shows real errors.
    }
  }

  void _openPeople() {
    final social = _social;
    if (social == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                PeoplePage(social: social, myEmail: widget.userEmail),
          ),
        )
        .then((_) => _refreshPeopleBadge());
  }

  void _openSettings() {
    final social = _social;
    if (social == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          appSettings: widget.settings,
          social: social,
          profile: widget.profile,
          pickImage: widget.pickImage,
          email: widget.userEmail,
          avatarUrl: _avatarUrl,
          onAvatarChanged: (url) {
            if (mounted) setState(() => _avatarUrl = url);
          },
          onSignOut: _signOut,
        ),
      ),
    );
  }

  void _openBoard() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CelebrationOverlay(
          key: _boardCelebration,
          child: BoardPage(store: _store, onOpen: _openEditor),
        ),
      ),
    );
  }

  /// Sound and confetti when a task is finished, bigger when today is clear.
  void _celebrate(Completion c) {
    final settings = widget.settings;
    if (settings == null) return;
    // Celebrate on whichever screen is showing: the board or home.
    final overlay = _boardCelebration.currentState ?? _celebration.currentState;
    if (c.clearedToday) {
      if (settings.sounds) widget.sounds.play(SoundEffect.allDone);
      if (settings.celebrations) overlay?.bigBurst();
      _showMessage('🎉 All done for today. Nice work!');
    } else {
      if (settings.sounds) widget.sounds.play(SoundEffect.complete);
      if (settings.celebrations) overlay?.burst();
    }
  }

  void _openAssistant() {
    final service = widget.assistant;
    if (service == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssistantPage(store: _store, service: service),
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      // Don't leave this account's reminders on the device.
      _reminderTimer?.cancel();
      await widget.reminders.sync(const []);
      await widget.homeWidget?.call(null, DateTime.now());
      await widget.onSignOut();
    } catch (e) {
      _showMessage('Could not sign out: $e');
    }
  }

  void _clearSearch() {
    _search.clear();
    _store.query = '';
  }

  @override
  Widget build(BuildContext context) =>
      CelebrationOverlay(key: _celebration, child: _content(context));

  Widget _content(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final wide =
            (widget.allowDesktopLayout ?? HomePage._desktopPlatform) &&
            MediaQuery.sizeOf(context).width >= _wideLayout;
        if (!wide) {
          return MobileHome(
            store: _store,
            userEmail: widget.userEmail,
            avatarUrl: _avatarUrl,
            avatarBusy: _avatarBusy,
            onChangeAvatar: widget.profile == null ? null : _changeAvatar,
            onRemoveAvatar: widget.profile == null || _avatarUrl == null
                ? null
                : _removeAvatar,
            onSignOut: _signOut,
            onOpenEditor: _openEditor,
            onDelete: _delete,
            onOpenAssistant: widget.assistant == null ? null : _openAssistant,
            onOpenBoard: _openBoard,
            onOpenPeople: _social == null ? null : _openPeople,
            onOpenSettings: _social == null ? null : _openSettings,
            peopleBadge: _peopleBadge,
          );
        }
        final nav = NavPanel(
          store: _store,
          userEmail: widget.userEmail,
          avatarUrl: _avatarUrl,
          avatarBusy: _avatarBusy,
          onChangeAvatar: widget.profile == null ? null : _changeAvatar,
          onRemoveAvatar: widget.profile == null || _avatarUrl == null
              ? null
              : _removeAvatar,
          onSignOut: _signOut,
          onSelected: () {
            _clearSearch();
            if (!wide) _scaffoldKey.currentState?.closeDrawer();
          },
        );

        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            title: wide ? null : const _Brand(),
            actions: [
              PopupMenuButton<SortBy>(
                tooltip: 'Sort',
                icon: const Icon(Icons.swap_vert_rounded),
                initialValue: _store.sortBy,
                onSelected: (s) => _store.sortBy = s,
                itemBuilder: (_) => [
                  for (final s in SortBy.values)
                    CheckedPopupMenuItem(
                      value: s,
                      checked: s == _store.sortBy,
                      child: Text(s.label),
                    ),
                ],
              ),
              IconButton(
                tooltip: _store.showCompleted
                    ? 'Hide completed tasks'
                    : 'Show completed tasks',
                isSelected: _store.showCompleted,
                icon: const Icon(Icons.visibility_off_outlined),
                selectedIcon: const Icon(Icons.visibility_rounded),
                onPressed: () => _store.showCompleted = !_store.showCompleted,
              ),
              IconButton(
                tooltip: 'Board',
                icon: const Icon(Icons.view_kanban_outlined),
                onPressed: _openBoard,
              ),
              if (_social != null) ...[
                IconButton(
                  tooltip: 'People',
                  icon: Badge(
                    isLabelVisible: _peopleBadge > 0,
                    label: Text('$_peopleBadge'),
                    child: const Icon(Icons.people_alt_outlined),
                  ),
                  onPressed: _openPeople,
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _openSettings,
                ),
              ],
              if (widget.assistant != null)
                IconButton(
                  tooltip: 'Assistant',
                  icon: const Icon(Icons.auto_awesome_rounded),
                  onPressed: _openAssistant,
                ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _store.loading ? null : _store.load,
              ),
              if (!wide)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: IconButton(
                    tooltip: 'Profile',
                    padding: EdgeInsets.zero,
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    icon: UserAvatar(
                      name: widget.userEmail ?? '',
                      url: _avatarUrl,
                      radius: 16,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
          drawer: wide ? null : Drawer(child: nav),
          floatingActionButton: _store.loading || _store.loadError != null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New task'),
                ),
          body: wide
              ? Row(
                  children: [
                    SizedBox(
                      width: 300,
                      child: Material(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        child: nav,
                      ),
                    ),
                    Expanded(child: _body()),
                  ],
                )
              : _body(),
        );
      },
    );
  }

  Widget _body() {
    if (_store.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_store.loadError != null) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load your tasks',
        subtitle: _store.loadError!,
        action: FilledButton(
          onPressed: _store.load,
          child: const Text('Try again'),
        ),
      );
    }

    final searching = _store.query.trim().isNotEmpty;
    final tasks = _store.visibleTasks;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            _ViewHeader(store: _store, searching: searching),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search all tasks',
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  suffixIcon: _store.query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: _clearSearch,
                        ),
                ),
                onChanged: (v) => _store.query = v,
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.03),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey((_store.view, searching)),
                  child: tasks.isEmpty
                      ? _Message(
                          icon: searching
                              ? Icons.search_off_rounded
                              : Icons.wb_sunny_rounded,
                          title: searching
                              ? 'No matching tasks'
                              : 'Nothing here. Enjoy the calm.',
                          subtitle: searching
                              ? 'Try a different word.'
                              : 'Tap the + button to add a task.',
                        )
                      : RefreshIndicator(
                          onRefresh: _store.load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            itemCount: tasks.length,
                            itemBuilder: (context, i) {
                              final task = tasks[i];
                              return Padding(
                                key: ValueKey(task.id),
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Dismissible(
                                  key: ValueKey('dismiss-${task.id}'),
                                  background: const _SwipeBackground(
                                    Alignment.centerLeft,
                                  ),
                                  secondaryBackground: const _SwipeBackground(
                                    Alignment.centerRight,
                                  ),
                                  onDismissed: (_) => _delete(task),
                                  child: TaskTile(
                                    task: task,
                                    store: _store,
                                    onTap: () => _openEditor(task),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewHeader extends StatelessWidget {
  const _ViewHeader({required this.store, required this.searching});

  final TodoStore store;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = searching
        ? (Icons.search_rounded, scheme.primary)
        : viewStyle(store, store.view, scheme);
    final progress = store.progressFor(store.view);
    final showProgress =
        !searching &&
        progress.total > 0 &&
        store.view.kind != ViewKind.completed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('EEEE, d MMMM').format(store.today).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  searching ? 'Search' : store.titleOf(store.view),
                  style: theme.textTheme.headlineMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (showProgress) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: progress.done / progress.total),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) =>
                        LinearProgressIndicator(value: value, color: color),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${progress.done} of ${progress.total} done',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.check_rounded, size: 18, color: scheme.onPrimary),
        ),
        const SizedBox(width: 10),
        const Text('Tasks'),
      ],
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground(this.alignment);
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(Icons.delete_rounded, color: scheme.onErrorContainer),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primaryContainer, scheme.tertiaryContainer],
                ),
              ),
              child: Icon(icon, size: 52, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
