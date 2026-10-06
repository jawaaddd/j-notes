import 'package:intl/intl.dart';

import '../api/models.dart';

/// Card state derived from dueAt, the list's kind, and today (ui-frontend-spec,
/// Card states). Everything here works in local time.
enum DueState { normal, dueSoon, overdue, done }

DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// Calendar days from `from` to `to`; rounding absorbs 23- and 25-hour DST days.
int daysBetween(DateTime from, DateTime to) => (dateOnly(to).difference(dateOnly(from)).inHours / 24).round();

DueState dueState(CardSummary c, BoardList? list, DateTime now) {
  if (list?.isDone ?? false) return DueState.done;
  final due = c.dueAt;
  if (due == null) return DueState.normal;
  if (due.isBefore(now)) return DueState.overdue;
  final days = daysBetween(now, due);
  return days <= 1 ? DueState.dueSoon : DueState.normal;
}

final _weekdayDate = DateFormat('EEE, MMM d');
final _monthDay = DateFormat('MMM d');
final _time = DateFormat('h:mm a');

/// The card's due line: "Due Thu, Oct 8", "Due tomorrow", "Overdue · 1 day",
/// "No due date", or "Done Oct 5".
String dueLine(CardSummary c, BoardList? list, DateTime now) {
  if (list?.isDone ?? false) {
    final at = c.completedAt ?? c.updatedAt;
    return 'Done ${_monthDay.format(at)}';
  }
  final due = c.dueAt;
  if (due == null) return 'No due date';
  if (due.isBefore(now)) {
    final days = daysBetween(due, now);
    return days == 0 ? 'Overdue · today' : 'Overdue · $days ${days == 1 ? 'day' : 'days'}';
  }
  return switch (daysBetween(now, due)) {
    0 => 'Due today',
    1 => 'Due tomorrow',
    _ => 'Due ${_weekdayDate.format(due)}',
  };
}

/// "Thu, Oct 8 · 11:59 PM", or just the date for all-day cards.
String dueFull(DateTime due, bool allDay) => allDay ? _weekdayDate.format(due) : '${_weekdayDate.format(due)} · ${_time.format(due)}';

String shortDate(DateTime t) => _weekdayDate.format(t);
String monthDay(DateTime t) => _monthDay.format(t);

/// "in 2 days", "tomorrow", "today", "3 days ago".
String relativeDay(DateTime t, DateTime now) {
  final d = daysBetween(now, t);
  return switch (d) {
    0 => 'today',
    1 => 'tomorrow',
    -1 => 'yesterday',
    > 1 => 'in $d days',
    _ => '${-d} days ago',
  };
}

/// "just now", "12m ago", "2h ago", "3d ago".
String ago(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
