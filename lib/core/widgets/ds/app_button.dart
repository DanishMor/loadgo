import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// Which button. One [primary] (saffron) action per screen; the rest are quieter.
enum AppButtonKind {
  /// The action of the screen: saffron with dark text.
  primary,

  /// Navy button, for a second strong action next to a saffron one.
  strong,

  /// An outline.
  secondary,

  /// Text only.
  tertiary,

  /// Deleting, cancelling, blocking: red.
  danger,
}

/// The one button of the design system (replaces the old PrimaryButton look).
///
/// * [big] is the Driver Simple Mode size: 64 dp tall, 18 sp text.
/// * [loading] disables the button and shows a spinner; the label stays for
///   screen readers.
/// * [expand] stretches it to the full width (default); off for inline buttons.
/// * The tap target is never under 48 dp.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool big;
  final bool expand;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = AppButtonKind.primary,
    this.icon,
    this.loading = false,
    this.big = false,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = big ? DsSpace.tapBig : DsSpace.tapMin + DsSpace.s1; // 64 or 52
    final textStyle = (big ? DsType.subtitle.copyWith(fontSize: 18) : DsType.label.copyWith(fontSize: 16));
    final disabled = loading || onPressed == null;
    final fgOnFilled = switch (kind) {
      AppButtonKind.primary => scheme.onSecondary,
      AppButtonKind.strong => scheme.onPrimary,
      AppButtonKind.danger => scheme.onError,
      _ => scheme.primary,
    };

    final child = loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(fgOnFilled)),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: big ? 24 : 20), const SizedBox(width: DsSpace.s2)],
              Flexible(child: Text(label, textAlign: TextAlign.center, style: textStyle)),
            ],
          );

    final minSize = Size(expand ? double.infinity : DsSpace.tapMin, height);
    final shape = RoundedRectangleBorder(borderRadius: DsRadius.all(big ? DsRadius.lg : DsRadius.md));
    final button = switch (kind) {
      AppButtonKind.primary => ElevatedButton(
          onPressed: disabled ? null : onPressed,
          style: ElevatedButton.styleFrom(backgroundColor: scheme.secondary, foregroundColor: scheme.onSecondary, elevation: DsElevation.none, minimumSize: minSize, shape: shape, textStyle: textStyle),
          child: child,
        ),
      AppButtonKind.strong => ElevatedButton(
          onPressed: disabled ? null : onPressed,
          style: ElevatedButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary, elevation: DsElevation.none, minimumSize: minSize, shape: shape, textStyle: textStyle),
          child: child,
        ),
      AppButtonKind.danger => ElevatedButton(
          onPressed: disabled ? null : onPressed,
          style: ElevatedButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError, elevation: DsElevation.none, minimumSize: minSize, shape: shape, textStyle: textStyle),
          child: child,
        ),
      AppButtonKind.secondary => OutlinedButton(
          onPressed: disabled ? null : onPressed,
          style: OutlinedButton.styleFrom(minimumSize: minSize, shape: shape, textStyle: textStyle),
          child: child,
        ),
      AppButtonKind.tertiary => TextButton(
          onPressed: disabled ? null : onPressed,
          style: TextButton.styleFrom(minimumSize: Size(DsSpace.tapMin, height), shape: shape, textStyle: textStyle),
          child: child,
        ),
    };

    return Semantics(
      button: true,
      enabled: !disabled,
      label: label,
      excludeSemantics: true,
      onTap: disabled ? null : onPressed,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
