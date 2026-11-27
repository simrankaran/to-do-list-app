import 'package:material_ui/material_ui.dart';

import '../../data/profile_repository.dart';
import '../../data/social_models.dart';
import '../../data/social_repository.dart';
import '../../data/todo_repository.dart';
import '../../services/app_settings.dart';
import '../common/image_source.dart';
import '../common/label_actions.dart';
import '../common/user_avatar.dart';

/// Your profile as other people see it (photo, name, bio), plus account
/// actions.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.social,
    required this.onSignOut,
    this.profile,
    this.pickImage = pickProfileImage,
    this.email,
    this.avatarUrl,
    this.onAvatarChanged,
    this.appSettings,
  });

  /// Theme, sound and confetti choices; null hides the Appearance section.
  final AppSettings? appSettings;

  final SocialRepository social;

  /// Photo storage; without it the photo can't be changed.
  final ProfileRepository? profile;
  final Future<PickedImage?> Function() pickImage;
  final String? email;
  final String? avatarUrl;
  final ValueChanged<String?>? onAvatarChanged;
  final VoidCallback onSignOut;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  late String? _avatarUrl = widget.avatarUrl;
  Profile? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _photoBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await widget.social.fetchMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _name.text = profile.displayName;
        _bio.text = profile.bio;
        _avatarUrl ??= profile.avatarUrl;
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

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Enter a name so people know who you are.');
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.social.updateMyProfile(
        displayName: name,
        bio: _bio.text.trim(),
      );
      if (!mounted) return;
      setState(() => _profile = saved);
      _snack('Profile saved');
    } on TodoException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _photo(
    Future<String?> Function(ProfileRepository repo) change,
  ) async {
    final repo = widget.profile;
    if (repo == null || _photoBusy) return;
    setState(() => _photoBusy = true);
    try {
      final url = await change(repo);
      if (!mounted) return;
      setState(() => _avatarUrl = url);
      widget.onAvatarChanged?.call(url);
      _snack(url == null ? 'Photo removed' : 'Photo updated');
    } on _Cancelled {
      // The picker was closed without choosing a photo.
    } on TodoException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not change the photo: $e');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  void _photoMenu() {
    if (widget.profile == null || _photoBusy) return;
    showAvatarSheet(
      context,
      hasPhoto: _avatarUrl != null,
      onChange: () => _photo((repo) async {
        final image = await widget.pickImage();
        if (image == null) throw const _Cancelled();
        return repo.uploadAvatar(image.bytes, image.contentType);
      }),
      onRemove: () => _photo((repo) async {
        await repo.removeAvatar();
        return null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = _name.text.trim().isEmpty
        ? (widget.email ?? 'You')
        : _name.text.trim();

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _profile == null) {
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
    } else {
      body = ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Tooltip(
              message: 'Change profile photo',
              child: GestureDetector(
                onTap: _photoMenu,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    UserAvatar(name: name, url: _avatarUrl, radius: 52),
                    if (_photoBusy)
                      const Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.all(34),
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      ),
                    if (widget.profile != null && !_photoBusy)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.surface, width: 3),
                          ),
                          child: Icon(
                            Icons.photo_camera_rounded,
                            size: 16,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.profile != null)
            Center(
              child: TextButton(
                onPressed: _photoBusy ? null : _photoMenu,
                child: Text(
                  _avatarUrl == null ? 'Upload a photo' : 'Change photo',
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: 50,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Display name',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          TextField(
            controller: _bio,
            maxLength: 200,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'About you',
              hintText: 'A line or two that friends will see',
            ),
          ),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save profile'),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'People you connect with can see your photo, name and '
                    '“About you”. Your tasks, projects and files are always '
                    'private.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (widget.appSettings != null) ...[
            const SizedBox(height: 24),
            _AppearanceSection(settings: widget.appSettings!),
          ],
          const SizedBox(height: 20),
          if (widget.email != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mail_outline_rounded),
              title: const Text('Signed in as'),
              subtitle: Text(widget.email!),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded, color: scheme.error),
            title: Text('Sign out', style: TextStyle(color: scheme.error)),
            onTap: () {
              Navigator.of(context).pop();
              widget.onSignOut();
            },
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: body,
        ),
      ),
    );
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Colour theme, light/dark mode, and the sound and confetti switches.
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appearance', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final t in appThemes)
                _ThemeSwatch(
                  appTheme: t,
                  selected: t.key == settings.theme.key,
                  onTap: () => settings.theme = t,
                ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('Auto'),
                icon: Icon(Icons.brightness_auto_rounded),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode_rounded),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode_rounded),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => settings.themeMode = s.first,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              settings.sounds
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
            ),
            title: const Text('Sounds'),
            subtitle: const Text('A soft pop when you finish a task'),
            value: settings.sounds,
            onChanged: (v) => settings.sounds = v,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(Icons.celebration_rounded, color: scheme.primary),
            title: const Text('Confetti'),
            subtitle: const Text('Celebrate finished tasks and a clear day'),
            value: settings.celebrations,
            onChanged: (v) => settings.celebrations = v,
          ),
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.appTheme,
    required this.selected,
    required this.onTap,
  });

  final AppTheme appTheme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${appTheme.name} theme',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [appTheme.seed, appTheme.accent],
                ),
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : Colors.transparent,
                  width: 3,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: appTheme.seed.withValues(alpha: 0.45),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(appTheme.name, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
