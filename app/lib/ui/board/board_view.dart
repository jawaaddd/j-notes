import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/models.dart';
import '../../state/data.dart';
import '../../state/ui.dart';
import '../../theme/tokens.dart';
import '../../util/dates.dart';
import '../dialogs.dart';
import '../popover.dart';
import '../widgets.dart';
import 'card_tile.dart';

/// The Board view: the current board's lists left to right, with search,
/// special tag chips, and tag filters. Filters dim cards; they never move.
class BoardView extends ConsumerStatefulWidget {
  const BoardView({super.key});

  @override
  ConsumerState<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends ConsumerState<BoardView> {
  final _searchFocus = FocusNode();
  final _search = TextEditingController();

  @override
  void dispose() {
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boardId = ref.watch(currentBoardIdProvider);
    final detail = ref.watch(currentBoardProvider);
    if (boardId == null || detail == null) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    final cards = ref.watch(cardsProvider(boardId));
    final filter = ref.watch(boardFilterProvider);
    // Keep the field in step when the filter resets on a board switch.
    if (filter.search.isEmpty && _search.text.isNotEmpty) _search.clear();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _searchFocus.requestFocus,
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32 - _listPad, 28, 32 - _listPad, 28 - _listPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _listPad),
                child: _Toolbar(detail: detail, cards: cards.value ?? const [], search: _search, searchFocus: _searchFocus),
              ),
              const SizedBox(height: 24 - _listPad),
              Expanded(
                child: cards.when(
                  data: (cards) => _Columns(detail: detail, cards: cards),
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => EmptyState(
                    "Couldn't load cards",
                    detail: '$e',
                    action: AppButton(label: 'Retry', onTap: () => ref.invalidate(cardsProvider(boardId))),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({required this.detail, required this.cards, required this.search, required this.searchFocus});

  final BoardDetail detail;
  final List<CardSummary> cards;
  final TextEditingController search;
  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(boardFilterProvider);
    final b = detail.board;
    String subtitle;
    if (filter.isActive) {
      final matches = cards.where(filter.matches).length;
      final names = [
        if (detail.tag(filter.specialTagId) case final t?) t.name,
        for (final id in filter.tagIds) ?detail.tag(id)?.name,
        if (filter.search.trim().isNotEmpty) '“${filter.search.trim()}”',
      ];
      subtitle = 'Showing $matches of ${cards.length} · filtered by ${names.join(', ')}';
    } else {
      subtitle = '${b.name} · ${b.openCount} open${b.overdueCount > 0 ? ' · ${b.overdueCount} overdue' : ''}';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.itemNoun, style: AppText.pageTitle),
              const SizedBox(height: 4),
              Text(subtitle, style: AppText.subtitle, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        _Filters(detail: detail),
        const SizedBox(width: 12),
        SizedBox(
          width: 280,
          child: AppTextField(
            controller: search,
            focusNode: searchFocus,
            hint: 'Search ${b.itemNoun}…',
            onChanged: ref.read(boardFilterProvider.notifier).search,
            suffix: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('Ctrl K', style: AppText.mono(11)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: 'Ctrl N',
          child: AppButton(label: '+ New Card', kind: ButtonKind.primary, onTap: () => newCard(context, ref, detail)),
        ),
      ],
    );
  }
}

/// "+ New Card": asks for a title, creates the card in the first open list,
/// and opens it in the Card Modal (create mode isn't designed yet).
Future<void> newCard(BuildContext context, WidgetRef ref, BoardDetail detail, {DateTime? dueAt}) async {
  final title = await promptText(context, title: 'New card', hint: 'Title', action: 'Create');
  if (title == null || !context.mounted) return;
  try {
    final card = await ref.read(apiProvider).createCard(detail.board.id, {
      'title': title,
      if (dueAt != null) ...{'dueAt': apiTime(dueAt), 'dueAllDay': true},
    });
    refreshBoardFromWidget(ref, detail.board.id);
    ref.read(openCardProvider.notifier).open(card.summary.id);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _Filters extends ConsumerStatefulWidget {
  const _Filters({required this.detail});

  final BoardDetail detail;

  @override
  ConsumerState<_Filters> createState() => _FiltersState();
}

class _FiltersState extends ConsumerState<_Filters> {
  final _popover = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(boardFilterProvider);
    final notifier = ref.read(boardFilterProvider.notifier);
    // Special tags are filtered from the sidebar rows and Urgent from the
    // Filter popover, so the toolbar only needs Filter and Sort.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Popover(
          controller: _popover,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          popover: (context) => _FilterPopover(detail: widget.detail),
          child: Pill(
            label: 'Filter',
            leading: AppIcon('filter', size: 12, color: filter.tagIds.isNotEmpty ? AppColors.accent : AppColors.mutedText),
            highlight: filter.tagIds.isNotEmpty,
            badge: filter.tagIds.isEmpty ? null : filter.tagIds.length,
            onTap: _popover.toggle,
          ),
        ),
        const SizedBox(width: 8),
        MenuAnchor(
          alignmentOffset: const Offset(0, 6),
          menuChildren: [
            for (final s in CardSort.values)
              MenuItemButton(
                onPressed: () => notifier.sort(s),
                trailingIcon: s == filter.sort ? Text('✓', style: AppText.sans(13, color: AppColors.accent)) : null,
                child: Text(s.label),
              ),
          ],
          builder: (context, menu, _) => Pill(
            label: filter.sort.label,
            leading: const AppIcon('sort', size: 12),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
          ),
        ),
      ],
    );
  }
}

/// TAGS: the board's regular tags with checkboxes, Match any/all, Clear.
class _FilterPopover extends ConsumerWidget {
  const _FilterPopover({required this.detail});

