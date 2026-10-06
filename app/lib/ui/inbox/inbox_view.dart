import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/models.dart';
import '../../state/data.dart';
import '../../theme/tokens.dart';
import '../../util/dates.dart';
import '../widgets.dart';

/// Edits made with E before accepting a voice entry.
class _Edits {
  _Edits(InboxItem item)
    : title = TextEditingController(text: item.parsed.title),
      boardId = item.boardId,
      specialTagId = item.parsed.specialTagId,
      dueAt = item.parsed.dueAt,
      dueAllDay = item.parsed.dueAllDay;

  final TextEditingController title;
  int? boardId;
  int? specialTagId;
  DateTime? dueAt;
  bool dueAllDay;

  Map<String, dynamic> toJson() => {
    'title': title.text.trim(),
    'boardId': boardId,
    'specialTagId': specialTagId,
    'dueAt': dueAt == null ? null : apiTime(dueAt!),
    'dueAllDay': dueAllDay,
  };
}

/// The Inbox: only what needs a human decision, built to be cleared to zero
/// with the keyboard.
class InboxView extends ConsumerStatefulWidget {
  const InboxView({super.key});

  @override
  ConsumerState<InboxView> createState() => _InboxViewState();
}

class _InboxViewState extends ConsumerState<InboxView> {
  InboxType? _type;
  int _selected = 0;
  _Edits? _edits; // non-null while the selected item is being edited
  final _resolving = <int>{};
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  List<InboxItem> _visible(InboxList inbox) => [
    for (final i in inbox.items)
      if ((_type == null || i.type == _type) && !_resolving.contains(i.id)) i,
  ];

