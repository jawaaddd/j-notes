// JSON shapes from backend-api-spec.md. Timestamps arrive in UTC and are
// converted to local time here, so the UI never deals with UTC.

DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
int? _int(Object? v) => (v as num?)?.toInt();
List<int> _ints(Object? v) => [for (final x in (v as List? ?? const [])) (x as num).toInt()];

class Board {
  Board.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      name = j['name'] as String,
      itemNoun = j['itemNoun'] as String,
      specialTagLabel = j['specialTagLabel'] as String,
      position = j['position'] as int,
      openCount = j['openCount'] as int,
      overdueCount = j['overdueCount'] as int;

  final int id;
  final String name;
  final String itemNoun;
  final String specialTagLabel;
  final int position;
  final int openCount;
  final int overdueCount;
}

enum ListKind { open, done }

class BoardList {
  BoardList.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      boardId = j['boardId'] as int,
      name = j['name'] as String,
      kind = j['kind'] == 'done' ? ListKind.done : ListKind.open,
      position = j['position'] as int,
      cardCount = j['cardCount'] as int;

  final int id;
  final int boardId;
  final String name;
  final ListKind kind;
  final int position;
  final int cardCount;

  bool get isDone => kind == ListKind.done;
}

class Tag {
  Tag.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      boardId = j['boardId'] as int,
      name = j['name'] as String,
      color = j['color'] as String,
      isSpecial = j['isSpecial'] as bool,
      systemKey = j['systemKey'] as String?,
      position = j['position'] as int,
      openCardCount = j['openCardCount'] as int;

  final int id;
  final int boardId;
  final String name;
  final String color;
  final bool isSpecial;
  final String? systemKey;
  final int position;
  final int openCardCount;

  bool get isUrgent => systemKey == 'urgent';
}

class BoardDetail {
  BoardDetail.fromJson(Map<String, dynamic> j)
    : board = Board.fromJson(j['board'] as Map<String, dynamic>),
      lists = [for (final l in j['lists'] as List) BoardList.fromJson(l as Map<String, dynamic>)],
      tags = [for (final t in j['tags'] as List) Tag.fromJson(t as Map<String, dynamic>)];

  final Board board;
  final List<BoardList> lists;
  final List<Tag> tags;

  List<Tag> get specialTags => [
    for (final t in tags)
      if (t.isSpecial) t,
  ];
  List<Tag> get regularTags => [
    for (final t in tags)
      if (!t.isSpecial) t,
  ];
  Tag? tag(int? id) => id == null ? null : tags.where((t) => t.id == id).firstOrNull;
  BoardList? list(int id) => lists.where((l) => l.id == id).firstOrNull;
  Tag? get urgentTag => tags.where((t) => t.isUrgent).firstOrNull;
}

class CardSummary {
  CardSummary.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      boardId = j['boardId'] as int,
      listId = j['listId'] as int,
      position = j['position'] as int? ?? 0,
      title = j['title'] as String,
      dueAt = _time(j['dueAt']),
      dueAllDay = j['dueAllDay'] as bool,
      specialTagId = _int(j['specialTagId']),
      tagIds = _ints(j['tagIds']),
      completedAt = _time(j['completedAt']),
      archivedAt = _time(j['archivedAt']),
      createdAt = _time(j['createdAt'])!,
      updatedAt = _time(j['updatedAt'])!;

  CardSummary._copy(CardSummary c, {int? listId, int? position, DateTime? completedAt, bool clearCompleted = false})
    : id = c.id,
      boardId = c.boardId,
      listId = listId ?? c.listId,
      position = position ?? c.position,
      title = c.title,
      dueAt = c.dueAt,
      dueAllDay = c.dueAllDay,
      specialTagId = c.specialTagId,
      tagIds = c.tagIds,
      completedAt = clearCompleted ? null : (completedAt ?? c.completedAt),
      archivedAt = c.archivedAt,
      createdAt = c.createdAt,
      updatedAt = c.updatedAt;

  /// The card as it looks right after a drag, before the server confirms.
  CardSummary movedTo(BoardList list, {int? position}) => list.isDone
      ? CardSummary._copy(this, listId: list.id, position: position, completedAt: completedAt ?? DateTime.now())
      : CardSummary._copy(this, listId: list.id, position: position, clearCompleted: true);

  CardSummary withPosition(int position) => CardSummary._copy(this, position: position);

  final int id;
  final int boardId;
  final int listId;

  /// Order within the list for the Custom sort.
  final int position;
  final String title;
  final DateTime? dueAt;
  final bool dueAllDay;
  final int? specialTagId;
  final List<int> tagIds;
  final DateTime? completedAt;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

enum BlockType { text, todo, link }

class NoteBlock {
  NoteBlock({required this.id, required this.type, this.text = '', this.done = false, this.title = '', this.url = ''});

