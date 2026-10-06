import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data.dart';
import '../../state/ui.dart';
import '../../util/dates.dart';
import '../archive/archive_view.dart';
import '../board/board_view.dart';
import '../calendar/calendar_view.dart';
import '../card_modal/card_modal.dart';
import '../inbox/inbox_view.dart';
import '../manage/manage_view.dart';
import '../settings/settings_view.dart';
import 'sidebar.dart';
import 'window_chrome.dart';

/// The signed-in app: title bar, sidebar, the current view, status bar, and
/// the Card Modal on top.
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Scrapers and the voice app write in the background; pick up their changes.
    _poll = Timer.periodic(const Duration(minutes: 1), (_) {
      ref.invalidate(inboxProvider);
      ref.invalidate(sourcesProvider);
      ref.invalidate(boardsProvider);
      final id = ref.read(currentBoardIdProvider);
      if (id != null && ref.read(openCardProvider) == null) refreshBoardFromWidget(ref, id);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(viewProvider);
    final detail = ref.watch(currentBoardProvider);
    final boards = ref.watch(boardsProvider);

    final title = switch (view) {
      AppView.board => detail?.board.name ?? 'Board',
      AppView.inbox => 'Inbox',
      AppView.calendar => 'Calendar',
      AppView.archive => 'Archive',
      AppView.settings => 'Settings',
      AppView.manage => 'Manage boards',
    };

    final Widget main;
    if (boards.hasError && boards.value == null && view != AppView.settings) {
      main = Center(child: Text("Couldn't load boards: ${boards.error}"));
    } else {
      main = switch (view) {
        AppView.board => const BoardView(),
        AppView.inbox => const InboxView(),
        AppView.calendar => const CalendarView(),
        AppView.archive => const ArchiveView(),
        AppView.settings => const SettingsView(),
        AppView.manage => const ManageView(),
      };
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newCard,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _newCard,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Column(
              children: [
                TitleBar(title: title),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Sidebar(),
                      Expanded(child: main),
                    ],
                  ),
                ),
                StatusBar(left: _statusLeft(view), right: _statusRight()),
              ],
            ),
            const CardModalHost(),
          ],
        ),
      ),
    );
  }

  /// Ctrl+N, from any view: a new card on the current board.
  void _newCard() {
    final detail = ref.read(currentBoardProvider);
    if (detail != null) newCard(context, ref, detail);
  }

  String _statusLeft(AppView view) {
    final detail = ref.watch(currentBoardProvider);
    final now = ref.watch(nowProvider);
    final cards = detail == null ? null : ref.watch(cardsProvider(detail.board.id)).value;
    return switch (view) {
      AppView.board => detail == null || cards == null ? '' : boardStatus(detail, cards, ref.watch(boardFilterProvider), now),
      AppView.inbox => inboxStatus(ref.watch(inboxProvider).value, detail?.board),
      AppView.calendar => calendarStatus(detail, cards, ref.watch(calendarProvider).anchor, now),
      _ => detail == null ? '' : '${detail.board.openCount} open · ${detail.board.overdueCount} overdue',
    };
  }

  String _statusRight() {
    final api = ref.watch(apiProvider);
    final now = ref.watch(nowProvider);
    final synced = [for (final s in ref.watch(sourcesProvider).value ?? const []) ?s.lastSyncAt];
    synced.sort();
    final last = synced.isEmpty ? 'no syncs yet' : 'last sync ${ago(synced.last, now)}';
    return 'api: ${api.host} · $last';
  }
}
