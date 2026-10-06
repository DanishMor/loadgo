import 'dart:convert';

/// Remote app control: force update, maintenance mode and feature flags.
/// Source order: Remote Config first, `config/app` (Firestore) as fallback.
class AppControl {
  final int minVersionCode;
  final bool maintenance;
  final String maintenanceMessage;
  final Map<String, bool> flags;

  const AppControl({
    this.minVersionCode = 0,
    this.maintenance = false,
    this.maintenanceMessage = '',
    this.flags = const {},
  });

  static const open = AppControl();

  /// Reads the shared shape used by `config/app` and the Remote Config keys
  /// (`min_version_code`, `maintenance`, `maintenance_message`, `feature_flags`).
  /// Anything missing or malformed becomes the safe default (no block).
  factory AppControl.fromMap(Map<String, dynamic>? m) {
    if (m == null) return open;
    final min = m['minVersionCode'];
    final msg = m['maintenanceMessage'];
    return AppControl(
      minVersionCode: _nonNegative(min),
      maintenance: m['maintenance'] == true,
      maintenanceMessage: msg is String ? (msg.length > 300 ? msg.substring(0, 300) : msg) : '',
      flags: parseFlags(m['flags']),
    );
  }

  static int _nonNegative(Object? v) {
    final n = v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
    return n != null && n > 0 ? n : 0;
  }

  /// Flags arrive as a map (Firestore) or a JSON string (Remote Config).
  static Map<String, bool> parseFlags(Object? raw) {
    Object? v = raw;
    if (v is String) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return const {};
      }
    }
    if (v is! Map) return const {};
    return {for (final e in v.entries) if (e.key is String && e.value is bool) e.key as String: e.value as bool};
  }

  /// Remote values win where they are set; [fallback] fills the rest.
  AppControl overlay(AppControl fallback, {required bool hasMin, required bool hasMaintenance, required bool hasMessage}) =>
      AppControl(
        minVersionCode: hasMin ? minVersionCode : fallback.minVersionCode,
        maintenance: hasMaintenance ? maintenance : fallback.maintenance,
        maintenanceMessage: hasMessage ? maintenanceMessage : fallback.maintenanceMessage,
        flags: {...fallback.flags, ...flags},
      );

  @override
  bool operator ==(Object other) =>
      other is AppControl &&
      other.minVersionCode == minVersionCode &&
      other.maintenance == maintenance &&
      other.maintenanceMessage == maintenanceMessage &&
      _sameFlags(other.flags);

  bool _sameFlags(Map<String, bool> o) => o.length == flags.length && flags.entries.every((e) => o[e.key] == e.value);

  @override
  int get hashCode => Object.hash(minVersionCode, maintenance, maintenanceMessage, flags.length);
}

/// Compares the installed build with the minimum the admin asks for.
class VersionGate {
  VersionGate._();

  /// Build number of a `1.2.3+45` style version (0 when there is none).
  static int codeOf(String version) {
    final i = version.indexOf('+');
    if (i < 0) return 0;
    return int.tryParse(version.substring(i + 1).trim()) ?? 0;
  }

  /// True when [currentCode] is below a positive [minCode].
  static bool needsUpdate(int currentCode, int minCode) => minCode > 0 && currentCode < minCode;
}

/// Reads feature flags with safe defaults: an unknown flag is OFF unless the
/// caller gives another default.
class FeatureFlags {
  FeatureFlags._();

  static Map<String, bool> _flags = const {};

  static void set(Map<String, bool> flags) => _flags = Map.unmodifiable(flags);

  static bool isOn(String name, {bool defaultValue = false}) => _flags[name] ?? defaultValue;
}
