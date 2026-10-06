import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/tokens.dart';
import '../../util/dates.dart';
import '../widgets.dart';

/// The Card component (Figma: Card): special tag chip, regular tag dots,
/// title, and due line. Source is never shown on the card.
class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.card,
    required this.list,
    required this.detail,
    required this.now,
    this.dimmed = false,
    this.onTap,
  });

  final CardSummary card;
  final BoardList? list;
  final BoardDetail detail;
  final DateTime now;
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = dueState(card, list, now);
    final special = detail.tag(card.specialTagId);
    final dots = [for (final id in card.tagIds) ?detail.tag(id)].take(4).toList();
    final dueColor = switch (state) {
      DueState.overdue => AppColors.danger,
      DueState.dueSoon => AppColors.accent,
      _ => AppColors.mutedText,
    };

    return AnimatedOpacity(
      duration: kHoverFade, // filters fade cards in and out rather than snapping
      opacity: dimmed ? 0.3 : (state == DueState.done ? 0.55 : 1),
      child: Hover(
        onTap: onTap,
        builder: (context, hovered) => AnimatedContainer(
          duration: kHoverFade,
          curve: Curves.easeOut,
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hovered ? const Color(0xFF424242) : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: state == DueState.overdue ? AppColors.danger : AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (special != null || dots.isNotEmpty) ...[
                Row(
                  children: [
                    if (special != null) MonoChip(special.name),
                    const Spacer(),
                    for (final (i, t) in dots.indexed) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Tooltip(message: t.name, child: Dot(AppColors.tag(t.color))),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Text(card.title, style: AppText.cardTitle),
              const SizedBox(height: 10),
              Text(dueLine(card, list, now), style: AppText.mono(12, color: dueColor)),
            ],
          ),
        ),
      ),
    );
  }
}
