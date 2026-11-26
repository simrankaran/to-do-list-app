import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme.dart';
import 'data/profile_repository.dart';
import 'data/supabase_todo_repository.dart';
import 'features/auth/auth_page.dart';
import 'features/home/home_page.dart';

class TodoApp extends StatelessWidget {
  const TodoApp({super.key, this.home});

  /// Overrides the signed-in/signed-out switch (used by tests).
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tasks',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: home ?? const AuthGate(),
    );
  }
}

/// Shows the sign-in page or the user's tasks depending on the session.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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
          onSignOut: auth.signOut,
        );
      },
    );
  }
}
