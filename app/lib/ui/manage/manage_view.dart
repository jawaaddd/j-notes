import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/models.dart';
import '../../state/data.dart';
import '../../theme/tokens.dart';
import '../dialogs.dart';
import '../popover.dart';
import '../widgets.dart';

/// Manage boards (ui-frontend-spec, Managing boards and lists). Not designed
/// yet: boards on the left, the picked board's details, lists, and tags on the
/// right. Every edit saves straight away.
class ManageView extends ConsumerStatefulWidget {
  const ManageView({super.key});

  @override
  ConsumerState<ManageView> createState() => _ManageViewState();
}

class _ManageViewState extends ConsumerState<ManageView> {
  int? _picked;

  /// Board ids in their new order while a reorder is saving.
  List<int>? _pendingOrder;

  @override
  Widget build(BuildContext context) {
    var boards = ref.watch(boardsProvider).value ?? const <Board>[];
    if (_pendingOrder case final order?) {
      boards = [...boards]..sort((a, b) => order.indexOf(a.id).compareTo(order.indexOf(b.id)));
    }
    final current = ref.watch(currentBoardIdProvider);
    final pickedId = boards.any((b) => b.id == _picked) ? _picked : current;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 260,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(32, 28, 12, 28),
            children: [
              Text('Manage boards', style: AppText.pageTitle),
              const SizedBox(height: 4),
              Text('Drag to reorder.', style: AppText.subtitle),
              const SizedBox(height: 24),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                proxyDecorator: _proxy,
                onReorderItem: (from, to) => _reorderBoards(boards, from, to),
                children: [
                  for (final (i, b) in boards.indexed)
                    ReorderableDragStartListener(
                      key: ValueKey(b.id),
                      index: i,
                      child: _BoardRow(board: b, selected: b.id == pickedId, onTap: () => setState(() => _picked = b.id)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              _TextAction('+ New board', color: AppColors.accent, onTap: _newBoard),
            ],
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: AppColors.cardBorder),
        Expanded(
          child: pickedId == null
              ? const SizedBox.shrink()
              : _BoardEditor(key: ValueKey(pickedId), boardId: pickedId, boards: boards, onDeleted: () => setState(() => _picked = null)),
        ),
      ],
    );
  }

  Future<void> _reorderBoards(List<Board> boards, int from, int to) async {
    if (to == from) return;
    final moved = boards[from];
    final order = [for (final b in boards) b.id]
      ..removeAt(from)
      ..insert(to, moved.id);
    setState(() => _pendingOrder = order);
    try {
      await ref.read(apiProvider).updateBoard(moved.id, {'position': to});
      ref.invalidate(boardsProvider);
      await ref.read(boardsProvider.future);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _pendingOrder = null);
    }
  }

  Future<void> _newBoard() async {
    final name = await promptText(context, title: 'New board', hint: 'Board name, e.g. Spring 2027', action: 'Create');
    if (name == null || !mounted) return;
    try {
      final b = await ref.read(apiProvider).createBoard(name);
      ref.invalidate(boardsProvider);
      setState(() => _picked = b.id);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }
}

/// A dragged row keeps its look; no Material elevation.
Widget _proxy(Widget child, int index, Animation<double> animation) => Material(
  type: MaterialType.transparency,
  child: DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(AppRadii.row),
      boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6))],
    ),
    child: child,
  ),
);

class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.board, required this.selected, required this.onTap});

  final Board board;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Hover(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: kHoverFade,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardBackground : (hovered ? const Color(0x0DFFFFFF) : null),
          borderRadius: BorderRadius.circular(AppRadii.row),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              board.name,
              overflow: TextOverflow.ellipsis,
              style: AppText.sans(
                13,
                weight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected ? AppColors.primaryText : AppColors.bodyText,
              ),
            ),
            const SizedBox(height: 2),
            Text('${board.openCount} open', style: AppText.mono(11)),
          ],
        ),
      ),
    ),
  );
}

class _BoardEditor extends ConsumerStatefulWidget {
  const _BoardEditor({super.key, required this.boardId, required this.boards, required this.onDeleted});

