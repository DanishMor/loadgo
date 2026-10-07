/// One switchable part of the app. [pilotOn] is the default while pilot mode
/// is on, [normalOn] the default when it is off. An explicit value in
/// `config/features.flags` always wins.
class FeatureSpec {
  final String key;
  final bool pilotOn;
  final bool normalOn;
  const FeatureSpec(this.key, {required this.pilotOn, this.normalOn = true});
}

class FeatureKey {
  FeatureKey._();
  static const driverNetwork = 'driverNetwork';
  static const emptyTrucks = 'emptyTrucks';
  static const businessTools = 'businessTools';
  static const rentalMovers = 'rentalMovers';
  static const driverRewards = 'driverRewards';
  static const tripShare = 'tripShare';
  static const problemReport = 'problemReport';
}

/// `config/features`: {pilotMode: bool, flags: {key: bool}}. A missing
/// document means pilot mode ON with the pilot defaults below, so a fresh
/// project starts in the small, safe configuration.
class Features {
  final bool pilotMode;
  final Map<String, bool> flags;
  const Features({this.pilotMode = true, this.flags = const {}});

  /// Pilot defaults: the core freight flow, support and safety stay ON; the
  /// parts that need more people, more support or more review stay OFF.
  static const registry = <FeatureSpec>[
    FeatureSpec(FeatureKey.driverNetwork, pilotOn: false),
    FeatureSpec(FeatureKey.emptyTrucks, pilotOn: false),
    FeatureSpec(FeatureKey.businessTools, pilotOn: false),
    FeatureSpec(FeatureKey.rentalMovers, pilotOn: false),
    FeatureSpec(FeatureKey.driverRewards, pilotOn: false),
    FeatureSpec(FeatureKey.tripShare, pilotOn: true),
    FeatureSpec(FeatureKey.problemReport, pilotOn: true),
  ];

  static final _byKey = {for (final s in registry) s.key: s};

  static const pilotDefault = Features();

  /// Effective value. Unknown keys are OFF.
  bool isOn(String key) {
    final explicit = flags[key];
    if (explicit != null) return explicit;
    final spec = _byKey[key];
    if (spec == null) return false;
    return pilotMode ? spec.pilotOn : spec.normalOn;
  }

  /// null = follows the default, true/false = set by an admin.
  bool? explicit(String key) => flags[key];

  factory Features.fromMap(Map<String, dynamic>? m) {
    if (m == null) return pilotDefault;
    final raw = m['flags'];
    return Features(
      pilotMode: m['pilotMode'] is bool ? m['pilotMode'] as bool : true,
      flags: raw is Map ? {for (final e in raw.entries) if (e.key is String && _byKey.containsKey(e.key) && e.value is bool) e.key as String: e.value as bool} : const {},
    );
  }

  Map<String, Object?> toMap() => {'pilotMode': pilotMode, 'flags': flags};

  Features withPilot(bool on) => Features(pilotMode: on, flags: flags);

  /// [value] null removes the explicit setting.
  Features withFlag(String key, bool? value) {
    final next = {...flags};
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return Features(pilotMode: pilotMode, flags: next);
  }
}