  final BoardDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(boardFilterProvider);
    final notifier = ref.read(boardFilterProvider.notifier);
    return PopoverSurface(
      width: 220,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(14, 8, 14, 6), child: SectionLabel('Tags', size: 10)),
          if (detail.regularTags.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: Text('No tags on this board yet.', style: AppText.subtitle),
            ),
          for (final t in detail.regularTags)
            Hover(
              onTap: () => notifier.toggleTag(t.id),
              builder: (context, hovered) {
                final on = filter.tagIds.contains(t.id);
                return AnimatedContainer(
                  duration: kHoverFade,
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    color: on || hovered ? AppColors.background.withValues(alpha: on ? 1 : 0.5) : null,
                    borderRadius: BorderRadius.circular(AppRadii.row),
                  ),
                  child: Row(
                    children: [
                      CheckBox(checked: on),
                      const SizedBox(width: 10),
                      Dot(AppColors.tag(t.color), size: 7),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(t.name, style: AppText.sans(13, color: on ? AppColors.primaryText : AppColors.bodyText)),
                      ),
                      Text('${t.openCardCount}', style: AppText.mono(11)),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 4),
          const Divider(height: 1, thickness: 1, color: AppColors.cardBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 14, 6),
            child: Row(
              children: [
                Hover(
                  onTap: () => notifier.setMatchAll(!filter.matchAll),
                  builder: (context, _) =>
                      FadeText('${filter.matchAll ? 'Match all' : 'Match any'} ▾', style: AppText.sans(12, color: AppColors.mutedText)),
                ),
                const Spacer(),
                Hover(
                  onTap: notifier.clearTags,
                  builder: (context, _) => FadeText(
                    'Clear',
                    style: AppText.sans(12, weight: FontWeight.w500, color: AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 15px checkbox: Accent fill with a dark check when on, Muted outline when off.
class CheckBox extends StatelessWidget {
  const CheckBox({super.key, required this.checked, this.size = 14});

  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: checked ? AppColors.accent : null,
      borderRadius: BorderRadius.circular(4),
      border: checked ? null : Border.all(color: AppColors.mutedText),
    ),
    child: checked ? Icon(Icons.check_rounded, size: size - 3, color: AppColors.background) : null,
  );
}

/// Inner padding of each list, so the drop highlight has room around the
/// cards. The board compensates with less outer padding, keeping the cards
/// aligned with the toolbar.
const _listPad = 8.0;

/// Height of the card being dragged, so a list can find the dragged card's
/// middle when deciding where it would drop.
double _draggedHeight = 90;

class _Columns extends ConsumerWidget {
  const _Columns({required this.detail, required this.cards});

  final BoardDetail detail;
  final List<CardSummary> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = detail.lists;
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 20.0 - 2 * _listPad; // 20px between cards of neighboring lists
        final fit = (box.maxWidth - gap * (lists.length - 1)) / lists.length >= 256;
        final columns = [
          for (final (i, l) in lists.indexed) ...[
            if (i > 0) const SizedBox(width: gap),
            fit
                ? Expanded(
                    child: _Column(detail: detail, list: l, cards: cards),
                  )
                : SizedBox(
                    width: 316,
                    child: _Column(detail: detail, list: l, cards: cards),
                  ),
          ],
        ];
        final row = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: columns);
        return fit
            ? row
            : Scrollbar(
                child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: row),
              );
      },
    );
  }
}

class _Column extends ConsumerStatefulWidget {
  const _Column({required this.detail, required this.list, required this.cards});