  final int boardId;
  final List<Board> boards;
  final VoidCallback onDeleted;

  @override
  ConsumerState<_BoardEditor> createState() => _BoardEditorState();
}

class _BoardEditorState extends ConsumerState<_BoardEditor> {
  List<int>? _pendingListOrder;

  ApiClient get _api => ref.read(apiProvider);

  void _refresh() => refreshBoardFromWidget(ref, widget.boardId);

  /// Runs a change, reports a failure, and reloads the board either way.
  Future<void> _run(Future<void> Function() change) async {
    try {
      await change();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(boardDetailProvider(widget.boardId)).value;
    if (detail == null) return const SizedBox.shrink();
    final b = detail.board;
    var lists = detail.lists;
    if (_pendingListOrder case final order?) {
      lists = [...lists]..sort((x, y) => order.indexOf(x.id).compareTo(order.indexOf(y.id)));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InlineField(
                  value: b.name,
                  style: AppText.sans(20, weight: FontWeight.w600, color: AppColors.headingText),
                  height: 40,
                  onSave: (v) => _run(() => _api.updateBoard(b.id, {'name': v})),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _Labeled(
                        label: 'Page title',
                        help: 'What the cards are called: "${b.itemNoun}"',
                        child: _InlineField(value: b.itemNoun, onSave: (v) => _run(() => _api.updateBoard(b.id, {'itemNoun': v}))),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _Labeled(
                        label: 'Special tags label',
                        help: 'The sidebar section: "${b.specialTagLabel}"',
                        child: _InlineField(
                          value: b.specialTagLabel,
                          onSave: (v) => _run(() => _api.updateBoard(b.id, {'specialTagLabel': v})),
                        ),
                      ),
                    ),
                  ],
                ),
                _Section(
                  title: 'Lists',
                  help: 'Columns, left to right. Done lists mark their cards complete. A board keeps at least one of each.',
                  action: _TextAction('+ Add list', color: AppColors.accent, onTap: () => _addList(b.id)),
                  child: ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    proxyDecorator: _proxy,
                    onReorderItem: (from, to) => _reorderLists(lists, from, to),
                    children: [
                      for (final (i, l) in lists.indexed)
                        _ListRow(
                          key: ValueKey(l.id),
                          index: i,
                          list: l,
                          onRename: (v) => _run(() => _api.updateList(l.id, {'name': v})),
                          onKind: (k) => _run(() => _api.updateList(l.id, {'kind': k.name})),
                          onDelete: () => _deleteList(detail, l),
                        ),
                    ],
                  ),
                ),
                _Section(
                  title: b.specialTagLabel,
                  help: 'Special tags: listed in the sidebar for filtering. A card has at most one.',
                  action: _TextAction('+ Add', color: AppColors.accent, onTap: () => _addTag(detail, special: true)),
                  child: _tagRows(detail, detail.specialTags, 'No special tags yet.'),
                ),
                _Section(
                  title: 'Tags',
                  help: 'Regular tags: any number per card, shown as colored dots.',
                  action: _TextAction('+ Add', color: AppColors.accent, onTap: () => _addTag(detail, special: false)),
                  child: _tagRows(detail, detail.regularTags, 'No tags yet.'),
                ),
                _Section(
                  title: 'Delete board',
                  help: widget.boards.length == 1 ? "This is the only board, so it can't be deleted. Create another board first." : 'Deletes the board with its lists and tags. If it has cards, you choose to move them to another board or delete them.',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      label: 'Delete ${b.name}',
                      kind: ButtonKind.danger,
                      onTap: widget.boards.length == 1 ? null : () => _deleteBoard(b),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tagRows(BoardDetail detail, List<Tag> tags, String empty) {
    if (tags.isEmpty) return Text(empty, style: AppText.subtitle);
    return Column(
      children: [
        for (final t in tags)
          _TagRow(
            key: ValueKey(t.id),
            tag: t,
            otherGroup: t.isSpecial ? 'Tags' : detail.board.specialTagLabel,
            onRename: (v) => _run(() => _api.updateTag(t.id, {'name': v})),
            onColor: (c) => _run(() => _api.updateTag(t.id, {'color': c})),
            onToggleSpecial: t.isUrgent ? null : () => _run(() => _api.updateTag(t.id, {'isSpecial': !t.isSpecial})),
            onDelete: t.isUrgent ? null : () => _deleteTag(t),
          ),
      ],
    );
  }

  Future<void> _reorderLists(List<BoardList> lists, int from, int to) async {
    if (to == from) return;
    final order = [for (final l in lists) l.id];
    order.insert(to, order.removeAt(from));
    setState(() => _pendingListOrder = order);
    await _run(() async {
      await _api.reorderLists(widget.boardId, order);
      ref.invalidate(boardDetailProvider(widget.boardId));
      await ref.read(boardDetailProvider(widget.boardId).future);
    });
    if (mounted) setState(() => _pendingListOrder = null);
  }

  Future<void> _addList(int boardId) async {
    final name = await promptText(context, title: 'New list', hint: 'List name, e.g. Waiting', action: 'Add');
    if (name != null) await _run(() => _api.createList(boardId, name));
  }

  Future<void> _addTag(BoardDetail detail, {required bool special}) async {
    final name = await promptText(
      context,
      title: special ? 'New ${detail.board.specialTagLabel.toLowerCase()} tag' : 'New tag',
      hint: special ? 'e.g. DiffEq' : 'e.g. Exam prep',
      action: 'Add',
    );
    if (name == null) return;
    // The first palette color this group isn't using yet; recolor from the dot.
    final used = {for (final t in special ? detail.specialTags : detail.regularTags) t.color};
    final color = AppColors.palette.keys.firstWhere((c) => !used.contains(c), orElse: () => 'blue');
    await _run(() => _api.createTag(detail.board.id, name, color, isSpecial: special));
  }

  Future<void> _deleteTag(Tag t) async {
    final ok = await confirm(
      context,
      title: 'Delete ${t.name}?',
      message: t.openCardCount == 0 ? 'No open cards use it.' : "It's removed from the ${t.openCardCount} open cards that use it.",
    );
    if (ok) await _run(() => _api.deleteTag(t.id));
  }

  Future<void> _deleteList(BoardDetail detail, BoardList l) async {
    try {
      await _api.deleteList(l.id);
      _refresh();
      return;
    } on ApiException catch (e) {
      if (e.code != 'LIST_HAS_CARDS') {
        if (mounted) showError(context, e);
        return;
      }
      if (!mounted) return;
      final count = (e.details['cardCount'] as num?)?.toInt() ?? l.cardCount;
      final others = [
        for (final o in detail.lists)
          if (o.id != l.id) o,
      ];
      final to = await showDialog<BoardList>(
        context: context,
        builder: (context) => _MoveListCardsDialog(list: l, count: count, others: others),
      );
      if (to != null) await _run(() => _api.deleteList(l.id, moveToListId: to.id));
    }
  }

  Future<void> _deleteBoard(Board b) async {
    try {
      await _api.deleteBoard(b.id);
    } on ApiException catch (e) {
      if (e.code != 'BOARD_HAS_CARDS') {
        if (mounted) showError(context, e);
        return;
      }
      if (!mounted) return;
      final count = (e.details['cardCount'] as num?)?.toInt() ?? 0;
      final choice = await showDialog<_BoardDeleteChoice>(
        context: context,
        builder: (context) => _DeleteBoardDialog(
          board: b,
          count: count,
          others: [
            for (final o in widget.boards)
              if (o.id != b.id) o,
          ],
        ),
      );
      if (choice == null) return;
      try {
        await _api.deleteBoard(b.id, cards: choice.move ? 'move' : 'delete', toBoardId: choice.toBoardId, applyTagIds: choice.tagIds);
      } catch (e) {
        if (mounted) showError(context, e);
        return;
      }
    }
    if (!mounted) return;
    refreshAll(ref);
    widget.onDeleted();
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.help, this.action});

  final String title;
  final String? help;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: AppText.listTitle)),
            ?action,
          ],
        ),
        if (help != null) ...[const SizedBox(height: 4), Text(help!, style: AppText.subtitle)],
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.help, required this.child});

  final String label;
  final String help;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(padding: const EdgeInsets.only(left: 10, bottom: 4), child: SectionLabel(label, size: 10)),
      child,
      Padding(
        padding: const EdgeInsets.only(left: 10, top: 4),
        child: Text(help, overflow: TextOverflow.ellipsis, style: AppText.mono(11)),
      ),
    ],
  );
}