  factory NoteBlock.fromJson(Map<String, dynamic> j) => NoteBlock(
    id: j['id'] as String,
    type: BlockType.values.byName(j['type'] as String),
    text: j['text'] as String? ?? '',
    done: j['done'] as bool? ?? false,
    title: j['title'] as String? ?? '',
    url: j['url'] as String? ?? '',
  );

  final String id;
  final BlockType type;
  final String text;
  final bool done;
  final String title;
  final String url;

  NoteBlock copyWith({String? text, bool? done, String? title, String? url, BlockType? type}) => NoteBlock(
    id: id,
    type: type ?? this.type,
    text: text ?? this.text,
    done: done ?? this.done,
    title: title ?? this.title,
    url: url ?? this.url,
  );

  Map<String, dynamic> toJson() => switch (type) {
    BlockType.text => {'id': id, 'type': 'text', 'text': text},
    BlockType.todo => {'id': id, 'type': 'todo', 'text': text, 'done': done, if (title.isNotEmpty) 'title': title},
    BlockType.link => {'id': id, 'type': 'link', 'title': title, 'url': url},
  };
}

class CardDetail {
  CardDetail.fromJson(Map<String, dynamic> j)
    : summary = CardSummary.fromJson(j),
      sourceName = (j['source'] as Map<String, dynamic>)['name'] as String,
      sourceUrl = (j['source'] as Map<String, dynamic>)['url'] as String?,
      externalId = j['externalId'] as String?,
      lastSyncedAt = _time(j['lastSyncedAt']),
      notes = [for (final b in j['notes'] as List) NoteBlock.fromJson(b as Map<String, dynamic>)];

  final CardSummary summary;
  final String sourceName;
  final String? sourceUrl;
  final String? externalId;
  final DateTime? lastSyncedAt;
  final List<NoteBlock> notes;
}

enum InboxType { voice, change, duplicate }

class Parsed {
  Parsed.fromJson(Map<String, dynamic> j)
    : title = j['title'] as String,
      specialTagId = _int(j['specialTagId']),
      dueAt = _time(j['dueAt']),
      dueAllDay = j['dueAllDay'] as bool? ?? false,
      uncertain = {for (final e in (j['uncertain'] as Map? ?? const {}).entries) e.key as String: e.value as String};

  final String title;
  final int? specialTagId;
  final DateTime? dueAt;
  final bool dueAllDay;
  final Map<String, String> uncertain;
}

class Change {
  Change.fromJson(Map<String, dynamic> j)
    : field = j['field'] as String,
      oldValue = j['oldValue'] as String?,
      newValue = j['newValue'] as String?;

  final String field;
  final String? oldValue;
  final String? newValue;
}

class InboxItem {
  InboxItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      type = InboxType.values.byName(j['type'] as String),
      source = j['source'] as String,
      boardId = _int(j['boardId']),
      rawText = j['rawText'] as String,
      parsed = Parsed.fromJson(j['parsed'] as Map<String, dynamic>),
      cardId = _int(j['cardId']),
      change = j['change'] == null ? null : Change.fromJson(j['change'] as Map<String, dynamic>),
      receivedAt = _time(j['receivedAt'])!;

  final int id;
  final InboxType type;
  final String source;
  final int? boardId;
  final String rawText;
  final Parsed parsed;
  final int? cardId;
  final Change? change;
  final DateTime receivedAt;
}

class InboxCounts {
  InboxCounts.fromJson(Map<String, dynamic> j)
    : all = j['all'] as int,
      voice = j['voice'] as int,
      change = j['change'] as int,
      duplicate = j['duplicate'] as int;

  final int all, voice, change, duplicate;
}

class InboxList {
  InboxList.fromJson(Map<String, dynamic> j)
    : items = [for (final i in j['items'] as List) InboxItem.fromJson(i as Map<String, dynamic>)],
      counts = InboxCounts.fromJson(j['counts'] as Map<String, dynamic>);

  final List<InboxItem> items;
  final InboxCounts counts;
}

class Source {
  Source.fromJson(Map<String, dynamic> j)
    : name = j['name'] as String,
      kind = j['kind'] as String,
      health = j['health'] as String,
      statusMessage = j['statusMessage'] as String?,
      lastSyncAt = _time(j['lastSyncAt']);

  final String name;
  final String kind;
  final String health;
  final String? statusMessage;
  final DateTime? lastSyncAt;

  bool get healthy => health == 'ok';
}

class ApiToken {
  ApiToken.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      kind = j['kind'] as String,
      name = j['name'] as String,
      createdAt = _time(j['createdAt'])!,
      lastUsedAt = _time(j['lastUsedAt']),
      current = j['current'] as bool? ?? false;

  final int id;
  final String kind;
  final String name;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final bool current;
}

class AuthStatus {
  AuthStatus.fromJson(Map<String, dynamic> j) : setupRequired = j['setupRequired'] as bool, passwordFromEnv = j['passwordFromEnv'] as bool;

  final bool setupRequired;
  final bool passwordFromEnv;
}
