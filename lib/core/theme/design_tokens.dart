import 'package:flutter/material.dart';

/// Load 20 design tokens (L4): the one place for colour, type, spacing, radius,
/// elevation and motion. Nothing else in the app should spell a colour or a
/// text style (test/theme_guard_test.dart). The direction is deep navy for
/// trust and saffron / amber for the one action on a screen, with green, amber
/// and red kept for status and a cool slate for everything neutral.
///
/// test/design_tokens_test.dart proves the contrast of every pair that is
/// used: text 4.5:1 or more, UI parts (input borders, focus ring, icons) 3:1
/// or more, in light and in dark. If a value changes, that test says which
/// pair broke.
@immutable
class DsColors {
  // Surfaces
  final Color bg, surface, chip, tint;
  // Text
  final Color text, textStrong, textMuted, textHint;
  // Lines. [border] is decoration only; [inputBorder] and [focus] identify a control (3:1).
  final Color border, inputBorder, focus;
  // Brand
  final Color primary, onPrimary, accent, onAccent, accentStrong;
  // Status (text/icon colour and its soft background)
  final Color success, successBg, warning, warningBg, error, errorBg;
  // A light touch of colour per role (icons and thin lines only)
  final Color roleCustomer, roleDriver, roleTransporter;
  // Admin mode banner
  final Color adminBanner, onAdminBanner;

  const DsColors({
    required this.bg,
    required this.surface,
    required this.chip,
    required this.tint,
    required this.text,
    required this.textStrong,
    required this.textMuted,
    required this.textHint,
    required this.border,
    required this.inputBorder,
    required this.focus,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.accentStrong,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.error,
    required this.errorBg,
    required this.roleCustomer,
    required this.roleDriver,
    required this.roleTransporter,
    required this.adminBanner,
    required this.onAdminBanner,
  });

  static const light = DsColors(
    bg: Color(0xFFF6F8FB),
    surface: Color(0xFFFFFFFF),
    chip: Color(0xFFEDF1F6),
    tint: Color(0xFFE3ECF8),
    text: Color(0xFF0F1B2D),
    textStrong: Color(0xFF2B3A52),
    textMuted: Color(0xFF4F5F77),
    textHint: Color(0xFF5B6B83),
    border: Color(0xFFDDE3EC),
    inputBorder: Color(0xFF7B889C),
    focus: Color(0xFF123A6B),
    primary: Color(0xFF123A6B),
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFFF2A100),
    onAccent: Color(0xFF0F1B2D),
    accentStrong: Color(0xFFB45309),
    success: Color(0xFF146C3C),
    successBg: Color(0xFFE3F5EA),
    warning: Color(0xFF9A5B00),
    warningBg: Color(0xFFFFF1D6),
    error: Color(0xFFB42318),
    errorBg: Color(0xFFFDE7E4),
    roleCustomer: Color(0xFF0E7490),
    roleDriver: Color(0xFF4338CA),
    roleTransporter: Color(0xFF9D2F6B),
    adminBanner: Color(0xFF3B1D6E),
    onAdminBanner: Color(0xFFFFFFFF),
  );

  /// Dark mode is navy-tinted, not pure black.
  static const dark = DsColors(
    bg: Color(0xFF0D1526),
    surface: Color(0xFF16213A),
    chip: Color(0xFF1F2C48),
    tint: Color(0xFF1B2F55),
    text: Color(0xFFEEF2F8),
    textStrong: Color(0xFFCBD5E3),
    textMuted: Color(0xFFA5B3C8),
    textHint: Color(0xFF9AA8BE),
    border: Color(0xFF2C3A55),
    inputBorder: Color(0xFF6F81A0),
    focus: Color(0xFF9DBDF2),
    primary: Color(0xFF9DBDF2),
    onPrimary: Color(0xFF0B1E3C),
    accent: Color(0xFFF5B13D),
    onAccent: Color(0xFF0F1B2D),
    accentStrong: Color(0xFFF5B13D),
    success: Color(0xFF4BD68A),
    successBg: Color(0xFF12301F),
    warning: Color(0xFFF7C14A),
    warningBg: Color(0xFF33280E),
    error: Color(0xFFFF9188),
    errorBg: Color(0xFF3A1A1A),
    roleCustomer: Color(0xFF67D4E8),
    roleDriver: Color(0xFFA5A8FF),
    roleTransporter: Color(0xFFE9A3CE),
    adminBanner: Color(0xFFD6C2FF),
    onAdminBanner: Color(0xFF1E1040),
  );

  static DsColors of(Brightness b) => b == Brightness.dark ? dark : light;
}