class _TextAction extends StatelessWidget {
  const _TextAction(this.label, {required this.onTap, this.color = AppColors.mutedText});

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Hover(
    onTap: onTap,
    builder: (context, hovered) => AnimatedContainer(
      duration: kHoverFade,
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: hovered && onTap != null ? const Color(0x0DFFFFFF) : null,
        borderRadius: BorderRadius.circular(AppRadii.row),
      ),
      child: Text(label, style: AppText.sans(12, color: onTap == null ? AppColors.cardBackground : color)),
    ),
  );
}

/// Text that edits in place: borderless until hovered or focused. Enter or
/// leaving the field saves; Esc puts the old value back.
class _InlineField extends StatefulWidget {
  const _InlineField({required this.value, required this.onSave, this.style, this.height = 34});

  final String value;
  final Future<void> Function(String) onSave;
  final TextStyle? style;
  final double height;

  @override
  State<_InlineField> createState() => _InlineFieldState();
}

class _InlineFieldState extends State<_InlineField> {
  late final _controller = TextEditingController(text: widget.value);
  late final _focus = FocusNode(
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        _controller.text = widget.value;
        node.unfocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_InlineField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = _controller.text.trim();
    if (v.isEmpty || v == widget.value) {
      _controller.text = widget.value;
      return;
    }
    widget.onSave(v);
  }

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.row),
      borderSide: BorderSide(color: c),
    );
    return SizedBox(
      height: widget.height,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        style: widget.style ?? AppText.sans(13),
        onSubmitted: (_) => _focus.unfocus(),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.transparent,
          hoverColor: const Color(0x0DFFFFFF),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          enabledBorder: border(Colors.transparent),
          focusedBorder: border(AppColors.accent),
        ),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    super.key,
    required this.index,
    required this.list,
    required this.onRename,
    required this.onKind,
    required this.onDelete,
  });

  final int index;
  final BoardList list;
  final Future<void> Function(String) onRename;
  final ValueChanged<ListKind> onKind;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
    decoration: BoxDecoration(color: const Color(0x08FFFFFF), borderRadius: BorderRadius.circular(AppRadii.row)),
    child: Row(
      children: [
        ReorderableDragStartListener(
          index: index,
          child: const MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Icon(Icons.drag_indicator, size: 16, color: AppColors.mutedText),
            ),
          ),
        ),
        Expanded(
          child: _InlineField(value: list.name, onSave: onRename),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 70,
          child: Text('${list.cardCount} ${list.cardCount == 1 ? 'card' : 'cards'}', textAlign: TextAlign.right, style: AppText.mono(11)),
        ),
        const SizedBox(width: 16),
        Pill(label: 'Open', selected: list.kind == ListKind.open, onTap: () => list.isDone ? onKind(ListKind.open) : null),
        const SizedBox(width: 4),
        Pill(label: 'Done', selected: list.isDone, onTap: () => list.isDone ? null : onKind(ListKind.done)),
        const SizedBox(width: 8),
        _TextAction('Delete', onTap: onDelete),
      ],
    ),
  );
}

