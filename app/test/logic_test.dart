import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/api/models.dart';
import 'package:notes_app/state/ui.dart';
import 'package:notes_app/util/dates.dart';

final now = DateTime(2026, 10, 6, 15); // Tue, Oct 6, 3 PM local

BoardList list(String kind) => BoardList.fromJson({'id': 1, 'boardId': 1, 'name': kind, 'kind': kind, 'position': 0, 'cardCount': 0});

CardSummary card({int id = 1, DateTime? due, List<int> tags = const [], int? special, String title = 'Card', DateTime? completed}) =>
    CardSummary.fromJson({
      'id': id,
      'boardId': 1,
      'listId': 1,
      'title': title,
      'dueAt': due?.toUtc().toIso8601String(),
      'dueAllDay': false,
      'specialTagId': special,
      'tagIds': tags,
      'completedAt': completed?.toUtc().toIso8601String(),
      'archivedAt': null,
      'createdAt': DateTime(2026, 9, id).toUtc().toIso8601String(),
      'updatedAt': DateTime(2026, 9, id).toUtc().toIso8601String(),
    });

void main() {
  final open = list('open');
  final done = list('done');

  test('due line and state follow the spec', () {
    expect(dueLine(card(), open, now), 'No due date');
    expect(dueLine(card(due: DateTime(2026, 10, 5, 23, 59)), open, now), 'Overdue · 1 day');
    expect(dueLine(card(due: DateTime(2026, 10, 3, 23, 59)), open, now), 'Overdue · 3 days');
    expect(dueLine(card(due: DateTime(2026, 10, 6, 9)), open, now), 'Overdue · today');
    expect(dueLine(card(due: DateTime(2026, 10, 6, 23, 59)), open, now), 'Due today');
    expect(dueLine(card(due: DateTime(2026, 10, 7, 23, 59)), open, now), 'Due tomorrow');
    expect(dueLine(card(due: DateTime(2026, 10, 8, 23, 59)), open, now), 'Due Thu, Oct 8');
    expect(dueLine(card(due: DateTime(2026, 10, 5), completed: DateTime(2026, 10, 5, 12)), done, now), 'Done Oct 5');

    expect(dueState(card(due: DateTime(2026, 10, 5, 23, 59)), open, now), DueState.overdue);
    expect(dueState(card(due: DateTime(2026, 10, 7, 23, 59)), open, now), DueState.dueSoon);
    expect(dueState(card(due: DateTime(2026, 10, 8, 23, 59)), open, now), DueState.normal);
    expect(dueState(card(due: DateTime(2026, 10, 5)), done, now), DueState.done, reason: 'done wins over overdue');
  });

  test('daysBetween counts calendar days across DST', () {
    expect(daysBetween(DateTime(2026, 11, 1, 0, 30), DateTime(2026, 11, 2, 23)), 1);
    expect(daysBetween(DateTime(2026, 3, 7, 23), DateTime(2026, 3, 9, 1)), 2);
  });

  test('filters combine with AND; tags match any or all', () {
    final a = card(id: 1, tags: [10, 11], special: 5, title: 'Lab 3: A* path planner');
    final b = card(id: 2, tags: [10], special: 6, title: 'HW 6');
    expect(const BoardFilter().matches(a), isTrue);
    expect(const BoardFilter(specialTagId: 5).matches(b), isFalse);
    expect(const BoardFilter(tagIds: {10, 11}).matches(b), isTrue, reason: 'match any');
    expect(const BoardFilter(tagIds: {10, 11}, matchAll: true).matches(b), isFalse);
    expect(const BoardFilter(tagIds: {10}, search: 'path').matches(a), isTrue);
    expect(const BoardFilter(tagIds: {10}, search: 'path').matches(b), isFalse);
  });

  test('due sort puts cards without a date last', () {
    final sorted = sortCards([card(id: 1), card(id: 2, due: DateTime(2026, 10, 9)), card(id: 3, due: DateTime(2026, 10, 7))], CardSort.due);
    expect(sorted.map((c) => c.id), [3, 2, 1]);
  });

  test('a moved card picks up or drops completedAt', () {
    final c = card(due: DateTime(2026, 10, 9));
    expect(c.movedTo(done).completedAt, isNotNull);
    expect(c.movedTo(done).movedTo(open).completedAt, isNull);
  });

  test('custom sort follows position, the default sort', () {
    expect(const BoardFilter().sort, CardSort.custom);
    final sorted = sortCards([card(id: 1).withPosition(2), card(id: 2).withPosition(0), card(id: 3).withPosition(1)], CardSort.custom);
    expect(sorted.map((c) => c.id), [2, 3, 1]);
  });
}