  Future<void> _resolve(InboxItem item, String action) async {
    final edits = item.type == InboxType.voice && action == 'accept' ? _edits?.toJson() : null;
    setState(() {
      _resolving.add(item.id);
      _edits = null;
    });
    try {
      await ref.read(apiProvider).resolveInbox(item.id, action, edits: edits);
      if (item.boardId != null) refreshBoardFromWidget(ref, item.boardId!);
      ref.invalidate(boardsProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      ref.invalidate(inboxProvider);
      try {
        await ref.read(inboxProvider.future); // keep the row hidden until the list no longer has it
      } catch (_) {}
      if (mounted) setState(() => _resolving.remove(item.id));
    }
  }

  (String, String)? _primary(InboxType t) => switch (t) {
    InboxType.voice => ('Accept', 'accept'),
    InboxType.change => ('Accept change', 'accept'),
    InboxType.duplicate => ('Merge', 'merge'),
  };

  (String, String)? _secondary(InboxType t) => switch (t) {
    InboxType.voice => ('Discard', 'discard'),
    InboxType.change => ('Ignore', 'ignore'),
    InboxType.duplicate => ('Keep both', 'keep_both'),
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent e, List<InboxItem> items) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (items.isEmpty) return KeyEventResult.ignored;
    final item = items[_selected.clamp(0, items.length - 1)];
    final key = e.logicalKey;
    if (_edits != null) {
      if (key == LogicalKeyboardKey.escape) {
        setState(() => _edits = null);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter) {
        _resolve(item, 'accept');
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored; // typing in the title field
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1).clamp(0, items.length - 1));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = (_selected - 1).clamp(0, items.length - 1));
    } else if (key == LogicalKeyboardKey.enter) {
      _resolve(item, _primary(item.type)!.$2);
    } else if (key == LogicalKeyboardKey.keyE && item.type == InboxType.voice) {
      setState(() => _edits = _Edits(item));
    } else if (key == LogicalKeyboardKey.keyX && item.type != InboxType.duplicate) {
      _resolve(item, _secondary(item.type)!.$2);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider);
    final data = inbox.value;
    final items = data == null ? <InboxItem>[] : _visible(data);
    if (_selected >= items.length && items.isNotEmpty) _selected = items.length - 1;
    final counts = data?.counts;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, e) => _onKey(node, e, items),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Inbox', style: AppText.pageTitle),
                      const SizedBox(height: 4),
                      Text(
                        counts == null ? ' ' : '${counts.all} ${counts.all == 1 ? 'item' : 'items'} to review before they reach the board',
                        style: AppText.subtitle,
                      ),
                    ],
                  ),
                ),
                for (final (key, label) in [('↑↓', 'Move'), ('↵', 'Accept'), ('E', 'Edit'), ('X', 'Discard')]) ...[
                  const SizedBox(width: 16),
                  MonoChip(key),
                  const SizedBox(width: 6),
                  Text(label, style: AppText.sans(12, color: AppColors.mutedText)),
                ],
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                for (final (i, (label, type, n)) in [
                  ('All', null, counts?.all),
                  ('Voice', InboxType.voice, counts?.voice),
                  ('Changes', InboxType.change, counts?.change),
                  ('Duplicates', InboxType.duplicate, counts?.duplicate),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Pill(
                    label: label,
                    count: n == null ? null : '$n',
                    selected: _type == type,
                    onTap: () => setState(() {
                      _type = type;
                      _selected = 0;
                      _edits = null;
                      _focus.requestFocus();
                    }),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: inbox.hasError && data == null
                  ? EmptyState(
                      "Couldn't load the Inbox",
                      detail: '${inbox.error}',
                      action: AppButton(label: 'Retry', onTap: () => ref.invalidate(inboxProvider)),
                    )
                  : data == null
                  ? const SizedBox.shrink()
                  : items.isEmpty
                  ? const EmptyState(
                      'Nothing to review',
                      detail:
                          'Confident voice entries and newly scraped assignments go straight to the board. '
                          'Only guesses, changes, and conflicts land here.',
                    )
                  : ListView(
                      children: [
                        for (final (i, item) in items.indexed) ...[
                          _InboxRow(
                            item: item,
                            selected: i == _selected,
                            edits: i == _selected ? _edits : null,
                            primary: _primary(item.type)!,
                            secondary: _secondary(item.type)!,
                            onSelect: () => setState(() {
                              if (_selected != i) _edits = null;
                              _selected = i;
                              _focus.requestFocus();
                            }),
                            onAction: (action) => _resolve(item, action),
                            onEdit: () => setState(() {
                              _selected = i;
                              _edits = _edits == null ? _Edits(item) : null;
                            }),
                            onEditsChanged: () => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          'Confident voice entries and newly scraped assignments go straight to the board. '
                          'Only guesses, changes, and conflicts land here.',
                          style: AppText.sans(12, color: AppColors.mutedText),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxRow extends ConsumerWidget {
  const _InboxRow({
    required this.item,
    required this.selected,
    required this.edits,
    required this.primary,
    required this.secondary,
    required this.onSelect,
    required this.onAction,
    required this.onEdit,
    required this.onEditsChanged,
  });

  final InboxItem item;
  final bool selected;
  final _Edits? edits;
  final (String, String) primary;
  final (String, String) secondary;
  final VoidCallback onSelect;
  final ValueChanged<String> onAction;
  final VoidCallback onEdit;
  final VoidCallback onEditsChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowProvider);
    final boardId = edits?.boardId ?? item.boardId;
    final board = boardId == null ? null : ref.watch(boardDetailProvider(boardId)).value;
    final typeLabel = item.type.name.toUpperCase();
    final meta = item.type == InboxType.voice ? ago(item.receivedAt, now) : '${item.source} · ${ago(item.receivedAt, now)}';
    final raw = switch (item.type) {
      InboxType.change => item.rawText.replaceAll(' / ', '\n'),
      _ => '"${item.rawText}"',
    };

    return GestureDetector(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: selected ? AppColors.accent : AppColors.cardBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 290,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      MonoChip(typeLabel),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(meta, style: AppText.mono(11), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(raw, style: AppText.mono(13, color: AppColors.bodyText, height: 1.4)),
                  if (edits != null) ...[const SizedBox(height: 10), _BoardPicker(edits: edits!, onChanged: onEditsChanged)],
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(child: _parsed(context, ref, board)),
            const SizedBox(width: 24),
            SizedBox(
              width: 216,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppButton(
                    label: primary.$1,
                    small: true,
                    kind: selected ? ButtonKind.primary : ButtonKind.outline,
                    onTap: () => onAction(primary.$2),
                  ),
                  if (item.type == InboxType.voice) AppButton(label: edits == null ? 'Edit' : 'Done', small: true, onTap: onEdit),
                  AppButton(label: secondary.$1, small: true, onTap: () => onAction(secondary.$2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _parsed(BuildContext context, WidgetRef ref, BoardDetail? board) {
    final p = item.parsed;
    final classLabel = board == null ? 'TAG' : _singular(board.board.specialTagLabel).toUpperCase();

    if (item.type == InboxType.duplicate) {
      final match = item.cardId == null ? null : ref.watch(cardDetailProvider(item.cardId!)).value;
      return _Field(
        label: 'MATCHES',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(match?.summary.title ?? '…', style: _value),
            const SizedBox(height: 4),
            Text('already on board · ${match?.sourceName ?? ''}', style: AppText.mono(11)),
          ],
        ),
      );
    }

    final e = edits;
    final specialId = e?.specialTagId ?? p.specialTagId;
    final special = board?.tag(e != null ? e.specialTagId : p.specialTagId);
    final dueAt = e != null ? e.dueAt : p.dueAt;
    final dueAllDay = e != null ? e.dueAllDay : p.dueAllDay;
    final change = item.change;

    final Widget title = e != null
        ? TextField(controller: e.title, autofocus: true, style: _value, decoration: _editDecoration)
        : change?.field == 'title'
        ? _Diff(change!.oldValue ?? '', change.newValue ?? '')
        : Text(p.title, style: _value);

    final Widget classValue = e != null && board != null
        ? MenuAnchor(
            menuChildren: [
              for (final t in board.specialTags)
                MenuItemButton(
                  leadingIcon: Dot(AppColors.tag(t.color)),
                  onPressed: () {
                    e.specialTagId = t.id;
                    onEditsChanged();
                  },
                  child: Text(t.name),
                ),
              MenuItemButton(
                onPressed: () {
                  e.specialTagId = null;
                  onEditsChanged();
                },
                child: const Text('None'),
              ),
            ],
            builder: (context, menu, _) => Hover(
              onTap: menu.open,
              builder: (context, h) => FadeText('${special?.name ?? 'None'} ▾', style: _value.copyWith(color: h ? AppColors.accent : null)),
            ),
          )
        : _MaybeUncertain(value: special?.name ?? (specialId == null ? '—' : '…'), reason: e == null ? p.uncertain['specialTagId'] : null);

    String dueText(String? iso) => iso == null ? 'none' : shortDate(DateTime.parse(iso).toLocal());
    final Widget dueValue = change?.field == 'dueAt'
        ? _Diff(dueText(change!.oldValue), dueText(change.newValue))
        : e != null
        ? Hover(
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: e.dueAt ?? now,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 5),
              );
              if (d == null) return;
              e.dueAt = DateTime(d.year, d.month, d.day, 23, 59);
              e.dueAllDay = true;
              onEditsChanged();
            },
            builder: (context, h) => FadeText(
              '${dueAt == null ? 'No due date' : shortDate(dueAt)} ▾',
              style: _value.copyWith(color: h ? AppColors.accent : null),
            ),
          )
        : _MaybeUncertain(
            value: dueAt == null ? 'No due date' : (dueAllDay ? shortDate(dueAt) : dueFull(dueAt, false)),
            reason: p.uncertain['dueAt'],
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Field(label: 'TITLE', child: title),
        ),
        const SizedBox(width: 24),
        SizedBox(
          width: 100,
          child: _Field(label: classLabel, child: classValue),
        ),
        const SizedBox(width: 24),
        SizedBox(
          width: 190,
          child: _Field(label: 'DUE', child: dueValue),
        ),
      ],
    );
  }
}

final _value = AppText.sans(13, weight: FontWeight.w500, color: AppColors.primaryText);

const _editDecoration = InputDecoration(
  isDense: true,
  contentPadding: EdgeInsets.symmetric(vertical: 4),
  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.mutedText)),
  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.accent)),
);

