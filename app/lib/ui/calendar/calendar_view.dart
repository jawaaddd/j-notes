import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../state/data.dart';
import '../../state/ui.dart';
import '../../theme/tokens.dart';
import '../../util/dates.dart';
import '../board/board_view.dart' show newCard;
import '../widgets.dart';

/// Which month or week the Calendar shows. Shared with the status bar.
final calendarProvider = NotifierProvider<CalendarNotifier, CalendarState>(CalendarNotifier.new);

class CalendarState {
  const CalendarState(this.anchor, this.week);

  /// Any day inside the shown month (or week).
  final DateTime anchor;
  final bool week;
}

class CalendarNotifier extends Notifier<CalendarState> {
  @override
  CalendarState build() => CalendarState(dateOnly(DateTime.now()), false);

  void step(int dir) {
    final a = state.anchor;
    state = CalendarState(state.week ? a.add(Duration(days: 7 * dir)) : DateTime(a.year, a.month + dir, 1), state.week);
  }

  void today() => state = CalendarState(dateOnly(DateTime.now()), state.week);
  void setWeek(bool week) => state = CalendarState(state.anchor, week);
}

/// Cards due in [month] (local), and how many of those are overdue.
(int due, int overdue) monthCounts(BoardDetail detail, List<CardSummary> cards, DateTime month, DateTime now) {
  final inMonth = cards.where((c) => c.dueAt != null && c.dueAt!.year == month.year && c.dueAt!.month == month.month);
  final overdue = inMonth.where((c) => dueState(c, detail.list(c.listId), now) == DueState.overdue).length;
  return (inMonth.length, overdue);
}

String calendarStatus(BoardDetail? detail, List<CardSummary>? cards, DateTime month, DateTime now) {
  if (detail == null || cards == null) return '';
  final (due, overdue) = monthCounts(detail, cards, month, now);
  return '$due due in ${DateFormat.MMMM().format(month)} · $overdue overdue';
}

class CalendarView extends ConsumerWidget {
  const CalendarView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cal = ref.watch(calendarProvider);
    final detail = ref.watch(currentBoardProvider);
    final now = ref.watch(nowProvider);
    if (detail == null) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    final cards = ref.watch(cardsProvider(detail.board.id)).value ?? const <CardSummary>[];
    final (due, overdue) = monthCounts(detail, cards, cal.anchor, now);
    final notifier = ref.read(calendarProvider.notifier);

    // Grid days: whole weeks (Sunday first) covering the month, or one week.
    final List<DateTime> days;
    if (cal.week) {
      final start = cal.anchor.subtract(Duration(days: cal.anchor.weekday % 7));
      days = [for (var i = 0; i < 7; i++) DateTime(start.year, start.month, start.day + i)];
    } else {
      final first = DateTime(cal.anchor.year, cal.anchor.month, 1);
      final start = first.subtract(Duration(days: first.weekday % 7));
      final last = DateTime(cal.anchor.year, cal.anchor.month + 1, 0);
      final weeks = ((first.weekday % 7) + last.day + 6) ~/ 7;
      days = [for (var i = 0; i < weeks * 7; i++) DateTime(start.year, start.month, start.day + i)];
    }
    final byDay = <DateTime, List<CardSummary>>{};
    for (final c in cards) {
      if (c.dueAt != null) (byDay[dateOnly(c.dueAt!)] ??= []).add(c);
    }
    for (final l in byDay.values) {
      l.sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    }

    final title = cal.week ? 'Week of ${DateFormat('MMM d').format(days.first)}' : DateFormat('MMMM y').format(cal.anchor);

