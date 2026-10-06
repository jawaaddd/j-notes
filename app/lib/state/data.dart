import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/client.dart';
import '../api/models.dart';
import 'session.dart';

/// The signed-in API client. Only read below the ready phase.
final apiProvider = Provider<ApiClient>((ref) => ref.watch(sessionProvider.select((s) => s.api))!);

/// "Now", ticking every 30 seconds so relative times ("12m ago") stay fresh.
final nowProvider = NotifierProvider<NowNotifier, DateTime>(NowNotifier.new);

class NowNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final timer = Timer.periodic(const Duration(seconds: 30), (_) => state = DateTime.now());
    ref.onDispose(timer.cancel);
    return DateTime.now();
  }
}

final boardsProvider = FutureProvider<List<Board>>((ref) => ref.watch(apiProvider).boards());

/// The board picked in the switcher, remembered across launches. Falls back to
/// the first board when unset or deleted.
final selectedBoardIdProvider = NotifierProvider<SelectedBoardNotifier, int?>(SelectedBoardNotifier.new);

class SelectedBoardNotifier extends Notifier<int?> {
  @override
  int? build() {
    SharedPreferences.getInstance().then((p) {
      final saved = p.getInt('selectedBoardId');
      if (saved != null && state == null) state = saved;
    });
    return null;
  }

  void select(int id) {
    state = id;
    SharedPreferences.getInstance().then((p) => p.setInt('selectedBoardId', id));
  }
}

final currentBoardIdProvider = Provider<int?>((ref) {
  final boards = ref.watch(boardsProvider).value;
  if (boards == null || boards.isEmpty) return null;
  final selected = ref.watch(selectedBoardIdProvider);
  return boards.any((b) => b.id == selected) ? selected : boards.first.id;
});

final boardDetailProvider = FutureProvider.family<BoardDetail, int>((ref, id) => ref.watch(apiProvider).board(id));

/// The current board's lists and tags, or null while loading.
final currentBoardProvider = Provider<BoardDetail?>((ref) {
  final id = ref.watch(currentBoardIdProvider);
  return id == null ? null : ref.watch(boardDetailProvider(id)).value;
});

/// Every unarchived card on a board. The Board view filters and sorts on the
/// client (spec: filters dim, they don't refetch).
final cardsProvider = AsyncNotifierProvider.family<CardsNotifier, List<CardSummary>, int>(CardsNotifier.new);

class CardsNotifier extends AsyncNotifier<List<CardSummary>> {
  CardsNotifier(this.boardId);

  final int boardId;

  @override
  Future<List<CardSummary>> build() => ref.watch(apiProvider).cards(boardId);

  /// Moves a card into [to] at [index] among that list's cards (the end when
  /// null), right away, then confirms with the server. The board reloads
  /// from the server afterwards either way.
  Future<void> move(CardSummary card, BoardList to, {int? index}) async {
    final cards = state.value;
    if (cards == null) return;
    if (card.listId == to.id && index == null) return;

    final target = [
      for (final c in cards)
        if (c.listId == to.id && c.id != card.id) c,
    ]..sort((a, b) => a.position.compareTo(b.position));
    final at = index == null ? target.length : index.clamp(0, target.length);
    target.insert(at, card.movedTo(to));
    final placed = {for (final (i, c) in target.indexed) c.id: c.withPosition(i)};
    state = AsyncData([for (final c in cards) placed[c.id] ?? c]);

    try {
      await ref.read(apiProvider).updateCard(card.id, {if (card.listId != to.id) 'listId': to.id, 'position': at});
    } finally {
      refreshBoard(ref, boardId);
    }
  }
}

final archivedCardsProvider = FutureProvider.family<List<CardSummary>, int>((ref, boardId) async {
  final all = await ref.watch(apiProvider).cards(boardId, archived: true, sort: 'title');
  return [
    for (final c in all)
      if (c.archivedAt != null) c,
  ];
});

final inboxProvider = FutureProvider<InboxList>((ref) => ref.watch(apiProvider).inbox());

final sourcesProvider = FutureProvider<List<Source>>((ref) => ref.watch(apiProvider).sources());

final cardDetailProvider = FutureProvider.family<CardDetail, int>((ref, id) => ref.watch(apiProvider).card(id));

/// Reloads everything derived from a board after a change: counts, lists,
/// tags, and cards.
void refreshBoard(Ref ref, int boardId) {
  ref.invalidate(boardsProvider);
  ref.invalidate(boardDetailProvider(boardId));
  ref.invalidate(cardsProvider(boardId));
  ref.invalidate(archivedCardsProvider(boardId));
}

void refreshBoardFromWidget(WidgetRef ref, int boardId) {
  ref.invalidate(boardsProvider);
  ref.invalidate(boardDetailProvider(boardId));
  ref.invalidate(cardsProvider(boardId));
  ref.invalidate(archivedCardsProvider(boardId));
}

void refreshAll(WidgetRef ref) {
  ref.invalidate(boardsProvider);
  ref.invalidate(boardDetailProvider);
  ref.invalidate(cardsProvider);
  ref.invalidate(archivedCardsProvider);
  ref.invalidate(inboxProvider);
  ref.invalidate(sourcesProvider);
  ref.invalidate(cardDetailProvider);
}
