import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/tokens.dart';

/// One of the line icons exported from Figma (`assets/icons/<name>.svg`).
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.size = 14, this.color = AppColors.mutedText});

  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset('assets/icons/$name.svg', width: size, height: size, colorFilter: ColorFilter.mode(color, BlendMode.srcIn));
}

/// How long hover colors take to fade in and out.
const kHoverFade = Duration(milliseconds: 140);

/// Text whose style (usually its color) fades when it changes, e.g. on hover.
class FadeText extends StatelessWidget {
  const FadeText(this.text, {super.key, required this.style, this.overflow});

  final String text;
  final TextStyle style;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => AnimatedDefaultTextStyle(
    duration: kHoverFade,
    curve: Curves.easeOut,
    style: style,
    child: Text(text, overflow: overflow),
  );
}

/// An icon whose color fades when it changes.
class FadeIcon extends StatelessWidget {
  const FadeIcon(this.icon, {super.key, required this.color, this.size = 16});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
    tween: ColorTween(end: color),
    duration: kHoverFade,
    builder: (context, c, _) => Icon(icon, size: size, color: c),
  );
}

/// Rebuilds with whether the pointer is over it.
class Hover extends StatefulWidget {
  const Hover({super.key, required this.builder, this.onTap, this.cursor = SystemMouseCursors.click});

  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final MouseCursor cursor;

  @override
  State<Hover> createState() => _HoverState();
}

class _HoverState extends State<Hover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap == null ? MouseCursor.defer : widget.cursor,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: widget.builder(context, _hovered)),
  );
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: kHoverFade,
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Fully rounded pill: filter chips, Urgent/Filter/Sort, Inbox type chips.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.selected = false,
    this.count,
    this.leading,
    this.onTap,
    this.highlight = false,
    this.badge,
  });

  final String label;
  final bool selected;
  final String? count;
  final Widget? leading;
  final VoidCallback? onTap;

  /// Accent outline and text, e.g. the Filter pill while tag filters are on.
  final bool highlight;

  /// A filled Accent count badge, e.g. the number of active tag filters.
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final textColor = highlight ? AppColors.accent : (selected ? AppColors.primaryText : AppColors.mutedText);
    return Hover(
      onTap: onTap,
      builder: (context, hovered) => AnimatedContainer(
        duration: kHoverFade,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.cardBackground : (hovered ? const Color(0x0DFFFFFF) : null),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: highlight ? AppColors.accent : (selected ? AppColors.cardBackground : AppColors.cardBorder)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Text(
              label,
              style: AppText.sans(12, weight: selected ? FontWeight.w500 : FontWeight.w400, color: textColor),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text(count!, style: AppText.mono(11, color: selected ? AppColors.primaryText : AppColors.mutedText)),
            ],
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 15),
                height: 15,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  '$badge',
                  style: AppText.mono(10, weight: FontWeight.w600, color: AppColors.background),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum ButtonKind { primary, outline, danger }

/// Rectangular button. [small] is the Inbox row size (radius 6, 10×6 padding).
class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.label, this.onTap, this.kind = ButtonKind.outline, this.small = false});

  final String label;
  final VoidCallback? onTap;
  final ButtonKind kind;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Hover(
        onTap: onTap,
        builder: (context, hovered) {
          final (bg, border, fg) = switch (kind) {
            ButtonKind.primary => (hovered ? const Color(0xFFFFE4B8) : AppColors.accent, AppColors.accent, AppColors.background),
            ButtonKind.outline => (hovered ? const Color(0x0DFFFFFF) : null, AppColors.cardBorder, AppColors.bodyText),
            ButtonKind.danger => (hovered ? const Color(0x14FF8A80) : null, Colors.transparent, AppColors.danger),
          };
          return AnimatedContainer(
            duration: kHoverFade,
            curve: Curves.easeOut,
            padding: small
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(small ? AppRadii.row : AppRadii.control),
              border: Border.all(color: border),
            ),
            child: Text(
              label,
              style: AppText.sans(13, weight: kind == ButtonKind.primary ? FontWeight.w500 : FontWeight.w400, color: fg),
            ),
          );
        },
      ),
    );
  }
}

/// Mono caps label above a group: BOARD, CLASSES, SOURCES, TAGS, DUE.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.size = 11});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: AppText.mono(size, weight: FontWeight.w500));
}

/// Small bordered mono chip: special tag on a card, Inbox type tag, key hints.
class MonoChip extends StatelessWidget {
  const MonoChip(this.text, {super.key, this.color = AppColors.mutedText});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.cardBorder),
      borderRadius: BorderRadius.circular(AppRadii.chip),
    ),
    child: Text(
      text,
      style: AppText.mono(11, weight: FontWeight.w500, color: color),
    ),
  );
}

/// A centered message for empty and error states.
class EmptyState extends StatelessWidget {
  const EmptyState(this.title, {super.key, this.detail, this.action});

  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AppText.sans(15, weight: FontWeight.w500, color: AppColors.primaryText),
        ),
        if (detail != null) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(detail!, textAlign: TextAlign.center, style: AppText.subtitle),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

/// Bordered text field matching the search field (radius 8, 36 high).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.obscure = false,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
    this.autofocus = false,
    this.mono = false,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final bool autofocus;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final style = mono ? AppText.mono(13, color: AppColors.bodyText) : AppText.sans(13);
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: style,
        cursorHeight: 15,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppText.sans(13, color: AppColors.mutedText),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: suffix,
          suffixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 0),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
            borderSide: const BorderSide(color: AppColors.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
            borderSide: const BorderSide(color: AppColors.accent),
          ),
        ),
      ),
    );
  }
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text('$error', style: AppText.sans(13)),
      backgroundColor: AppColors.cardBackground,
      behavior: SnackBarBehavior.floating,
      width: 420,
    ),
  );
}
