import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme.dart';
import 'data/assistant_service.dart';
import 'data/local_assistant.dart';
import 'data/profile_repository.dart';
import 'data/social_repository.dart';
import 'data/supabase_todo_repository.dart';
import 'features/auth/auth_page.dart';
import 'features/home/home_page.dart';
import 'services/app_settings.dart';
import 'services/home_widget_sync.dart';
import 'services/reminders.dart';
import 'services/sound_effects.dart';

class TodoApp extends StatelessWidget {
  const TodoApp({
    super.key,
    this.home,
    this.reminders = const NoReminders(),
    this.settings,
    this.sounds = const SilentSoundPlayer(),
  });

  /// Overrides the signed-in/signed-out switch (used by tests).
  final Widget? home;

  /// Phone notifications for task start and end times.
  final ReminderScheduler reminders;

  /// Theme, sound and confetti choices; null uses the default look.
  final AppSettings? settings;
  final SoundPlayer sounds;

  MaterialApp _app(AppSettings? s) {
    final seed = s?.theme.seed ?? brandSeed;
    return MaterialApp(
      title: 'Tasks',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, seed: seed),
      darkTheme: buildTheme(Brightness.dark, seed: seed),
      themeMode: s?.themeMode ?? ThemeMode.system,
      // Colours glide into each other when the theme changes.
      themeAnimationDuration: const Duration(milliseconds: 400),
      home:
          home ??
          AuthGate(reminders: reminders, settings: settings, sounds: sounds),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = settings;
    if (s == null) return _app(null);
    return ListenableBuilder(listenable: s, builder: (_, _) => _app(s));
  }
}

/// Shows the sign-in page or the user's tasks depending on the session.
class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.reminders,
    this.settings,
    this.sounds = const SilentSoundPlayer(),
  });

  final ReminderScheduler reminders;
  final AppSettings? settings;
  final SoundPlayer sounds;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final session = auth.currentSession;
        if (session == null) return const AuthPage();
        final user = auth.currentUser ?? session.user;
        return HomePage(
          // A new user id gets a fresh page and store.
          key: ValueKey(user.id),
          repository: SupabaseTodoRepository(Supabase.instance.client),
          profile: SupabaseProfileRepository(Supabase.instance.client),
          userEmail: user.email,
          avatarUrl: user.userMetadata?['avatar_url'] as String?,
          reminders: reminders,
          // Claude when an AI key is set up; built-in rules otherwise.
          assistant: SmartAssistantService(
            SupabaseAssistantService(Supabase.instance.client),
          ),
          homeWidget: updateHomeWidget,
          social: SupabaseSocialRepository(Supabase.instance.client),
          settings: settings,
          sounds: sounds,
          onSignOut: auth.signOut,
        );
      },
    );
  }
}
