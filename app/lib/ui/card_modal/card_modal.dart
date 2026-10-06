import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/client.dart';
import '../../api/models.dart';
import '../../state/data.dart';
import '../../state/ui.dart';
import '../../theme/tokens.dart';
import '../../util/dates.dart';
import '../board/board_view.dart' show CheckBox;
import '../dialogs.dart';
import '../widgets.dart';

/// Shows the Card Modal over the current view while a card is open.
class CardModalHost extends ConsumerStatefulWidget {
  const CardModalHost({super.key});

  @override
  ConsumerState<CardModalHost> createState() => _CardModalHostState();
}

class _CardModalHostState extends ConsumerState<CardModalHost> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Esc closes the modal wherever keyboard focus is (a text field, or
  /// nowhere after a field loses focus). A dialog or picker opened from the
  /// modal is its own route, so it gets Esc instead.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) return false;
    if (ref.read(openCardProvider) == null || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    ref.read(openCardProvider.notifier).close();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final id = ref.watch(openCardProvider);
    if (id == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => ref.read(openCardProvider.notifier).close(),
              child: const ColoredBox(color: Color(0x99000000)),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
              child: CardModal(key: ValueKey(id), cardId: id),
            ),
          ),
        ],
      ),
    );
  }
}

class CardModal extends ConsumerStatefulWidget {
  const CardModal({super.key, required this.cardId});

  final int cardId;

  @override
  ConsumerState<CardModal> createState() => _CardModalState();
}

class _CardModalState extends ConsumerState<CardModal> {
  CardDetail? _card;
  Object? _loadError;
  List<NoteBlock> _blocks = [];
  DateTime? _editedAt;
  Timer? _saveTimer;
  bool _dirty = false; // notes changed since the last save started
  bool _saving = false;
  final _title = TextEditingController();
  final _titleFocus = FocusNode();
  final _controllers = <String, TextEditingController>{};
  final _listNames = <String, TextEditingController>{}; // by the list's first todo id
  final _focus = <String, FocusNode>{};

