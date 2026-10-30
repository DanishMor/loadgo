import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/design_tokens.dart';
import 'app_button.dart';
import 'status_badge.dart';

/// A dialog in the design system look. [actions] are shown right to left as the
/// platform does; use [showConfirmDialog] for a yes / no question.
Future<R?> showAppDialog<R>(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  List<Widget> actions = const [],
  bool dismissible = true,
}) {
  return showDialog<R>(
    context: context,
    barrierDismissible: dismissible,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: content ?? (message == null ? null : Text(message)),
      scrollable: true,
      actionsOverflowButtonSpacing: DsSpace.s2,
      actions: actions,
    ),
  );
}

/// A question with two answers. Returns true on confirm, false on cancel, and
/// false when dismissed. [danger] makes the confirm button red (delete, cancel
/// a booking, block).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
  bool danger = false,
}) async {
  final r = await showAppDialog<bool>(
    context,
    title: title,
    message: message,
    actions: [
      Builder(builder: (ctx) => AppButton(label: cancelLabel ?? tr(ctx, 'cancel'), kind: AppButtonKind.tertiary, expand: false, onPressed: () => Navigator.of(ctx).pop(false))),
      Builder(builder: (ctx) => AppButton(label: confirmLabel ?? tr(ctx, 'dsConfirm'), kind: danger ? AppButtonKind.danger : AppButtonKind.primary, expand: false, onPressed: () => Navigator.of(ctx).pop(true))),
    ],
  );
  return r ?? false;
}

/// A bottom sheet with a drag handle, a title, safe-area padding and a scroll
/// when the content is taller than 90% of the screen.
Future<R?> showAppSheet<R>(
  BuildContext context, {
  String? title,
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(DsSpace.gutter, 0, DsSpace.gutter, DsSpace.s4 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: DsSpace.s3),
                child: Semantics(header: true, child: Text(title, style: DsType.title.copyWith(color: ctx.ds.text))),
              ),
            builder(ctx),
          ],
        ),
      ),
    ),
  );
}

enum SnackKind { info, success, error }

/// A floating message coloured by [kind] with an icon (colour never carries
/// the meaning alone). An [action] (such as Retry) stays for 8 seconds.
void showAppSnack(BuildContext context, String message, {SnackKind kind = SnackKind.info, String? actionLabel, VoidCallback? onAction}) {
  final b = Theme.of(context).brightness;
  final tone = switch (kind) { SnackKind.success => StatusTone.success, SnackKind.error => StatusTone.danger, SnackKind.info => StatusTone.progress };
  final s = statusStyle(tone, b, context.ds);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: s.bg,
      duration: Duration(seconds: onAction == null ? 4 : 8),
      content: Row(children: [
        ExcludeSemantics(child: Icon(s.icon, color: s.fg, size: 20)),
        const SizedBox(width: DsSpace.s3),
        Expanded(child: Text(message, style: DsType.bodySmall.copyWith(color: s.fg, fontWeight: FontWeight.w600))),
      ]),
      action: onAction == null ? null : SnackBarAction(label: actionLabel ?? tr(context, 'retry'), textColor: s.fg, onPressed: onAction),
    ));
}
