import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'design_tokens.dart';

/// Colours that used to be hard-coded light greys. Screens read them through
/// `AppColors` (core/widgets/common.dart); dark mode swaps the whole set.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg, card, text, strong, muted, hint, border, tint, chip, warnBg;

  const AppPalette({
    required this.bg, required this.card, required this.text, required this.strong, required this.muted,
    required this.hint, required this.border, required this.tint, required this.chip, required this.warnBg,
  });

  /// The palette of the theme being shown; set by the app builder (see main.dart).
  static AppPalette current = light;

  static AppPalette _from(DsColors c) => AppPalette(
        bg: c.bg, card: c.surface, text: c.text, strong: c.textStrong, muted: c.textMuted,
        hint: c.textHint, border: c.border, tint: c.tint, chip: c.chip, warnBg: c.warningBg,
      );

  /// Built from the design tokens (design_tokens.dart); the values live there.
  static final light = _from(DsColors.light);
  static final dark = _from(DsColors.dark);

  @override
  AppPalette copyWith({Color? bg, Color? card, Color? text, Color? strong, Color? muted, Color? hint, Color? border, Color? tint, Color? chip, Color? warnBg}) =>
      AppPalette(
        bg: bg ?? this.bg, card: card ?? this.card, text: text ?? this.text, strong: strong ?? this.strong, muted: muted ?? this.muted,
        hint: hint ?? this.hint, border: border ?? this.border, tint: tint ?? this.tint, chip: chip ?? this.chip, warnBg: warnBg ?? this.warnBg,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      bg: l(bg, other.bg), card: l(card, other.card), text: l(text, other.text), strong: l(strong, other.strong), muted: l(muted, other.muted),
      hint: l(hint, other.hint), border: l(border, other.border), tint: l(tint, other.tint), chip: l(chip, other.chip), warnBg: l(warnBg, other.warnBg),
    );
  }
}


/// The colours that tell the three kinds of person apart, used for icons and
/// thin lines only (a light touch, never a fill behind text).
@immutable
class RoleAccents extends ThemeExtension<RoleAccents> {
  final Color customer, driver, transporter;
  const RoleAccents({required this.customer, required this.driver, required this.transporter});

  /// [role] is 'customer', 'driver' or 'transporter'; anything else gets the brand colour.
  Color forRole(String? role, Color fallback) => switch (role) {
        'customer' => customer,
        'driver' => driver,
        'transporter' => transporter,
        _ => fallback,
      };

  static RoleAccents of(BuildContext context) =>
      Theme.of(context).extension<RoleAccents>() ?? RoleAccents(customer: DsColors.light.roleCustomer, driver: DsColors.light.roleDriver, transporter: DsColors.light.roleTransporter);

  @override
  RoleAccents copyWith({Color? customer, Color? driver, Color? transporter}) =>
      RoleAccents(customer: customer ?? this.customer, driver: driver ?? this.driver, transporter: transporter ?? this.transporter);

  @override
  RoleAccents lerp(ThemeExtension<RoleAccents>? other, double t) {
    if (other is! RoleAccents) return this;
    return RoleAccents(customer: Color.lerp(customer, other.customer, t)!, driver: Color.lerp(driver, other.driver, t)!, transporter: Color.lerp(transporter, other.transporter, t)!);
  }
}

class AppTheme {
  AppTheme._();

  /// The brand colour the Material scheme grows from.
  static const seed = DsBrand.navy;

