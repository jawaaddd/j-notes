import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'widgets.dart';

/// A small modal in the app's style: title, body, and a row of actions.
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, required this.title, required this.body, required this.actions, this.width = 420});

  final String title;
  final Widget body;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AppText.sans(16, weight: FontWeight.w600, color: AppColors.headingText),
            ),
            const SizedBox(height: 14),
            body,
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 10), a],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> promptText(BuildContext context, {required String title, String? hint, String initial = '', String action = 'Save'}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      void submit() {
        final v = controller.text.trim();
        if (v.isNotEmpty) Navigator.pop(context, v);
      }

      return AppDialog(
        title: title,
        body: AppTextField(controller: controller, hint: hint, autofocus: true, onSubmitted: (_) => submit()),
        actions: [
          AppButton(label: 'Cancel', onTap: () => Navigator.pop(context)),
          AppButton(label: action, kind: ButtonKind.primary, onTap: submit),
        ],
      );
    },
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Delete',
  bool danger = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AppDialog(
      title: title,
      body: Text(message, style: AppText.body),
      actions: [
        AppButton(label: 'Cancel', onTap: () => Navigator.pop(context, false)),
        AppButton(label: action, kind: danger ? ButtonKind.danger : ButtonKind.primary, onTap: () => Navigator.pop(context, true)),
      ],
    ),
  );
  return ok ?? false;
}

/// For controls whose flow isn't designed yet (ui-frontend-spec, Open decisions).
Future<void> showNotDesigned(BuildContext context, String what, String detail) => showDialog<void>(
  context: context,
  builder: (context) => AppDialog(
    title: what,
    body: Text(detail, style: AppText.body),
    actions: [AppButton(label: 'OK', kind: ButtonKind.primary, onTap: () => Navigator.pop(context))],
  ),
);
