import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Shows [popover] anchored to [child] while [controller] is open. Closes on a
/// click outside both, or Esc.
class Popover extends StatefulWidget {
  const Popover({
    super.key,
    required this.controller,
    required this.child,
    required this.popover,
    this.targetAnchor = Alignment.bottomLeft,
    this.followerAnchor = Alignment.topLeft,
    this.offset = const Offset(0, 6),
  });

  final OverlayPortalController controller;
  final Widget child;
  final WidgetBuilder popover;
  final Alignment targetAnchor;
  final Alignment followerAnchor;
  final Offset offset;

  @override
  State<Popover> createState() => _PopoverState();
}

class _PopoverState extends State<Popover> {
  final _link = LayerLink();
  final _group = UniqueKey();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: widget.controller,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: widget.targetAnchor,
          followerAnchor: widget.followerAnchor,
          offset: widget.offset,
          child: Align(
            alignment: widget.followerAnchor,
            child: TapRegion(
              groupId: _group,
              onTapOutside: (_) => widget.controller.hide(),
              child: CallbackShortcuts(
                bindings: {const SingleActivator(LogicalKeyboardKey.escape): widget.controller.hide},
                child: Focus(autofocus: true, child: widget.popover(context)),
              ),
            ),
          ),
        ),
        child: TapRegion(groupId: _group, child: widget.child),
      ),
    );
  }
}

/// The popover surface: Card Background, border, 6px radius, drop shadow.
class PopoverSurface extends StatelessWidget {
  const PopoverSurface({super.key, required this.child, this.width});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.row),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 32, offset: Offset(0, 12))],
      ),
      child: child,
    ),
  );
}
