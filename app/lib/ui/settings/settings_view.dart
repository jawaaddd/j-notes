import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/models.dart';
import '../../state/data.dart';
import '../../state/session.dart';
import '../../theme/tokens.dart';
import '../../util/dates.dart';
import '../dialogs.dart';
import '../widgets.dart';

final _tokensProvider = FutureProvider.autoDispose<List<ApiToken>>((ref) => ref.watch(apiProvider).tokens());

/// Settings isn't designed yet. This covers what the app needs today: the
/// server, signing out, the password, and API tokens for scrapers.
class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final tokens = ref.watch(_tokensProvider);
    final now = ref.watch(nowProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      children: [
        Text('Settings', style: AppText.pageTitle),
        const SizedBox(height: 28),
        _Section(
          title: 'Server',
          child: Row(
            children: [
              Expanded(
                child: Text(session.serverUrl ?? '', style: AppText.mono(13, color: AppColors.bodyText)),
              ),
              AppButton(label: 'Change server', onTap: ref.read(sessionProvider.notifier).changeServer),
              const SizedBox(width: 10),
              AppButton(label: 'Sign out', onTap: ref.read(sessionProvider.notifier).signOut),
            ],
          ),
        ),
        _Section(
          title: 'Password',
          child: session.passwordFromEnv
              ? Text('Set by NOTES_PASSWORD on the server. Change it there and restart the server.', style: AppText.subtitle)
              : Row(
                  children: [
                    Expanded(child: Text('Changing it signs out every other device. API tokens keep working.', style: AppText.subtitle)),
                    AppButton(label: 'Change password', onTap: () => _changePassword(context, ref)),
                  ],
                ),
        ),
        _Section(
          title: 'API tokens',
          trailing: AppButton(label: '+ New token', kind: ButtonKind.primary, small: true, onTap: () => _newToken(context, ref)),
          child: tokens.when(
            loading: () => const SizedBox(height: 40),
            error: (e, _) => Text('$e', style: AppText.subtitle),
            data: (list) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Scrapers and the voice app sign in with a token. Sessions are the devices signed in with your password.',
                    style: AppText.subtitle,
                  ),
                ),
                for (final t in list)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(AppRadii.control)),
                    child: Row(
                      children: [
                        MonoChip(t.kind == 'api' ? 'API' : 'SESSION'),
                        const SizedBox(width: 12),
                        Expanded(child: Text(t.current ? '${t.name} (this device)' : t.name, style: AppText.sans(13))),
                        Text(t.lastUsedAt == null ? 'never used' : 'used ${ago(t.lastUsedAt!, now)}', style: AppText.mono(11)),
                        const SizedBox(width: 16),
                        if (!t.current)
                          AppButton(
                            label: t.kind == 'api' ? 'Revoke' : 'Sign out',
                            small: true,
                            kind: ButtonKind.danger,
                            onTap: () async {
                              try {
                                await ref.read(apiProvider).deleteToken(t.id);
                                ref.invalidate(_tokensProvider);
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _newToken(BuildContext context, WidgetRef ref) async {
    final name = await promptText(context, title: 'New API token', hint: 'What uses it, e.g. autolab scraper', action: 'Create');
    if (name == null || !context.mounted) return;
    try {
      final token = await ref.read(apiProvider).createToken(name);
      ref.invalidate(_tokensProvider);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          title: 'Copy your token',
          width: 520,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("This is the only time it's shown. Give it to $name as its bearer token.", style: AppText.body),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.cardBackground, borderRadius: BorderRadius.circular(AppRadii.control)),
                child: SelectableText(token, style: AppText.mono(12, color: AppColors.primaryText)),
              ),
            ],
          ),
          actions: [
            AppButton(
              label: 'Copy',
              onTap: () => Clipboard.setData(ClipboardData(text: token)),
            ),
            AppButton(label: 'Done', kind: ButtonKind.primary, onTap: () => Navigator.pop(context)),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final current = TextEditingController();
    final next = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          Future<void> submit() async {
            try {
              await ref.read(apiProvider).changePassword(current.text, next.text);
              if (context.mounted) Navigator.pop(context);
            } on ApiException catch (e) {
              setState(() => error = e.code == 'INVALID_PASSWORD' ? 'Current password is wrong.' : e.message);
            }
          }

          return AppDialog(
            title: 'Change password',
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(controller: current, hint: 'Current password', obscure: true, autofocus: true),
                const SizedBox(height: 10),
                AppTextField(controller: next, hint: 'New password (8+ characters)', obscure: true, onSubmitted: (_) => submit()),
                if (error != null) ...[const SizedBox(height: 10), Text(error!, style: AppText.sans(12, color: AppColors.danger))],
              ],
            ),
            actions: [
              AppButton(label: 'Cancel', onTap: () => Navigator.pop(context)),
              AppButton(label: 'Change', kind: ButtonKind.primary, onTap: submit),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 32),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppText.listTitle)),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}