class _TagRow extends StatefulWidget {
  const _TagRow({
    super.key,
    required this.tag,
    required this.otherGroup,
    required this.onRename,
    required this.onColor,
    required this.onToggleSpecial,
    required this.onDelete,
  });

  final Tag tag;

  /// The section the tag would move to: "Tags" or the special tags label.
  final String otherGroup;
  final Future<void> Function(String) onRename;
  final ValueChanged<String> onColor;
  final VoidCallback? onToggleSpecial;
  final VoidCallback? onDelete;

  @override
  State<_TagRow> createState() => _TagRowState();
}

class _TagRowState extends State<_TagRow> {
  final _palette = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    final t = widget.tag;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
      decoration: BoxDecoration(color: const Color(0x08FFFFFF), borderRadius: BorderRadius.circular(AppRadii.row)),
      child: Row(
        children: [
          Popover(
            controller: _palette,
            popover: (context) => PopoverSurface(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final MapEntry(key: name, value: color) in AppColors.palette.entries)
                      Tooltip(
                        message: name,
                        child: Hover(
                          onTap: () {
                            _palette.hide();
                            if (name != t.color) widget.onColor(name);
                          },
                          builder: (context, hovered) => Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              border: Border.all(color: name == t.color || hovered ? color : Colors.transparent),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Dot(color, size: 10),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            child: Tooltip(
              message: t.isUrgent ? 'Urgent is always yellow; no other tag can use it' : 'Change color',
              child: Hover(
                onTap: t.isUrgent ? null : _palette.toggle,
                builder: (context, hovered) => AnimatedContainer(
                  duration: kHoverFade,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: hovered && !t.isUrgent ? const Color(0x0DFFFFFF) : null,
                    borderRadius: BorderRadius.circular(AppRadii.row),
                  ),
                  child: Dot(AppColors.tag(t.color), size: 10),
                ),
              ),
            ),
          ),
          Expanded(
            child: _InlineField(value: t.name, onSave: widget.onRename),
          ),
          if (t.isUrgent) ...[
            const SizedBox(width: 8),
            const Tooltip(
              message: 'Built in: the status bar counts urgent cards. It can be renamed, and its yellow is reserved.',
              child: MonoChip('SYSTEM'),
            ),
          ],
          const SizedBox(width: 12),
          SizedBox(
            width: 70,
            child: Text('${t.openCardCount} open', textAlign: TextAlign.right, style: AppText.mono(11)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: Align(
              alignment: Alignment.centerRight,
              child: widget.onToggleSpecial == null ? null : _TextAction('Move to ${widget.otherGroup}', onTap: widget.onToggleSpecial),
            ),
          ),
          SizedBox(width: 64, child: widget.onDelete == null ? null : _TextAction('Delete', onTap: widget.onDelete)),
        ],
      ),
    );
  }
}

