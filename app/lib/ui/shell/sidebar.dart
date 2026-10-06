import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/data.dart';
import '../../state/ui.dart';
import '../../theme/tokens.dart';
import '../../util/dates.dart';
import '../dialogs.dart';
import '../popover.dart';
import '../widgets.dart';

/// The shared Sidebar component (Figma: Sidebar, variant Active).
class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(viewProvider);
    final detail = ref.watch(currentBoardProvider);
    final inboxCount = ref.watch(inboxProvider).value?.counts.all;

    return Container(
      width: 248,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              'notes',
              style: AppText.sans(16, weight: FontWeight.w600, color: AppColors.headingText),
            ),
          ),
          const SizedBox(height: 24),
          const _GroupLabel('Board'),
          const _BoardSwitcher(),
          const SizedBox(height: 24),
          _NavRow(
            icon: 'inbox',
            label: 'Inbox',
            count: inboxCount == null ? null : '$inboxCount',
            active: view == AppView.inbox,
            onTap: () => ref.read(viewProvider.notifier).show(AppView.inbox),
          ),
          const SizedBox(height: 2),
          _NavRow(
            icon: 'calendar',
            label: 'Calendar',
            active: view == AppView.calendar,
            onTap: () => ref.read(viewProvider.notifier).show(AppView.calendar),
          ),
          const SizedBox(height: 2),
          _NavRow(
            icon: 'archive',
            label: 'Archive',
            active: view == AppView.archive,
            onTap: () => ref.read(viewProvider.notifier).show(AppView.archive),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (detail != null && detail.specialTags.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _GroupLabel(detail.board.specialTagLabel),
                    for (final t in detail.specialTags) _SpecialTagRow(t),
                  ],
                  const SizedBox(height: 24),
                  const _Sources(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _NavRow(
            icon: 'settings',
            label: 'Settings',
            active: view == AppView.settings,
            onTap: () => ref.read(viewProvider.notifier).show(AppView.settings),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 6), child: SectionLabel(text));
}

/// A 31px sidebar row: 14px slot on the left, label, optional count.
class _Row extends StatelessWidget {
  const _Row({required this.leading, required this.label, this.count, this.active = false, this.onTap});

  final Widget Function(bool hovered) leading;
  final Widget label;
  final String? count;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Hover(
    onTap: onTap,
    builder: (context, hovered) => AnimatedContainer(
      duration: kHoverFade,
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active ? AppColors.cardBackground : (hovered ? const Color(0x0DFFFFFF) : null),
        borderRadius: BorderRadius.circular(AppRadii.row),
      ),
      child: Row(
        children: [
          SizedBox(width: 14, height: 14, child: Center(child: leading(hovered))),
          const SizedBox(width: 10),
          Expanded(child: label),
          if (count != null) Text(count!, style: AppText.mono(12)),
        ],
      ),
    ),
  );
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, this.count, required this.active, required this.onTap});

  final String icon;
  final String label;
  final String? count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Row(
    active: active,
    onTap: onTap,
    count: count,
    leading: (_) => AppIcon(icon, color: active ? AppColors.primaryText : AppColors.mutedText),
    label: Text(
      label,
      style: AppText.sans(
        13,
        weight: active ? FontWeight.w500 : FontWeight.w400,
        color: active ? AppColors.primaryText : AppColors.bodyText,
      ),
    ),
  );
}

class _BoardSwitcher extends ConsumerStatefulWidget {
  const _BoardSwitcher();

  @override
  ConsumerState<_BoardSwitcher> createState() => _BoardSwitcherState();
}

class _BoardSwitcherState extends ConsumerState<_BoardSwitcher> {
  final _menu = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    final boards = ref.watch(boardsProvider).value ?? const [];
    final currentId = ref.watch(currentBoardIdProvider);
    final current = boards.where((b) => b.id == currentId).firstOrNull;
    final onBoardView = ref.watch(viewProvider) == AppView.board;