String _singular(String s) {
  final l = s.toLowerCase();
  for (final end in ['sses', 'xes', 'ches', 'shes']) {
    if (l.endsWith(end)) return s.substring(0, s.length - 2);
  }
  return s.endsWith('s') ? s.substring(0, s.length - 1) : s;
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppText.mono(10, weight: FontWeight.w500)),
      const SizedBox(height: 4),
      child,
    ],
  );
}

/// A parsed value; when the parser was unsure it shows in Accent with "?" and
/// the reason underneath.
class _MaybeUncertain extends StatelessWidget {
  const _MaybeUncertain({required this.value, this.reason});

  final String value;
  final String? reason;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(reason == null ? value : '$value ?', style: _value.copyWith(color: reason == null ? null : AppColors.accent)),
      if (reason != null) ...[const SizedBox(height: 4), Text(reason!, style: AppText.mono(11))],
    ],
  );
}

/// Old value struck through → new value in Accent.
class _Diff extends StatelessWidget {
  const _Diff(this.oldValue, this.newValue);

  final String oldValue;
  final String newValue;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      Text(
        oldValue,
        style: AppText.sans(
          13,
          color: AppColors.mutedText,
        ).copyWith(decoration: TextDecoration.lineThrough, decorationColor: AppColors.mutedText),
      ),
      Text('→', style: AppText.sans(13, color: AppColors.mutedText)),
      Text(newValue, style: _value.copyWith(color: AppColors.accent)),
    ],
  );
}

class _BoardPicker extends ConsumerWidget {
  const _BoardPicker({required this.edits, required this.onChanged});

  final _Edits edits;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boards = ref.watch(boardsProvider).value ?? const [];
    final current = boards.where((b) => b.id == edits.boardId).firstOrNull;
    return MenuAnchor(
      menuChildren: [
        for (final b in boards)
          MenuItemButton(
            onPressed: () {
              if (b.id != edits.boardId) {
                edits.boardId = b.id;
                edits.specialTagId = null; // special tags belong to one board
                onChanged();
              }
            },
            child: Text(b.name),
          ),
      ],
      builder: (context, menu, _) => Hover(
        onTap: menu.open,
        builder: (context, h) => FadeText(
          'board: ${current?.name ?? 'pick one'} ▾',
          style: AppText.mono(11, color: h || current == null ? AppColors.accent : AppColors.mutedText),
        ),
      ),
    );
  }
}

/// Left side of the status bar on the Inbox view.
String inboxStatus(InboxList? inbox, Board? board) => '${inbox?.counts.all ?? 0} to review · ${board?.openCount ?? 0} open on board';