  final BoardDetail detail;
  final BoardList list;
  final List<CardSummary> cards;

  @override
  ConsumerState<_Column> createState() => _ColumnState();
}

class _ColumnState extends ConsumerState<_Column> {
  final _keys = <int, GlobalKey>{};

  /// Where a hovering card would land, as an index among this list's other
  /// cards; null when nothing is hovering.
  int? _dropIndex;
  bool _hovering = false;

  GlobalKey _key(int id) => _keys.putIfAbsent(id, GlobalKey.new);

  /// Finds the drop index by comparing the dragged card's middle with the
  /// middle of each other card in the list.
  int _indexAt(Offset feedbackTopLeft, int draggedId, List<CardSummary> mine) {
    final y = feedbackTopLeft.dy + _draggedHeight / 2;
    var i = 0;
    for (final c in mine) {
      if (c.id == draggedId) continue;
      final box = _keys[c.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final mid = box.localToGlobal(Offset(0, box.size.height / 2)).dy;
      if (y < mid) return i;
      i++;
    }
    return i;
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final list = widget.list;
    final filter = ref.watch(boardFilterProvider);
    final now = ref.watch(nowProvider);
    final custom = filter.sort == CardSort.custom;
    final mine = sortCards(widget.cards.where((c) => c.listId == list.id), filter.sort);

    // Custom sort shows an insertion line where the card will land. Other
    // sorts only move cards between lists; they land in sort order.
    final lineAt = custom && _hovering ? _dropIndex : null;
    final children = <Widget>[];
    var others = 0;
    for (final c in mine) {
      final isDragged = _draggingId == c.id;
      if (!isDragged && lineAt == others) children.add(const _DropLine());
      children.add(
        Padding(
          key: _key(c.id),
          padding: const EdgeInsets.only(bottom: 10),
          child: _DraggableCard(
            card: c,
            list: list,
            detail: detail,
            now: now,
            dimmed: filter.isActive && !filter.matches(c),
            onDragStarted: (h) => _draggedHeight = h,
          ),
        ),
      );
      if (!isDragged) others++;
    }
    if (lineAt != null && lineAt >= others) children.add(const _DropLine());

    return DragTarget<CardSummary>(
      onWillAcceptWithDetails: (d) => custom || d.data.listId != list.id,
      onMove: (d) {
        final i = _indexAt(d.offset, d.data.id, mine);
        if (i != _dropIndex || !_hovering || _draggingId != d.data.id) {
          setState(() {
            _dropIndex = i;
            _hovering = true;
            _draggingId = d.data.id;
          });
        }
      },
      onLeave: (_) => setState(() {
        _hovering = false;
        _dropIndex = null;
        _draggingId = null;
      }),
      onAcceptWithDetails: (d) async {
        final index = custom ? _indexAt(d.offset, d.data.id, mine) : null;
        setState(() {
          _hovering = false;
          _dropIndex = null;
          _draggingId = null;
        });
        try {
          await ref.read(cardsProvider(detail.board.id).notifier).move(d.data, list, index: index);
        } catch (e) {
          if (context.mounted) showError(context, e);
        }
      },
      builder: (context, candidates, _) => AnimatedContainer(
        duration: kHoverFade,
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(_listPad),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty ? const Color(0x0AFFFFFF) : const Color(0x00FFFFFF),
          borderRadius: BorderRadius.circular(AppRadii.card + 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Flexible(
                    child: Text(list.name, style: AppText.listTitle, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Text('${mine.length}', style: AppText.mono(12)), // full total, not the filtered count
                  if (list.isDone) ...[
                    const Spacer(),
                    // Overflows the header row so Done's cards line up with the other lists'.
                    SizedBox(
                      width: 24,
                      height: 16,
                      child: OverflowBox(
                        maxHeight: 24,
                        child: _ArchiveListButton(list: list, count: mine.length, boardId: detail.board.id),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(child: ListView(children: children)),
          ],
        ),
      ),
    );
  }

  int? _draggingId;
}

/// The round button on a Done list's header: archives all its cards.
class _ArchiveListButton extends ConsumerWidget {
  const _ArchiveListButton({required this.list, required this.count, required this.boardId});

  final BoardList list;
  final int count;
  final int boardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = count > 0;
    return Tooltip(
      message: enabled ? 'Archive all $count' : 'Nothing to archive',
      child: Hover(
        onTap: enabled ? () => _archive(context, ref) : null,
        builder: (context, hovered) => AnimatedContainer(
          duration: kHoverFade,
          curve: Curves.easeOut,
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hovered && enabled ? AppColors.cardBackground : null,
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Center(child: AppIcon('archive', size: 12, color: hovered && enabled ? AppColors.bodyText : AppColors.mutedText)),
        ),
      ),
    );
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Archive $count ${count == 1 ? 'card' : 'cards'}?',
      message: 'Everything in ${list.name} moves to the Archive, where it can be unarchived.',
      action: 'Archive',
      danger: false,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(apiProvider).archiveList(list.id);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
    refreshBoardFromWidget(ref, boardId);
  }
}

class _DropLine extends StatelessWidget {
  const _DropLine();

  @override
  Widget build(BuildContext context) => Container(
    height: 2,
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(1)),
  );
}

class _DraggableCard extends ConsumerWidget {
  const _DraggableCard({
    required this.card,
    required this.list,
    required this.detail,
    required this.now,
    required this.dimmed,
    required this.onDragStarted,
  });

  final CardSummary card;
  final BoardList list;
  final BoardDetail detail;
  final DateTime now;
  final bool dimmed;
  final ValueChanged<double> onDragStarted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = CardTile(
      card: card,
      list: list,
      detail: detail,
      now: now,
      dimmed: dimmed,
      onTap: () => ref.read(openCardProvider.notifier).open(card.id),
    );
    return LayoutBuilder(
      builder: (context, box) => Draggable<CardSummary>(
        data: card,
        onDragStarted: () => onDragStarted(context.size?.height ?? 90),
        feedback: Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: box.maxWidth,
            child: Transform.rotate(
              angle: -0.015,
              child: CardTile(card: card, list: list, detail: detail, now: now),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: tile),
        child: tile,
      ),
    );
  }
}

/// Left side of the status bar on the Board view, e.g.
/// "5 open · 1 overdue · 1 due tomorrow".
String boardStatus(BoardDetail detail, List<CardSummary> cards, BoardFilter filter, DateTime now) {
  final open = [
    for (final c in cards)
      if (!(detail.list(c.listId)?.isDone ?? false)) c,
  ];
  final overdue = open.where((c) => c.dueAt != null && c.dueAt!.isBefore(now)).length;
  final parts = ['${open.length} open', '$overdue overdue'];
  final urgent = detail.urgentTag;
  if (urgent != null && filter.tagIds.contains(urgent.id)) {
    parts.add('${open.where((c) => c.tagIds.contains(urgent.id)).length} ${urgent.name.toLowerCase()}');
  } else {
    final tomorrow = open.where((c) => c.dueAt != null && !c.dueAt!.isBefore(now) && daysBetween(now, c.dueAt!) == 1).length;
    if (tomorrow > 0) parts.add('$tomorrow due tomorrow');
  }
  return parts.join(' · ');
}