  /// Material 3 theme for [brightness], every colour, text style, radius and
  /// size taken from the design tokens. Dark mode is navy-tinted, not black.
  static ThemeData build(Brightness brightness, {bool lowEnd = false}) {
    DsMotion.lowEnd = lowEnd;
    final c = DsColors.of(brightness);
    final p = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.tint,
      onPrimaryContainer: c.text,
      secondary: c.accent,
      onSecondary: c.onAccent,
      secondaryContainer: c.warningBg,
      onSecondaryContainer: c.warning,
      tertiary: c.accentStrong,
      onTertiary: c.onPrimary,
      error: c.error,
      onError: brightness == Brightness.dark ? c.onPrimary : const Color(0xFFFFFFFF),
      errorContainer: c.errorBg,
      onErrorContainer: c.error,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.textMuted,
      surfaceContainerLowest: c.bg,
      surfaceContainerLow: c.bg,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.chip,
      surfaceContainerHighest: c.chip,
      outline: c.inputBorder,
      outlineVariant: c.border,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: c.text,
      onInverseSurface: c.bg,
      inversePrimary: c.accent,
      surfaceTint: Colors.transparent,
    );
    OutlineInputBorder border(Color color, [double w = 1]) =>
        OutlineInputBorder(borderRadius: DsRadius.all(DsRadius.md), borderSide: BorderSide(color: color, width: w));
    final shape = RoundedRectangleBorder(borderRadius: DsRadius.all(DsRadius.md));
    const minTap = Size(DsSpace.tapMin, DsSpace.tapMin);
    final labelStyle = DsType.label.copyWith(fontSize: 16);
    return ThemeData(
      useMaterial3: true,
      // Low-end device mode: no page slide, no ink ripple (MASTER-6 Task 40).
      pageTransitionsTheme: lowEnd ? const PageTransitionsTheme(builders: {TargetPlatform.android: _NoTransitions(), TargetPlatform.iOS: _NoTransitions()}) : null,
      splashFactory: lowEnd ? NoSplash.splashFactory : null,
      fontFamily: DsType.family,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: DsType.textTheme(c),
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      dividerColor: c.border,
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      extensions: [p, RoleAccents(customer: c.roleCustomer, driver: c.roleDriver, transporter: c.roleTransporter)],
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: DsElevation.none,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: DsRadius.all(DsRadius.lg), side: BorderSide(color: c.border)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        foregroundColor: c.text,
        surfaceTintColor: Colors.transparent,
        elevation: DsElevation.none,
        scrolledUnderElevation: DsElevation.none,
        centerTitle: false,
        titleTextStyle: DsType.title.copyWith(color: c.text),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.tint,
        elevation: DsElevation.low,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => DsType.caption.copyWith(color: s.contains(WidgetState.selected) ? c.text : c.textMuted, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400)),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.primary : c.textMuted)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: DsElevation.sheet,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(DsRadius.xl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: DsElevation.dialog,
        shape: RoundedRectangleBorder(borderRadius: DsRadius.all(DsRadius.xl)),
        titleTextStyle: DsType.title.copyWith(color: c.text),
        contentTextStyle: DsType.body.copyWith(color: c.textStrong),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.text,
        contentTextStyle: DsType.bodySmall.copyWith(color: c.bg),
        actionTextColor: c.accent,
        shape: RoundedRectangleBorder(borderRadius: DsRadius.all(DsRadius.md)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: DsType.body.copyWith(color: c.textHint),
        labelStyle: DsType.body.copyWith(color: c.textMuted),
        helperStyle: DsType.caption.copyWith(color: c.textMuted),
        errorStyle: DsType.caption.copyWith(color: c.error),
        border: border(c.inputBorder),
        enabledBorder: border(c.inputBorder),
        focusedBorder: border(c.focus, 2),
        errorBorder: border(c.error),
        focusedErrorBorder: border(c.error, 2),
        contentPadding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s4),
      ),
      // The action on a screen is saffron with dark text; secondary is an outline.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          minimumSize: minTap,
          textStyle: labelStyle,
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.s5, vertical: DsSpace.s3),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          elevation: DsElevation.none,
          minimumSize: minTap,
          textStyle: labelStyle,
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.s5, vertical: DsSpace.s3),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.primary,
          minimumSize: minTap,
          textStyle: labelStyle,
          shape: shape,
          side: BorderSide(color: c.inputBorder),
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.s5, vertical: DsSpace.s3),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.primary, minimumSize: minTap, textStyle: labelStyle, shape: shape),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: minTap, foregroundColor: c.textStrong)),
      chipTheme: ChipThemeData(
        backgroundColor: c.chip,
        selectedColor: c.tint,
        disabledColor: c.chip,
        side: BorderSide(color: c.border),
        labelStyle: DsType.bodySmall.copyWith(color: c.textStrong),
        secondaryLabelStyle: DsType.bodySmall.copyWith(color: c.text),
        shape: RoundedRectangleBorder(borderRadius: DsRadius.all(DsRadius.sm)),
      ),
      listTileTheme: ListTileThemeData(iconColor: c.textStrong, textColor: c.text, minVerticalPadding: DsSpace.s2),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onPrimary : c.inputBorder),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : c.chip),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : c.inputBorder),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.onPrimary),
        side: BorderSide(color: c.inputBorder, width: 2),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : c.inputBorder)),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accentStrong, linearTrackColor: c.chip, circularTrackColor: c.chip),
      tooltipTheme: TooltipThemeData(decoration: BoxDecoration(color: c.text, borderRadius: DsRadius.all(DsRadius.sm)), textStyle: DsType.caption.copyWith(color: c.bg)),
      focusColor: c.focus.withValues(alpha: 0.2),
    );
  }
}
class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) => child;
}

/// Low-end device mode (MASTER-6 Task 40): fewer animations so an old phone
/// feels quicker. Off by default, kept on the device.
class LowEndMode {
  LowEndMode._();

  static const _key = 'low_end_mode';
  static final ValueNotifier<bool> notifier = ValueNotifier(false);
  static bool get isOn => notifier.value;

  static Future<void> load() async {
    try {
      notifier.value = (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {
      notifier.value = false;
    }
  }

  static Future<void> set(bool on) async {
    notifier.value = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, on);
    } catch (_) {}
  }
}

/// system | light | dark, kept on the device.
class ThemeStore {
  ThemeStore._();

  static const _key = 'theme_mode';
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  static Future<void> load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_key);
      mode.value = ThemeMode.values.where((m) => m.name == v).firstOrNull ?? ThemeMode.system;
    } catch (_) {}
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, m.name);
    } catch (_) {}
  }
}

/// Largest text scale the layouts are built for; bigger system settings are
/// clamped so rows and buttons do not break (accessibility keeps up to 2.0x;
/// test/theme_layout_test.dart checks the main screens at 2.0x on a 360x640 phone).
const double maxTextScale = 2.0;

/// Marks every mounted widget dirty (used once after the light/dark switch).
void repaintAll() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}