/// A radio-style option row for the delete dialogs.
class _Choice extends StatelessWidget {
  const _Choice({required this.selected, required this.label, required this.onTap, this.child});

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Hover(
    onTap: onTap,
    builder: (context, hovered) => AnimatedContainer(
      duration: kHoverFade,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hovered && !selected ? const Color(0x0DFFFFFF) : null,
        borderRadius: BorderRadius.circular(AppRadii.control),
        border: Border.all(color: selected ? AppColors.accent : AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? AppColors.accent : AppColors.mutedText, width: selected ? 4 : 1.5),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: AppText.sans(13, color: selected ? AppColors.primaryText : AppColors.bodyText)),
              ),
            ],
          ),
          if (selected && child != null) ...[const SizedBox(height: 12), Padding(padding: const EdgeInsets.only(left: 24), child: child)],
        ],
      ),
    ),
  );
}

/// A Pill that opens a menu of [items] and shows the picked one.
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.value, required this.items, required this.label, required this.onPick});

  final T value;
  final List<T> items;
  final String Function(T) label;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      menuChildren: [for (final x in items) MenuItemButton(onPressed: () => onPick(x), child: Text(label(x)))],
      builder: (context, menu, _) =>
          Pill(label: '${label(value)}  ▾', selected: true, onTap: () => menu.isOpen ? menu.close() : menu.open()),
    ),
  );
}

class _MoveListCardsDialog extends StatefulWidget {
  const _MoveListCardsDialog({required this.list, required this.count, required this.others});

  final BoardList list;
  final int count;
  final List<BoardList> others;