    return Padding(
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
                    Text(title, style: AppText.pageTitle),
                    const SizedBox(height: 4),
                    Text('${detail.board.name} · $due due this month${overdue > 0 ? ' · $overdue overdue' : ''}', style: AppText.subtitle),
                  ],
                ),
              ),
              _Segment(
                children: [
                  _SegButton('‹', onTap: () => notifier.step(-1)),
                  _SegButton('Today', onTap: notifier.today, wide: true),
                  _SegButton('›', onTap: () => notifier.step(1)),
                ],
              ),
              const SizedBox(width: 12),
              _Segment(
                children: [
                  _SegButton('Month', selected: !cal.week, onTap: () => notifier.setWeek(false)),
                  _SegButton('Week', selected: cal.week, onTap: () => notifier.setWeek(true)),
                ],
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Ctrl N',
                child: AppButton(label: '+ New Card', kind: ButtonKind.primary, onTap: () => newCard(context, ref, detail)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              for (final d in ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10, bottom: 8),
                    child: Text(d, style: AppText.mono(10, weight: FontWeight.w500)),
                  ),
                ),
            ],
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.cardBorder),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var w = 0; w < days.length ~/ 7; w++)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var d = 0; d < 7; d++)
                            Expanded(
                              child: _DayCell(
                                day: days[w * 7 + d],
                                inMonth: cal.week || days[w * 7 + d].month == cal.anchor.month,
                                today: dateOnly(now) == days[w * 7 + d],
                                cards: byDay[days[w * 7 + d]] ?? const [],
                                detail: detail,
                                now: now,
                                lastCol: d == 6,
                                lastRow: w == days.length ~/ 7 - 1,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends ConsumerWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.today,
    required this.cards,
    required this.detail,
    required this.now,
    required this.lastCol,
    required this.lastRow,
  });

  final DateTime day;
  final bool inMonth;
  final bool today;
  final List<CardSummary> cards;
  final BoardDetail detail;
  final DateTime now;
  final bool lastCol;
  final bool lastRow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: lastCol ? BorderSide.none : const BorderSide(color: AppColors.cardBorder),
          bottom: lastRow ? BorderSide.none : const BorderSide(color: AppColors.cardBorder),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: LayoutBuilder(
        builder: (context, box) {
          const pillH = 22.0;
          final room = ((box.maxHeight - 26) / pillH).floor().clamp(0, 99);
          final fits = cards.length <= room ? cards.length : (room - 1).clamp(0, 99);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: inMonth ? 1 : 0.45,
                child: today
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
                        child: Text(
                          '${day.day}',
                          style: AppText.sans(12, weight: FontWeight.w600, color: AppColors.background),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Text('${day.day}', style: AppText.sans(12, color: AppColors.bodyText)),
                      ),
              ),
              const SizedBox(height: 6),
              for (final c in cards.take(fits)) _Pill(card: c, detail: detail, now: now),
              if (fits < cards.length)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Text('+${cards.length - fits} more', style: AppText.mono(10)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A card on the calendar: special tag color dot and a one-line title.
class _Pill extends ConsumerWidget {
  const _Pill({required this.card, required this.detail, required this.now});

  final CardSummary card;
  final BoardDetail detail;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = dueState(card, detail.list(card.listId), now);
    final special = detail.tag(card.specialTagId);
    final color = switch (state) {
      DueState.overdue => AppColors.danger,
      DueState.dueSoon => AppColors.accent,
      DueState.done => AppColors.mutedText,
      DueState.normal => AppColors.primaryText,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Opacity(
        opacity: state == DueState.done ? 0.6 : 1,
        child: Hover(
          onTap: () => ref.read(openCardProvider.notifier).open(card.id),
          builder: (context, hovered) => AnimatedContainer(
            duration: kHoverFade,
            curve: Curves.easeOut,
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: hovered ? const Color(0xFF444444) : AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppRadii.chip),
              border: state == DueState.overdue ? Border.all(color: AppColors.danger) : null,
            ),
            child: Row(
              children: [
                Dot(special == null ? AppColors.mutedText : AppColors.tag(special.color), size: 6),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    card.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.sans(11, color: color).copyWith(
                      decoration: state == DueState.done ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.mutedText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.cardBorder),
      borderRadius: BorderRadius.circular(AppRadii.control),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}

class _SegButton extends StatelessWidget {
  const _SegButton(this.label, {required this.onTap, this.selected = false, this.wide = false});

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool wide;

  @override
  Widget build(BuildContext context) => Hover(
    onTap: onTap,
    builder: (context, hovered) => AnimatedContainer(
      duration: kHoverFade,
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(horizontal: wide ? 16 : 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? AppColors.cardBackground : (hovered ? const Color(0x0DFFFFFF) : null),
        borderRadius: BorderRadius.circular(AppRadii.row),
      ),
      child: Text(
        label,
        style: AppText.sans(
          12,
          weight: selected || wide ? FontWeight.w500 : FontWeight.w400,
          color: selected || wide ? AppColors.primaryText : AppColors.mutedText,
        ),
      ),
    ),
  );
}