/// Spacing on a 4 / 8 grid (logical pixels).
class DsSpace {
  DsSpace._();
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;

  /// The smallest thing a thumb should hit (Material: 48; Driver Simple Mode uses [tapBig]).
  static const double tapMin = 48;
  static const double tapBig = 64;

  /// Side gutter of a phone screen.
  static const double gutter = 16;
}

/// Corner radius.
class DsRadius {
  DsRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);
}

/// Elevation (dp). Cards sit flat with a border; only sheets and dialogs lift.
class DsElevation {
  DsElevation._();
  static const double none = 0;
  static const double low = 1;
  static const double card = 2;
  static const double sheet = 4;
  static const double dialog = 8;
}

/// Motion. Always ask [DsMotion.duration] so "remove animations" (system) and
/// Low-end mode turn every duration into zero.
class DsMotion {
  DsMotion._();
  static const Duration instant = Duration.zero;
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// Set by the app from LowEndMode (see AppTheme); kept here so the tokens do not import the store.
  static bool lowEnd = false;

  static bool reduced(BuildContext context) => lowEnd || MediaQuery.maybeDisableAnimationsOf(context) == true;

  static Duration duration(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;
}

/// Type scale (size / line height / weight). Font family comes from [DsType.family]
/// (L6); other scripts fall back to the system font.
class DsType {
  DsType._();

  static const String family = 'Roboto';

  static TextStyle _s(double size, double line, FontWeight w, {double letter = 0}) =>
      TextStyle(fontFamily: family, fontSize: size, height: line / size, fontWeight: w, letterSpacing: letter);

  static TextStyle get display => _s(32, 40, FontWeight.w700);
  static TextStyle get headline => _s(24, 32, FontWeight.w700);
  static TextStyle get title => _s(20, 28, FontWeight.w600);
  static TextStyle get subtitle => _s(16, 24, FontWeight.w600);
  static TextStyle get body => _s(16, 24, FontWeight.w400);
  static TextStyle get bodySmall => _s(14, 20, FontWeight.w400);
  static TextStyle get label => _s(14, 20, FontWeight.w600, letter: 0.1);
  static TextStyle get caption => _s(12, 16, FontWeight.w400, letter: 0.2);

  /// Same as [body] with equal-width digits, for money and distances.
  static TextStyle get number => body.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// The Material text theme built from the scale, coloured for [c].
  static TextTheme textTheme(DsColors c) => TextTheme(
        displayLarge: display.copyWith(color: c.text),
        displayMedium: display.copyWith(color: c.text),
        displaySmall: headline.copyWith(color: c.text),
        headlineLarge: headline.copyWith(color: c.text),
        headlineMedium: headline.copyWith(color: c.text),
        headlineSmall: title.copyWith(color: c.text),
        titleLarge: title.copyWith(color: c.text),
        titleMedium: subtitle.copyWith(color: c.text),
        titleSmall: label.copyWith(color: c.text),
        bodyLarge: body.copyWith(color: c.text),
        bodyMedium: bodySmall.copyWith(color: c.text),
        bodySmall: caption.copyWith(color: c.textMuted),
        labelLarge: label.copyWith(color: c.text),
        labelMedium: label.copyWith(color: c.textStrong),
        labelSmall: caption.copyWith(color: c.textMuted),
      );
}