  @override
  State<_MoveListCardsDialog> createState() => _MoveListCardsDialogState();
}

class _MoveListCardsDialogState extends State<_MoveListCardsDialog> {
  // Default to a list of the same kind, so done cards stay done.
  late BoardList _to = widget.others.firstWhere((o) => o.kind == widget.list.kind, orElse: () => widget.others.first);

  @override
  Widget build(BuildContext context) => AppDialog(
    title: 'Delete ${widget.list.name}?',
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('It has ${widget.count} ${widget.count == 1 ? 'card' : 'cards'} (archived ones included). Move them to:', style: AppText.body),
        const SizedBox(height: 12),
        _Dropdown<BoardList>(
          value: _to,
          items: widget.others,
          label: (l) => l.isDone ? '${l.name} (done)' : l.name,
          onPick: (l) => setState(() => _to = l),
        ),
      ],
    ),
    actions: [
      AppButton(label: 'Cancel', onTap: () => Navigator.pop(context)),
      AppButton(label: 'Move cards and delete', kind: ButtonKind.danger, onTap: () => Navigator.pop(context, _to)),
    ],
  );
}

class _BoardDeleteChoice {
  const _BoardDeleteChoice({required this.move, this.toBoardId, this.tagIds = const []});

  final bool move;
  final int? toBoardId;
  final List<int> tagIds;
}

/// The board-delete warning: move every card to another board (picking tags
/// from that board to add, since tags don't carry over) or delete them all.
class _DeleteBoardDialog extends ConsumerStatefulWidget {
  const _DeleteBoardDialog({required this.board, required this.count, required this.others});

  final Board board;
  final int count;
  final List<Board> others;

  @override
  ConsumerState<_DeleteBoardDialog> createState() => _DeleteBoardDialogState();
}

class _DeleteBoardDialogState extends ConsumerState<_DeleteBoardDialog> {
  bool _move = true;
  late Board _to = widget.others.first;
  final _tags = <int>{};

  @override
  Widget build(BuildContext context) {
    final n = widget.count;
    final cards = '$n ${n == 1 ? 'card' : 'cards'}';
    final target = ref.watch(boardDetailProvider(_to.id)).value;

    return AppDialog(
      title: 'Delete ${widget.board.name}?',
      width: 500,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('It has $cards, archived ones included.', style: AppText.body),
          const SizedBox(height: 14),
          _Choice(
            selected: _move,
            label: 'Move the $cards to another board',
            onTap: () => setState(() => _move = true),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Dropdown<Board>(
                  value: _to,
                  items: widget.others,
                  label: (b) => b.name,
                  onPick: (b) => setState(() {
                    _to = b;
                    _tags.clear();
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  "Lists match by name. Tags don't carry over; pick any from ${_to.name} to add to every moved card:",
                  style: AppText.subtitle,
                ),
                const SizedBox(height: 8),
                if (target == null)
                  const SizedBox(height: 26)
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in target.tags)
                        Pill(
                          label: t.name,
                          leading: Dot(AppColors.tag(t.color)),
                          selected: _tags.contains(t.id),
                          onTap: () => setState(() => _toggle(target, t)),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          _Choice(selected: !_move, label: 'Delete the $cards too', onTap: () => setState(() => _move = false)),
        ],
      ),
      actions: [
        AppButton(label: 'Cancel', onTap: () => Navigator.pop(context)),
        AppButton(
          label: _move ? 'Move cards and delete' : 'Delete board and cards',
          kind: ButtonKind.danger,
          onTap: () => Navigator.pop(
            context,
            _move ? _BoardDeleteChoice(move: true, toBoardId: _to.id, tagIds: _tags.toList()) : const _BoardDeleteChoice(move: false),
          ),
        ),
      ],
    );
  }

  /// A card takes one special tag, so picking one replaces the last.
  void _toggle(BoardDetail target, Tag t) {
    if (!_tags.remove(t.id)) {
      if (t.isSpecial) _tags.removeAll([for (final s in target.specialTags) s.id]);
      _tags.add(t.id);
    }
  }
}
