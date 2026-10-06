import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import 'data.dart';

enum AppView { board, inbox, calendar, archive, settings, manage }

final viewProvider = NotifierProvider<ViewNotifier, AppView>(ViewNotifier.new);

class ViewNotifier extends Notifier<AppView> {
  @override
  AppView build() => AppView.board;

  void show(AppView v) => state = v;
}

enum CardSort {
  /// Hand-arranged by dragging; the default.
  custom('Custom'),
  due('Due date'),
  created('Date added'),
  title('Title');

  const CardSort(this.label);
  final String label;
}

/// The Board view's filters. Rebuilt (cleared) whenever the board changes.
@immutable
class BoardFilter {
  const BoardFilter({this.specialTagId, this.tagIds = const {}, this.matchAll = false, this.search = '', this.sort = CardSort.custom});

  final int? specialTagId;
  final Set<int> tagIds;
  final bool matchAll;
  final String search;
  final CardSort sort;

  bool get isActive => specialTagId != null || tagIds.isNotEmpty || search.trim().isNotEmpty;

  bool matches(CardSummary c) {
    if (specialTagId != null && c.specialTagId != specialTagId) return false;
    if (tagIds.isNotEmpty) {
      final hits = tagIds.where(c.tagIds.contains).length;
      if (matchAll ? hits != tagIds.length : hits == 0) return false;
    }
    final q = search.trim().toLowerCase();
    if (q.isNotEmpty && !c.title.toLowerCase().contains(q)) return false;
    return true;
  }

  BoardFilter copyWith({int? specialTagId, bool clearSpecial = false, Set<int>? tagIds, bool? matchAll, String? search, CardSort? sort}) =>
      BoardFilter(
        specialTagId: clearSpecial ? null : (specialTagId ?? this.specialTagId),
        tagIds: tagIds ?? this.tagIds,
        matchAll: matchAll ?? this.matchAll,
        search: search ?? this.search,
        sort: sort ?? this.sort,
      );
}

final boardFilterProvider = NotifierProvider<BoardFilterNotifier, BoardFilter>(BoardFilterNotifier.new);

class BoardFilterNotifier extends Notifier<BoardFilter> {
  @override
  BoardFilter build() {
    ref.watch(currentBoardIdProvider);
    return const BoardFilter();
  }

  /// Single-select; picking the selected tag again clears it ("All").
  void special(int? id) =>
      state = id == null || id == state.specialTagId ? state.copyWith(clearSpecial: true) : state.copyWith(specialTagId: id);

  void toggleTag(int id) {
    final next = {...state.tagIds};
    next.contains(id) ? next.remove(id) : next.add(id);
    state = state.copyWith(tagIds: next);
  }

  void clearTags() => state = state.copyWith(tagIds: {});
  void setMatchAll(bool v) => state = state.copyWith(matchAll: v);
  void search(String q) => state = state.copyWith(search: q);
  void sort(CardSort s) => state = state.copyWith(sort: s);
}

/// Sorts cards within a list per the Sort setting; no due date sorts last.
List<CardSummary> sortCards(Iterable<CardSummary> cards, CardSort sort) {
  final out = cards.toList();
  int byDue(CardSummary a, CardSummary b) {
    if (a.dueAt == null || b.dueAt == null) {
      if (a.dueAt == b.dueAt) return a.id.compareTo(b.id);
      return a.dueAt == null ? 1 : -1;
    }
    final c = a.dueAt!.compareTo(b.dueAt!);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  out.sort(switch (sort) {
    CardSort.custom => (a, b) => a.position != b.position ? a.position.compareTo(b.position) : a.id.compareTo(b.id),
    CardSort.due => byDue,
    CardSort.created => (a, b) => a.createdAt.compareTo(b.createdAt),
    CardSort.title => (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  });
  return out;
}

/// The card open in the Card Modal, if any.
final openCardProvider = NotifierProvider<OpenCardNotifier, int?>(OpenCardNotifier.new);

class OpenCardNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void open(int id) => state = id;
  void close() => state = null;
}