  // Captured up front: notes are flushed from dispose(), when ref can no longer be read.
  late final ApiClient _api;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiProvider);
    _load();
    _titleFocus.addListener(() {
      if (!_titleFocus.hasFocus) _saveTitle();
    });
  }

  Future<void> _load() async {
    try {
      final c = await _api.card(widget.cardId);
      if (!mounted) return;
      setState(() {
        _card = c;
        _blocks = _joinText(c.notes).$1;
        _title.text = c.summary.title;
        _editedAt = c.summary.updatedAt;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    _flushNotes();
    _title.dispose();
    _titleFocus.dispose();
    for (final c in [..._controllers.values, ..._listNames.values]) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _close() => ref.read(openCardProvider.notifier).close();

  void _refreshBoard() {
    final c = _card;
    if (c != null) refreshBoardFromWidget(ref, c.summary.boardId);
    ref.invalidate(inboxProvider);
  }

  /// PATCHes [fields], adopts the server's version of the card, and refreshes the board.
  Future<void> _patch(Map<String, dynamic> fields) async {
    try {
      final updated = await _api.updateCard(widget.cardId, fields);
      if (!mounted) return;
      setState(() {
        _card = updated;
        _editedAt = updated.summary.updatedAt;
      });
      _refreshBoard();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _saveTitle() {
    final t = _title.text.trim();
    if (_card == null) return;
    if (t.isEmpty) {
      _title.text = _card!.summary.title;
    } else if (t != _card!.summary.title) {
      _patch({'title': t});
    }
  }

  // ---- notes ----

  String _newId() => 'b${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1296).toRadixString(36)}';

  TextEditingController _ctl(NoteBlock b) =>
      _controllers.putIfAbsent(b.id, () => TextEditingController(text: b.type == BlockType.link ? b.title : b.text));

  FocusNode _node(NoteBlock b) => _focus.putIfAbsent(b.id, FocusNode.new);

  void _setBlocks(List<NoteBlock> next) {
    setState(() => _blocks = next);
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _flushNotes);
  }

  void _updateBlock(NoteBlock b) => _setBlocks([for (final x in _blocks) x.id == b.id ? b : x]);

  /// Saves the notes if they changed: 800ms after the last edit, before Mark
  /// as done, and when the modal closes.
  void _flushNotes() {
    _saveTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    final blocks = [..._blocks];
    _saving = true;
    _api
        .saveNotes(widget.cardId, blocks)
        .then((at) {
          _saving = false;
          if (mounted) setState(() => _editedAt = at);
        })
        .catchError((Object e) {
          _saving = false;
          _dirty = true; // try again on the next edit or on close
          if (mounted) showError(context, "Notes weren't saved: $e");
        });
  }

  Future<void> _insert(BlockType type, {int? at}) async {
    NoteBlock block;
    if (type == BlockType.link) {
      final link = await _askLink();
      if (link == null) return;
      block = NoteBlock(id: _newId(), type: type, title: link.$1, url: link.$2);
    } else {
      block = NoteBlock(id: _newId(), type: type);
    }
    _edit([..._blocks]..insert(at ?? _blocks.length, block), focus: type == BlockType.link ? null : block.id);
  }

  /// Notes read like a Markdown file: text blocks never sit next to each
  /// other, they're one block of lines. Joins any that do; [focus] and
  /// [offset] follow the text into the block it joins.
  static (List<NoteBlock>, String?, int) _joinText(List<NoteBlock> blocks, [String? focus, int offset = 0]) {
    final out = <NoteBlock>[];
    for (final b in blocks) {
      if (b.type == BlockType.text && out.isNotEmpty && out.last.type == BlockType.text) {
        final into = out.removeLast();
        if (b.id == focus) (focus, offset) = (into.id, offset + into.text.length + 1);
        out.add(into.copyWith(text: '${into.text}\n${b.text}'));
      } else {
        out.add(b);
      }
    }
    return (out, focus, offset);
  }

  /// Applies a change to the notes, then puts the cursor in [focus] at
  /// [offset] (the end when null).
  void _edit(List<NoteBlock> next, {String? focus, int? offset}) {
    final focusBlock = next.where((b) => b.id == focus).firstOrNull;
    final (blocks, focusId, at) = _joinText(next, focus, offset ?? focusBlock?.text.length ?? 0);
    final ids = {for (final b in blocks) b.id};
    for (final map in [_controllers, _listNames]) {
      for (final id in [...map.keys.where((id) => !ids.contains(id))]) {
        map.remove(id)!.dispose();
      }
    }
    for (final b in blocks) {
      final c = _controllers[b.id];
      final text = b.type == BlockType.link ? b.title : b.text;
      if (c != null && c.text != text) c.text = text;
      final n = _listNames[b.id];
      if (n != null && n.text != b.title) n.text = b.title;
    }
    _setBlocks(blocks);
    if (focusId != null) WidgetsBinding.instance.addPostFrameCallback((_) => _focusAt(focusId, at));
  }

  void _focusAt(String id, int offset) {
    final b = _blocks.where((x) => x.id == id).firstOrNull;
    if (b == null || b.type == BlockType.link) return;
    _node(b).requestFocus();
    _ctl(b).selection = TextSelection.collapsed(offset: offset.clamp(0, _ctl(b).text.length));
  }

  bool _startsList(int i) => _blocks[i].type == BlockType.todo && (i == 0 || _blocks[i - 1].type != BlockType.todo);

  /// [b], at [at] in the current blocks, is leaving its list. If it named
  /// the list, the todo at [heir] in [next] takes the name.
  void _passListName(List<NoteBlock> next, NoteBlock b, int at, int heir) {
    if (_startsList(at) && b.title.isNotEmpty && heir < next.length && next[heir].type == BlockType.todo) {
      next[heir] = next[heir].copyWith(title: b.title);
    }
  }

  void _removeBlock(NoteBlock b) {
    final i = _blocks.indexWhere((x) => x.id == b.id);
    _passListName(_blocks, b, i, i + 1); // before removal, the heir is at i + 1
    final next = [..._blocks]..removeAt(i);
    _edit(next);
  }

  /// Focuses the nearest editable block before (dir -1, cursor at its end)
  /// or after (dir 1, at its start). Returns false at the edge.
  bool _focusNeighbour(NoteBlock b, int dir) {
    var i = _blocks.indexWhere((x) => x.id == b.id) + dir;
    while (i >= 0 && i < _blocks.length && _blocks[i].type == BlockType.link) {
      i += dir;
    }
    if (i < 0 || i >= _blocks.length) return false;
    _focusAt(_blocks[i].id, dir < 0 ? _blocks[i].text.length : 0);
    return true;
  }

  /// Backspace with the cursor at the start of [b]. A todo loses its checkbox
  /// and becomes a text line; a text line joins the todo above it.
  bool _backspaceAtStart(NoteBlock b) {
    final i = _blocks.indexWhere((x) => x.id == b.id);
    final next = [..._blocks];
    final text = _ctl(b).text;
    if (b.type == BlockType.todo) {
      // A new id gives the line a new text field and focus, so typing reaches it.
      final line = NoteBlock(id: _newId(), type: BlockType.text, text: text);
      next[i] = line;
      _passListName(next, b, i, i + 1);
      _edit(next, focus: line.id, offset: 0);
      return true;
    }
    final prev = i > 0 ? _blocks[i - 1] : null;
    if (prev?.type == BlockType.todo) {
      final nl = text.indexOf('\n');
      next[i - 1] = prev!.copyWith(text: prev.text + (nl < 0 ? text : text.substring(0, nl)));
      if (nl < 0) {
        next.removeAt(i);
      } else {
        next[i] = b.copyWith(text: text.substring(nl + 1));
      }
      _edit(next, focus: prev.id, offset: prev.text.length);
      return true;
    }
    if (text.isEmpty && _blocks.length > 1) {
      // An empty line after a link, or first in the notes.
      final neighbour = [
        for (final x in _blocks.reversed.skip(_blocks.length - i)) x,
        for (final x in _blocks.skip(i + 1)) x,
      ].where((x) => x.type != BlockType.link).firstOrNull;
      next.removeAt(i);
      _edit(next, focus: neighbour?.id, offset: neighbour == null || _blocks.indexOf(neighbour) > i ? 0 : null);
      return true;
    }
    return false;
  }

  /// Enter in a todo. On an empty todo it ends the list (the line becomes
  /// text); at the start of a list's first todo it opens a text line above
  /// the list; otherwise it splits the todo at the cursor.
  bool _enterInTodo(NoteBlock b) {
    final i = _blocks.indexWhere((x) => x.id == b.id);
    final ctl = _ctl(b);
    final text = ctl.text;
    final sel = ctl.selection.isValid ? ctl.selection : TextSelection.collapsed(offset: text.length);
    final next = [..._blocks];
    if (text.isEmpty) {
      final line = NoteBlock(id: _newId(), type: BlockType.text);
      next[i] = line;
      _passListName(next, b, i, i + 1);
      _edit(next, focus: line.id, offset: 0);
    } else if (sel.end == 0 && _startsList(i)) {
      final line = NoteBlock(id: _newId(), type: BlockType.text);
      next.insert(i, line);
      _edit(next, focus: line.id, offset: 0);
    } else {
      final rest = NoteBlock(id: _newId(), type: BlockType.todo, text: text.substring(sel.end));
      next[i] = b.copyWith(text: text.substring(0, sel.start));
      next.insert(i + 1, rest);
      _edit(next, focus: rest.id, offset: 0);
    }
    return true;
  }

  /// Whether the cursor is on the first (or last) visual line of [b], so Up
  /// (or Down) should move to the neighbouring block.
  bool _onEdgeLine(NoteBlock b, {required bool first}) {
    final ctl = _ctl(b);
    final sel = ctl.selection;
    if (!sel.isValid || !sel.isCollapsed) return false;
    final render = _node(b).context?.findAncestorStateOfType<EditableTextState>()?.renderEditable;
    if (render == null) {
      return !(first ? ctl.text.substring(0, sel.baseOffset) : ctl.text.substring(sel.baseOffset)).contains('\n');
    }
    double top(int offset) => render.getLocalRectForCaret(TextPosition(offset: offset)).top;
    return (top(sel.baseOffset) - top(first ? 0 : ctl.text.length)).abs() < 1;
  }

  /// Clicking below the last block writes after it.
  void _writeAtEnd() {
    final last = _blocks.lastOrNull;
    if (last?.type == BlockType.text) {
      _focusAt(last!.id, last.text.length);
    } else {
      _insert(BlockType.text);
    }
  }

  Future<(String, String)?> _askLink({String title = '', String url = ''}) async {
    final t = TextEditingController(text: title);
    final u = TextEditingController(text: url);
    return showDialog<(String, String)>(
      context: context,
      builder: (context) {
        void submit() {
          final link = u.text.trim();
          if (link.isEmpty) return;
          final withScheme = link.contains('://') ? link : 'https://$link';
          Navigator.pop(context, (t.text.trim().isEmpty ? link : t.text.trim(), withScheme));
        }

        return AppDialog(
          title: url.isEmpty ? 'Add link' : 'Edit link',
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(controller: u, hint: 'https://…', autofocus: true, mono: true, onSubmitted: (_) => submit()),
              const SizedBox(height: 10),
              AppTextField(controller: t, hint: 'Title (optional)', onSubmitted: (_) => submit()),
            ],
          ),
          actions: [
            AppButton(label: 'Cancel', onTap: () => Navigator.pop(context)),
            AppButton(label: url.isEmpty ? 'Add' : 'Save', kind: ButtonKind.primary, onTap: submit),
          ],
        );
      },
    );
  }

  // ---- due ----

  Future<void> _pickDue() async {
    final c = _card!.summary;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: c.dueAt ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: c.dueAt != null && !c.dueAllDay ? TimeOfDay.fromDateTime(c.dueAt!) : const TimeOfDay(hour: 23, minute: 59),
      helpText: 'Due time (cancel for all day)',
    );
    final allDay = time == null;
    final t = time ?? const TimeOfDay(hour: 23, minute: 59);
    final due = DateTime(date.year, date.month, date.day, t.hour, t.minute);
    await _patch({'dueAt': apiTime(due), 'dueAllDay': allDay});
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final detail = card == null ? null : ref.watch(boardDetailProvider(card.summary.boardId)).value;

    Widget body;
    if (_loadError != null) {
      body = SizedBox(height: 200, child: EmptyState("Couldn't open this card", detail: '$_loadError'));
    } else if (card == null || detail == null) {
      body = const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    } else {
      body = _content(card, detail);
    }

    return FocusScope(
      autofocus: true,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 760,
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - 96),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadii.modal),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 64, offset: Offset(0, 24))],
          ),
          child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24), child: body),
        ),
      ),
    );
  }

  Widget _content(CardDetail card, BoardDetail detail) {
    final c = card.summary;
    final now = ref.watch(nowProvider);
    final list = detail.list(c.listId);
    final special = detail.tag(c.specialTagId);
    final sourceLabel = card.sourceName[0].toUpperCase() + card.sourceName.substring(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: special tag, regular tags, + tag; list dropdown and close.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MenuAnchor(
                    alignmentOffset: const Offset(0, 4),
                    menuChildren: [
                      for (final t in detail.specialTags)
                        MenuItemButton(
                          leadingIcon: Dot(AppColors.tag(t.color)),
                          trailingIcon: t.id == c.specialTagId ? Text('✓', style: AppText.sans(13, color: AppColors.accent)) : null,
                          onPressed: () => _patch({'specialTagId': t.id}),
                          child: Text(t.name),
                        ),
                      if (special != null) MenuItemButton(onPressed: () => _patch({'specialTagId': null}), child: const Text('None')),
                    ],
                    builder: (context, menu, _) => _TagChip(
                      label: special?.name ?? 'No ${detail.board.specialTagLabel.toLowerCase()}',
                      color: special == null ? null : AppColors.tag(special.color),
                      onTap: () => menu.isOpen ? menu.close() : menu.open(),
                    ),
                  ),
                  for (final id in c.tagIds)
                    if (detail.tag(id) case final t?)
                      _TagChip(
                        label: t.name,
                        color: AppColors.tag(t.color),
                        tooltip: 'Remove ${t.name}',
                        onTap: () => _patch({
                          'tagIds': [
                            for (final x in c.tagIds)
                              if (x != t.id) x,
                          ],
                        }),
                      ),
                  MenuAnchor(
                    alignmentOffset: const Offset(0, 4),
                    menuChildren: [
                      for (final t in detail.regularTags)
                        MenuItemButton(
                          closeOnActivate: false,
                          leadingIcon: Dot(AppColors.tag(t.color)),
                          trailingIcon: c.tagIds.contains(t.id) ? Text('✓', style: AppText.sans(13, color: AppColors.accent)) : null,
                          onPressed: () => _patch({
                            'tagIds': c.tagIds.contains(t.id)
                                ? [
                                    for (final x in c.tagIds)
                                      if (x != t.id) x,
                                  ]
                                : [...c.tagIds, t.id],
                          }),
                          child: Text(t.name),
                        ),
                    ],
                    builder: (context, menu, _) => Hover(
                      onTap: () => menu.isOpen ? menu.close() : menu.open(),
                      builder: (context, hovered) =>
                          FadeText('+ tag', style: AppText.sans(12, color: hovered ? AppColors.bodyText : AppColors.mutedText)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            MenuAnchor(
              alignmentOffset: const Offset(0, 4),
              menuChildren: [
                for (final l in detail.lists)
                  MenuItemButton(
                    trailingIcon: l.id == c.listId ? Text('✓', style: AppText.sans(13, color: AppColors.accent)) : null,
                    onPressed: () => _patch({'listId': l.id}),
                    child: Text(l.name),
                  ),
              ],
              builder: (context, menu, _) => Hover(
                onTap: () => menu.isOpen ? menu.close() : menu.open(),
                builder: (context, hovered) => AnimatedContainer(
                  duration: kHoverFade,
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: hovered ? const Color(0xFF444444) : AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(AppRadii.row),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        list?.name ?? '',
                        style: AppText.sans(12, weight: FontWeight.w500, color: AppColors.primaryText),
                      ),
                      const SizedBox(width: 6),
                      Text('▾', style: AppText.sans(9, color: AppColors.mutedText)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Hover(
              onTap: _close,
              builder: (context, h) => FadeIcon(Icons.close, color: h ? AppColors.bodyText : AppColors.mutedText),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Title and provenance.
        TextField(
          controller: _title,
          focusNode: _titleFocus,
          maxLines: null,
          style: AppText.modalTitle,
          decoration: const InputDecoration.collapsed(hintText: 'Title'),
          onSubmitted: (_) => _titleFocus.unfocus(),
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 6),
        DefaultTextStyle(
          style: AppText.mono(11),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('from ${card.sourceName}'),
              if (card.sourceUrl != null) ...[
                const Text('·'),
                Hover(
                  onTap: () => launchUrl(Uri.parse(card.sourceUrl!)),
                  builder: (context, h) => FadeText(
                    'Open on $sourceLabel ↗',
                    style: AppText.mono(11, color: AppColors.accent).copyWith(decoration: h ? TextDecoration.underline : null),
                  ),
                ),
              ],
              const Text('·'),
              Text('added ${monthDay(c.createdAt)}'),
              if (card.lastSyncedAt != null) ...[const Text('·'), Text('synced ${ago(card.lastSyncedAt!, now)}')],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Due.
        Row(
          children: [
            Hover(
              onTap: _pickDue,
              builder: (context, hovered) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Due', size: 10),
                  const SizedBox(height: 4),
                  Text(
                    c.dueAt == null ? 'No due date' : dueFull(c.dueAt!, c.dueAllDay),
                    style: AppText.sans(13, weight: FontWeight.w500, color: hovered ? AppColors.accent : AppColors.bodyText),
                  ),
                  const SizedBox(height: 4),
                  Text(c.dueAt == null ? 'click to set' : relativeDay(c.dueAt!, now), style: AppText.mono(11)),
                ],
              ),
            ),
            if (c.dueAt != null) ...[
              const SizedBox(width: 16),
              Hover(
                onTap: () => _patch({'dueAt': null, 'dueAllDay': false}),
                builder: (context, h) => FadeText('clear', style: AppText.mono(11, color: h ? AppColors.danger : AppColors.mutedText)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        const Divider(height: 1, thickness: 1, color: AppColors.cardBorder),
        const SizedBox(height: 20),

        // Notes.
        const SectionLabel('Notes', size: 10),
        const SizedBox(height: 16),
        ..._notes(),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final (label, type) in [('+ Text', BlockType.text), ('+ Todo', BlockType.todo), ('+ Link', BlockType.link)]) ...[
              Hover(
                onTap: () => _insert(type),
                builder: (context, h) => FadeText(label, style: AppText.sans(12, color: h ? AppColors.bodyText : AppColors.mutedText)),
              ),
              const SizedBox(width: 16),
            ],
            Text('or type /todo, /text, or /link on a line', style: AppText.mono(11)),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(height: 1, thickness: 1, color: AppColors.cardBorder),
        const SizedBox(height: 20),

        // Footer.
        Row(
          children: [
            Expanded(
              child: Text(
                _saving || _dirty ? 'Saving…' : 'Saved automatically${_editedAt == null ? '' : ' · edited ${ago(_editedAt!, now)}'}',
                style: AppText.mono(11),
              ),
            ),
            AppButton(
              label: c.archivedAt == null ? 'Archive' : 'Unarchive',
              kind: ButtonKind.outline,
              onTap: () async {
                await _patch({'archived': c.archivedAt == null});
                if (c.archivedAt == null) _close();
              },
            ),
            const SizedBox(width: 12),
            AppButton(
              label: 'Delete',
              kind: ButtonKind.danger,
              onTap: () async {
                final ok = await confirm(context, title: 'Delete card?', message: '“${c.title}” and its notes will be deleted.');
                if (!ok) return;
                try {
                  await _api.deleteCard(c.id);
                  _refreshBoard();
                  _close();
                } catch (e) {
                  if (mounted) showError(context, e);
                }
              },
            ),
            const SizedBox(width: 12),
            if (!(list?.isDone ?? false))
              AppButton(
                label: 'Mark as done',
                kind: ButtonKind.primary,
                onTap: () async {
                  try {
                    _flushNotes();
                    await _api.markDone(c.id);
                    _refreshBoard();
                    _close();
                  } catch (e) {
                    if (mounted) showError(context, e);
                  }
                },
              ),
          ],
        ),
      ],
    );
  }

  /// Each unbroken run of todos is one list, headed by its name and count.
  /// The name lives on the run's first todo as its title.
  Widget _todoListHeader(NoteBlock first, int index) {
    final run = _blocks.skip(index).takeWhile((x) => x.type == BlockType.todo).toList();
    final ctl = _listNames.putIfAbsent(first.id, () => TextEditingController(text: first.title));
    final style = AppText.sans(13, weight: FontWeight.w500, color: AppColors.headingText);
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 0 : 8, bottom: 4),
      child: Row(
        children: [
          IntrinsicWidth(
            child: TextField(
              key: ValueKey('todo-list-name-${first.id}'),
              controller: ctl,
              style: style,
              maxLines: 1,
              decoration: InputDecoration.collapsed(hintText: 'Todos', hintStyle: style),
              onChanged: (v) => _updateBlock(first.copyWith(title: v.trim())),
            ),
          ),
          const SizedBox(width: 8),
          Text('${run.where((s) => s.done).length}/${run.length}', style: AppText.mono(11)),
        ],
      ),
    );
  }

  List<Widget> _notes() {
    final out = <Widget>[];
    for (final (i, b) in _blocks.indexed) {
      if (b.type == BlockType.todo && (i == 0 || _blocks[i - 1].type != BlockType.todo)) {
        out.add(_todoListHeader(b, i));
      }
      out.add(switch (b.type) {
        BlockType.text => Padding(padding: const EdgeInsets.only(bottom: 10), child: _textField(b, i)),
        BlockType.todo => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _updateBlock(b.copyWith(done: !b.done)),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: CheckBox(checked: b.done, size: 15),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _textField(b, i)),
            ],
          ),
        ),
        BlockType.link => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _LinkBlock(
            block: b,
            onEdit: () async {
              final link = await _askLink(title: b.title, url: b.url);
              if (link != null) _updateBlock(b.copyWith(title: link.$1, url: link.$2));
            },
            onRemove: () => _removeBlock(b),
          ),
        ),
      });
    }
    if (_blocks.isNotEmpty) {
      out.add(
        Hover(
          key: const ValueKey('notes-end'),
          cursor: SystemMouseCursors.text,
          onTap: _writeAtEnd,
          builder: (context, h) => const SizedBox(width: double.infinity, height: 24),
        ),
      );
    }
    if (_blocks.isEmpty) {
      // Clicking the empty notes area starts a text block right there.
      out.add(
        Hover(
          cursor: SystemMouseCursors.text,
          onTap: () => _insert(BlockType.text),
          builder: (context, h) => SizedBox(
            width: double.infinity,
            child: FadeText(
              'Write a note…',
              style: AppText.sans(14, height: 1.45, color: h ? AppColors.bodyText : const Color(0x80ABABAB)),
            ),
          ),
        ),
      );
    }
    return out;
  }

  Widget _textField(NoteBlock b, int index) {
    final isTodo = b.type == BlockType.todo;
    final done = isTodo && b.done;
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final enter = key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;
        if (event is KeyDownEvent && (key == LogicalKeyboardKey.space || enter) && _runSlashCommand(b)) {
          return KeyEventResult.handled;
        }
        final keys = HardwareKeyboard.instance;
        if (keys.isShiftPressed || keys.isControlPressed || keys.isAltPressed || keys.isMetaPressed) return KeyEventResult.ignored;
        final ctl = _ctl(b);
        final sel = ctl.selection;
        final atStart = sel.isValid && sel.isCollapsed && sel.baseOffset == 0;
        final atEnd = sel.isValid && sel.isCollapsed && sel.baseOffset == ctl.text.length;
        final handled = switch (key) {
          LogicalKeyboardKey.backspace when atStart => _backspaceAtStart(b),
          _ when enter && isTodo => _enterInTodo(b),
          LogicalKeyboardKey.arrowUp when _onEdgeLine(b, first: true) => _focusNeighbour(b, -1),
          LogicalKeyboardKey.arrowDown when _onEdgeLine(b, first: false) => _focusNeighbour(b, 1),
          LogicalKeyboardKey.arrowLeft when atStart => _focusNeighbour(b, -1),
          LogicalKeyboardKey.arrowRight when atEnd => _focusNeighbour(b, 1),
          _ => false,
        };
        return handled ? KeyEventResult.handled : KeyEventResult.ignored;
      },
      child: TextField(
        controller: _ctl(b),
        focusNode: _node(b),
        maxLines: isTodo ? 1 : null,
        style: isTodo
            ? AppText.sans(
                13,
                color: done ? AppColors.mutedText : AppColors.bodyText,
              ).copyWith(decoration: done ? TextDecoration.lineThrough : null, decorationColor: AppColors.mutedText)
            : AppText.sans(14, height: 1.45),
        decoration: InputDecoration.collapsed(
          hintText: isTodo ? 'Todo' : 'Write something…',
          hintStyle: AppText.sans(13, color: const Color(0x80ABABAB)),
        ),
        onChanged: (v) => _updateBlock(b.copyWith(text: v)),
      ),
    );
  }

  static const _slashCommands = {'/text': BlockType.text, '/todo': BlockType.todo, '/link': BlockType.link};

  /// A line that is just "/todo", "/text", or "/link" with the cursor at its
  /// end turns into that block when Space or Enter is pressed. In a text block
  /// with other lines, the block splits around it. Returns whether it did.
  bool _runSlashCommand(NoteBlock b) {
    final ctl = _ctl(b);
    final text = ctl.text;
    final sel = ctl.selection;
    if (!sel.isValid || !sel.isCollapsed) return false;
    final cursor = sel.baseOffset;
    final lineStart = cursor == 0 ? 0 : text.lastIndexOf('\n', cursor - 1) + 1;
    final nl = text.indexOf('\n', cursor);
    final lineEnd = nl == -1 ? text.length : nl;
    if (text.substring(cursor, lineEnd).trim().isNotEmpty) return false;
    final type = _slashCommands[text.substring(lineStart, cursor).trim().toLowerCase()];
    if (type == null) return false;

    final before = text.substring(0, lineStart).replaceFirst(RegExp(r'\n$'), '');
    final after = text.substring(lineEnd).replaceFirst(RegExp(r'^\n'), '');
    _applySlashCommand(b, type, before, after);
    return true;
  }

  Future<void> _applySlashCommand(NoteBlock b, BlockType type, String before, String after) async {
    NoteBlock block;
    if (type == BlockType.link) {
      final link = await _askLink();
      if (!mounted) return;
      if (link == null) {
        // Cancelled: drop the command text and keep typing where it was.
        final joined = [before, after].where((x) => x.isNotEmpty).join('\n');
        _ctl(b)
          ..text = joined
          ..selection = TextSelection.collapsed(offset: before.length);
        _updateBlock(b.copyWith(text: joined));
        _node(b).requestFocus();
        return;
      }
      block = NoteBlock(id: _newId(), type: type, title: link.$1, url: link.$2);
    } else {
      block = NoteBlock(id: _newId(), type: type);
    }
    final replacement = [
      if (before.isNotEmpty) b.copyWith(text: before),
      block,
      if (after.isNotEmpty) NoteBlock(id: _newId(), type: b.type, text: after),
    ];
    final i = _blocks.indexWhere((x) => x.id == b.id);
    _edit([..._blocks]..replaceRange(i, i + 1, replacement), focus: type == BlockType.link ? null : block.id, offset: 0);
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, this.color, required this.onTap, this.tooltip});

  final String label;
  final Color? color;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final chip = Hover(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: kHoverFade,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: hovered ? const Color(0x0DFFFFFF) : null,
          border: Border.all(color: AppColors.cardBorder),
          borderRadius: BorderRadius.circular(AppRadii.row),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null) ...[Dot(color!), const SizedBox(width: 6)],
            Text(
              label,
              style: AppText.mono(11, weight: FontWeight.w500, color: AppColors.bodyText),
            ),
          ],
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

class _LinkBlock extends StatelessWidget {
  const _LinkBlock({required this.block, required this.onEdit, required this.onRemove});

  final NoteBlock block;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final shown = block.url.replaceFirst(RegExp(r'^https?://(www\.)?'), '');
    return Hover(
      onTap: () => launchUrl(Uri.parse(block.url)),
      builder: (context, hovered) => AnimatedContainer(
        duration: kHoverFade,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hovered ? const Color(0xFF424242) : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Row(
          children: [
            Text('↗', style: AppText.sans(13, color: AppColors.mutedText)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.title,
                    style: AppText.sans(13, weight: FontWeight.w500, color: AppColors.accent),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(shown, style: AppText.mono(11), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (hovered) ...[
              Hover(
                onTap: onEdit,
                builder: (context, h) => FadeText('edit', style: AppText.mono(11, color: h ? AppColors.bodyText : AppColors.mutedText)),
              ),
              const SizedBox(width: 12),
              Hover(
                onTap: onRemove,
                builder: (context, h) => FadeText('remove', style: AppText.mono(11, color: h ? AppColors.danger : AppColors.mutedText)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
