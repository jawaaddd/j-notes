import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'state/session.dart';
import 'theme/tokens.dart';
import 'ui/auth/auth_screen.dart';
import 'ui/shell/shell.dart';
import 'ui/shell/window_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  // The app draws its own title bar (Figma: App Window), so hide the system one.
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'notes-app',
      size: Size(1440, 900),
      minimumSize: Size(1100, 680),
      center: true,
      backgroundColor: AppColors.background,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  runApp(
    ProviderScope(
      // Failed requests surface as errors with a Retry button instead of
      // retrying silently in the background.
      retry: (_, _) => null,
      child: const NotesApp(),
    ),
  );
}

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'notes-app',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: const Scaffold(body: _Root()),
  );
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(sessionProvider.select((s) => s.phase));
    if (phase == SessionPhase.ready) return const Shell();
    return const Column(
      children: [
        TitleBar(title: 'Sign in'),
        Expanded(child: AuthScreen()),
      ],
    );
  }
}
