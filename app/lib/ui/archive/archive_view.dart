import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/data.dart';
import '../../state/ui.dart';
import '../../theme/tokens.dart';
import '../../util/dates.dart';
import '../widgets.dart';

/// Archived cards on the current board. Not designed yet; a plain list with
/// Restore until it is.
class ArchiveView extends ConsumerWidget {
  const ArchiveView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(currentBoardProvider);
    if (detail == null) return const SizedBox.shrink();
    final archived = ref.watch(archivedCardsProvider(detail.board.id));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Archive', style: AppText.pageTitle),
          const SizedBox(height: 4),
          Text('${detail.board.name} · archived ${detail.board.itemNoun.toLowerCase()}', style: AppText.subtitle),
          const SizedBox(height: 24),
          Expanded(
            child: archived.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => EmptyState("Couldn't load the archive", detail: '$e'),
              data: (cards) => cards.isEmpty
                  ? const EmptyState('Nothing archived', detail: 'Archive a card from its Card Modal to tuck it away here.')
                  : ListView.separated(
                      itemCount: cards.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final c = cards[i];
                        final special = detail.tag(c.specialTagId);
                        return Hover(
                          onTap: () => ref.read(openCardProvider.notifier).open(c.id),
                          builder: (context, hovered) => AnimatedContainer(
                            duration: kHoverFade,
                            curve: Curves.easeOut,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: hovered ? const Color(0xFF424242) : AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(AppRadii.card),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: Row(
                              children: [
                                if (special != null) ...[MonoChip(special.name), const SizedBox(width: 12)],
                                Expanded(child: Text(c.title, style: AppText.cardTitle)),
                                Text('archived ${monthDay(c.archivedAt!)}', style: AppText.mono(11)),
                                const SizedBox(width: 16),
                                AppButton(
                                  label: 'Restore',
                                  small: true,
                                  onTap: () async {
                                    try {
                                      await ref.read(apiProvider).updateCard(c.id, {'archived': false});
                                      refreshBoardFromWidget(ref, detail.board.id);
                                    } catch (e) {
                                      if (context.mounted) showError(context, e);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
