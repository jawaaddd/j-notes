import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/session.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// Connect, first-run setup, and sign-in (not designed yet; built from the
/// same tokens as the rest of the app).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  late final _server = TextEditingController(text: ref.read(sessionProvider).serverUrl ?? defaultServerUrl);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _localError;
  bool _busy = false;

  @override
  void dispose() {
    _server.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _localError = null;
    });
    await action();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final notifier = ref.read(sessionProvider.notifier);
    final error = _localError ?? session.error;

    final (String title, String subtitle, List<Widget> fields, String action, VoidCallback submit) = switch (session.phase) {
      SessionPhase.setup => (
        'Set up this server',
        'Enter the one-time setup code from the server log, then choose a password.',
        [
          AppTextField(controller: _code, hint: 'Setup code, e.g. ABCD-EFGH', autofocus: true, mono: true),
          const SizedBox(height: 10),
          AppTextField(controller: _password, hint: 'New password (8+ characters)', obscure: true),
          const SizedBox(height: 10),
          AppTextField(controller: _confirm, hint: 'Confirm password', obscure: true, onSubmitted: (_) => _setup(notifier)),
        ],
        'Set password',
        () => _setup(notifier),
      ),
      SessionPhase.signIn => (
        'Sign in',
        session.serverUrl ?? '',
        [
          AppTextField(
            controller: _password,
            hint: 'Password',
            obscure: true,
            autofocus: true,
            onSubmitted: (_) => _run(() => notifier.signIn(_password.text)),
          ),
        ],
        'Sign in',
        () => _run(() => notifier.signIn(_password.text)),
      ),
      _ => (
        'Connect to a server',
        'The address of your notes-app server.',
        [
          AppTextField(
            controller: _server,
            hint: defaultServerUrl,
            autofocus: true,
            mono: true,
            onSubmitted: (_) => _run(() => notifier.connect(_server.text)),
          ),
        ],
        'Connect',
        () => _run(() => notifier.connect(_server.text)),
      ),
    };

    return Center(
      child: SizedBox(
        width: 380,
        child: session.phase == SessionPhase.loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'notes',
                    style: AppText.sans(16, weight: FontWeight.w600, color: AppColors.headingText),
                  ),
                  const SizedBox(height: 28),
                  Text(title, style: AppText.pageTitle),
                  const SizedBox(height: 6),
                  Text(subtitle, style: AppText.subtitle),
                  const SizedBox(height: 20),
                  ...fields,
                  if (error != null) ...[const SizedBox(height: 12), Text(error, style: AppText.sans(12, color: AppColors.danger))],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (session.phase != SessionPhase.connect)
                        Hover(
                          onTap: notifier.changeServer,
                          builder: (context, h) =>
                              FadeText('Change server', style: AppText.sans(12, color: h ? AppColors.bodyText : AppColors.mutedText)),
                        ),
                      const Spacer(),
                      AppButton(label: _busy ? 'Working…' : action, kind: ButtonKind.primary, onTap: _busy ? null : submit),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  void _setup(SessionNotifier notifier) {
    if (_password.text.length < 8) {
      setState(() => _localError = 'Passwords need at least 8 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _localError = "The passwords don't match.");
      return;
    }
    _run(() => notifier.setup(_code.text, _password.text));
  }
}
