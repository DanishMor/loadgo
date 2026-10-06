import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const light = AppPalette(
    bg: Color(0xFFF6F8FC), card: Colors.white, text: Color(0xFF111827), strong: Color(0xFF344054), muted: Color(0xFF667085),
    hint: Color(0xFF98A2B3), border: Color(0xFFE4E7EC), tint: Color(0xFFE8F1FF), chip: Color(0xFFF2F4F7), warnBg: Color(0xFFFFF6E5),
  );

  static const dark = AppPalette(
    bg: Color(0xFF0F1623), card: Color(0xFF182131), text: Color(0xFFF2F4F7), strong: Color(0xFFD0D5DD), muted: Color(0xFFA6B0C0),
    hint: Color(0xFF8A94A6), border: Color(0xFF2B3548), tint: Color(0xFF1B2D4A), chip: Color(0xFF222C3E), warnBg: Color(0xFF3A2F14),
  );

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


class AppTheme {
  AppTheme._();

  static const seed = Color(0xFF1565C0);

  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final p = dark ? AppPalette.dark : AppPalette.light;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    OutlineInputBorder border(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      extensions: [p],
      cardTheme: CardThemeData(color: p.card),
      appBarTheme: AppBarTheme(backgroundColor: p.bg, foregroundColor: p.text, surfaceTintColor: Colors.transparent),
      navigationBarTheme: NavigationBarThemeData(backgroundColor: p.card, indicatorColor: p.tint),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.card),
      dialogTheme: DialogThemeData(backgroundColor: p.card),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? p.card : const Color(0xFFF8FAFC),
        border: border(p.border),
        enabledBorder: border(p.border),
        focusedBorder: border(dark ? const Color(0xFF6EA8FE) : seed, 1.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
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
/// clamped so rows and buttons do not break (accessibility keeps up to 1.6x).
const double maxTextScale = 1.6;

/// Marks every mounted widget dirty (used once after the light/dark switch).
void repaintAll() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}
