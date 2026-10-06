import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../theme/tokens.dart';
import '../widgets.dart';

/// The app's own title bar: "notes-app — {view}" on the left, window controls
/// on the right. Dragging it moves the window; double-click maximizes.
class TitleBar extends StatelessWidget {
  const TitleBar({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: DragToMoveArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text('notes-app — $title', style: AppText.mono(12), overflow: TextOverflow.ellipsis),
              ),
              _Control('—', windowManager.minimize),
              const SizedBox(width: 18),
              _Control('□', () async => await windowManager.isMaximized() ? windowManager.unmaximize() : windowManager.maximize()),
              const SizedBox(width: 18),
              _Control('✕', windowManager.close),
            ],
          ),
        ),
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control(this.glyph, this.onTap);

  final String glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Hover(
    onTap: onTap,
    builder: (context, hovered) => FadeText(glyph, style: AppText.mono(12, color: hovered ? AppColors.bodyText : AppColors.mutedText)),
  );
}

/// The bottom status bar: a summary on the left, API host and last sync on the right.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.left, required this.right});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.cardBorder)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(left, style: AppText.mono(11), overflow: TextOverflow.ellipsis),
        ),
        Text(right, style: AppText.mono(11)),
      ],
    ),
  );
}
