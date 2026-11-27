import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;
  bool _needsConfirmation = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _needsConfirmation = false;
    });
    final auth = Supabase.instance.client.auth;
    final email = _email.text.trim();
    try {
      if (_signUp) {
        final res = await auth.signUp(email: email, password: _password.text);
        if (res.session == null && mounted) {
          setState(() {
            _signUp = false;
            _info =
                'Account created. Check $email for a confirmation link, '
                'then sign in here. Only the newest email\'s link works.';
          });
        }
      } else {
        await auth.signInWithPassword(email: email, password: _password.text);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'email_not_confirmed') {
          _needsConfirmation = true;
          _error = 'Confirm your email first: open the link we sent to $email.';
        } else if (e.code == 'over_email_send_rate_limit') {
          _error = 'Too many emails sent. Wait a few minutes, then try again.';
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendConfirmation() async {
    final email = _email.text.trim();
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      if (mounted) {
        setState(() {
          _needsConfirmation = false;
          _error = null;
          _info =
              'New confirmation email sent to $email. Use the link in '
              'that newest email.';
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'over_email_send_rate_limit'
              ? 'Too many emails sent. Wait a few minutes, then try again.'
              : e.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter your email above first.');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(() {
          _error = null;
          _info = 'If $email has an account, a reset link is on its way.';
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Phones get a flat full-screen form; bigger screens a floating card.
    final phone = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          gradient: phone
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primaryContainer,
                    scheme.surface,
                    scheme.tertiaryContainer,
                  ],
                ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(phone ? 8 : 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: phone ? 0 : 12,
                  shadowColor: scheme.primary.withValues(alpha: 0.25),
                  color: scheme.surface,
                  shape: phone
                      ? const RoundedRectangleBorder()
                      : RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [scheme.primary, scheme.tertiary],
                                ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.primary.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 44,
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _signUp ? 'Create your account' : 'Welcome back',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _signUp
                                ? 'Your tasks, synced everywhere.'
                                : 'Sign in to pick up where you left off.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (v) =>
                                v != null && v.trim().contains('@')
                                ? null
                                : 'Enter a valid email',
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscure
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            // New passwords must be longer; existing shorter
                            // ones can still sign in.
                            validator: (v) {
                              final min = _signUp ? 8 : 6;
                              return v != null && v.length >= min
                                  ? null
                                  : 'At least $min characters';
                            },
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                          if (_needsConfirmation)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _busy ? null : _resendConfirmation,
                                icon: const Icon(
                                  Icons.mark_email_unread_outlined,
                                ),
                                label: const Text('Resend confirmation email'),
                              ),
                            ),
                          if (_info != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _info!,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: _busy
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _signUp ? 'Create account' : 'Sign in',
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _signUp = !_signUp;
                                    _error = null;
                                  }),
                            child: Text(
                              _signUp
                                  ? 'Already have an account? Sign in'
                                  : 'New here? Create an account',
                            ),
                          ),
                          if (!_signUp)
                            TextButton(
                              onPressed: _busy ? null : _resetPassword,
                              child: const Text('Forgot password?'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