    return Popover(
      controller: _menu,
      offset: const Offset(0, 4),
      popover: (context) => _BoardMenu(
        boards: boards,
        currentId: currentId,
        onPick: (id) {
          _menu.hide();
          ref.read(selectedBoardIdProvider.notifier).select(id);
          ref.read(viewProvider.notifier).show(AppView.board);
        },
        onNewBoard: () async {
          _menu.hide();
          final name = await promptText(context, title: 'New board', hint: 'Board name, e.g. Spring 2027', action: 'Create');
          if (name == null || !context.mounted) return;
          try {
            final b = await ref.read(apiProvider).createBoard(name);
            ref.invalidate(boardsProvider);
            ref.read(selectedBoardIdProvider.notifier).select(b.id);
            ref.read(viewProvider.notifier).show(AppView.board);
          } catch (e) {
            if (context.mounted) showError(context, e);
          }
        },
        onManage: () {
          _menu.hide();
          ref.read(viewProvider.notifier).show(AppView.manage);
        },
      ),
      child: _Row(
        active: onBoardView,
        onTap: () {
          // From another view, the switcher first returns to the Board view.
          if (!onBoardView) {
            ref.read(viewProvider.notifier).show(AppView.board);
          } else {
            _menu.toggle();
          }
        },
        count: current == null ? null : '${current.openCount}',
        leading: (_) => AppIcon('board', color: onBoardView ? AppColors.primaryText : AppColors.mutedText),
        label: Row(
          children: [
            Flexible(
              child: Text(
                current?.name ?? 'Loading…',
                overflow: TextOverflow.ellipsis,
                style: AppText.sans(
                  13,
                  weight: onBoardView ? FontWeight.w500 : FontWeight.w400,
                  color: onBoardView ? AppColors.primaryText : AppColors.bodyText,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text('▾', style: AppText.sans(10, color: AppColors.mutedText)),
          ],
        ),
      ),
    );
  }
}

class _BoardMenu extends StatelessWidget {
  const _BoardMenu({required this.boards, required this.currentId, required this.onPick, required this.onNewBoard, required this.onManage});

  final List<Board> boards;
  final int? currentId;
  final ValueChanged<int> onPick;
  final VoidCallback onNewBoard;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return PopoverSurface(
      width: 219,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(10, 6, 10, 6), child: SectionLabel('Boards', size: 10)),
          for (final b in boards)
            Hover(
              onTap: () => onPick(b.id),
              builder: (context, hovered) {
                final selected = b.id == currentId;
                return AnimatedContainer(
                  duration: kHoverFade,
                  curve: Curves.easeOut,
                  color: selected ? AppColors.background : (hovered ? const Color(0x0DFFFFFF) : null),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.name,
                              style: AppText.sans(
                                13,
                                weight: selected ? FontWeight.w500 : FontWeight.w400,
                                color: selected ? AppColors.primaryText : AppColors.bodyText,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              b.overdueCount > 0 ? '${b.openCount} open · ${b.overdueCount} overdue' : '${b.openCount} open',
                              style: AppText.mono(11),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Text(
                          '✓',
                          style: AppText.sans(13, weight: FontWeight.w500, color: AppColors.accent),
                        ),
                    ],
                  ),
                );
              },
            ),
          const Divider(height: 1, thickness: 1, color: AppColors.cardBorder),
          _MenuAction('+ New board', AppColors.accent, onNewBoard),
          _MenuAction('Manage boards', AppColors.mutedText, onManage),
        ],
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction(this.label, this.color, this.onTap);

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Hover(
    onTap: onTap,
    builder: (context, hovered) => AnimatedContainer(
      duration: kHoverFade,
      curve: Curves.easeOut,
      color: hovered ? const Color(0x0DFFFFFF) : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text(label, style: AppText.sans(13, color: color)),
    ),
  );
}

/// Hover: faint highlight and the dot takes the tag's color. Click: filters
/// the board, in sync with the toolbar chips.
class _SpecialTagRow extends ConsumerWidget {
  const _SpecialTagRow(this.tag);

  final Tag tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(boardFilterProvider.select((f) => f.specialTagId == tag.id));
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: _Row(
        active: selected,
        onTap: () {
          ref.read(viewProvider.notifier).show(AppView.board);
          ref.read(boardFilterProvider.notifier).special(tag.id);
        },
        count: '${tag.openCardCount}',
        leading: (hovered) => Dot(hovered || selected ? AppColors.tag(tag.color) : AppColors.mutedText),
        label: Text(tag.name, overflow: TextOverflow.ellipsis, style: AppText.sans(13)),
      ),
    );
  }
}

class _Sources extends ConsumerWidget {
  const _Sources();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider).value ?? const [];
    final voiceCount = ref.watch(inboxProvider).value?.counts.voice ?? 0;
    final now = ref.watch(nowProvider);
    final shown = [
      for (final s in sources)
        if (s.kind != 'manual') s,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupLabel('Sources'),
        for (final s in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  SizedBox(width: 14, child: Center(child: Dot(s.healthy ? AppColors.indicator : AppColors.danger))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: AppText.sans(13)),
                        const SizedBox(height: 2),
                        Text(
                          sourceStatus(s, now, voiceCount),
                          overflow: TextOverflow.ellipsis,
                          style: AppText.mono(11, color: s.healthy ? AppColors.mutedText : AppColors.danger),
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
}

/// The subline under a source: "synced 12m ago", "needs re-login",
/// "1 new entry", "imported Sep 2".
String sourceStatus(Source s, DateTime now, int voiceCount) {
  if (!s.healthy) {
    return switch (s.health) {
      'not_set_up' => 'not set up',
      'needs_reauth' => s.statusMessage ?? 'needs re-login',
      _ => s.statusMessage ?? 'error',
    };
  }
  if (s.kind == 'voice' && voiceCount > 0) return '$voiceCount new ${voiceCount == 1 ? 'entry' : 'entries'}';
  final last = s.lastSyncAt;
  if (s.kind == 'import') return last == null ? 'not imported yet' : 'imported ${monthDay(last)}';
  return last == null ? 'not synced yet' : 'synced ${ago(last, now)}';
}
