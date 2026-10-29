/// One switchable part of the app. [pilotOn] is the default while pilot mode
/// is on, [normalOn] the default when it is off. An explicit value in
/// `config/features.flags` always wins.
class FeatureSpec {
  final String key;
  final bool pilotOn;
  final bool normalOn;

  /// E3: the heading on Admin > Features (one of [FeatureGroup.all]).
  final String group;
  const FeatureSpec(this.key, {required this.pilotOn, this.normalOn = true, this.group = FeatureGroup.core});
}

/// E3: the headings on Admin > Features, in screen order. docs/FLAGS.md lists every flag by group.
class FeatureGroup {
  FeatureGroup._();
  static const core = 'core';
  static const design = 'design';
  static const security = 'security';
  static const money = 'money';
  static const server = 'server';
  static const connect = 'connect';

  /// Regulated parts (payment hold, payouts, insurance, credit). Keys start with `legalGate` and are OFF in every mode.
  static const legal = 'legal';
  static const all = [core, design, security, money, server, connect, legal];
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
  static const transporter = 'transporter';
  static const bilty = 'bilty';

  /// F4: no screenshots or screen recording on sensitive screens (release builds).
  static const secureScreens = 'secureScreens';

  /// F9: the earnings and accounts hub for every role (the old Wallet screen stays when OFF).
  static const walletHub = 'walletHub';

  /// F8, F12: a payout is approved by one finance admin and paid by another.
  static const walletMakerChecker = 'walletMakerChecker';

  /// F11: asking for a payout or changing payout details needs a fresh OTP (last 5 minutes).
  static const walletStepUp = 'walletStepUp';

  /// F11: waiting time after changing payout details, and a daily payout limit (count and total).
  static const walletLimits = 'walletLimits';

  /// F11: an optional fingerprint / screen lock on the money screens.
  static const appLock = 'appLock';

  /// Server features (Phase C to E). Cloud Functions read the same switches from config/features.
  static const serverLimits = 'serverLimits';
  static const serverChatScan = 'serverChatScan';
  static const serverCredits = 'serverCredits';
  static const serverTrust = 'serverTrust';
  static const serverJobs = 'serverJobs';
  static const serverAdminActions = 'serverAdminActions';
  static const serverDeletion = 'serverDeletion';
  static const serverWallet = 'serverWallet';
  static const paymentGateway = 'paymentGateway';
  static const pushNotifications = 'pushNotifications';
  static const adminBroadcast = 'adminBroadcast';
  static const photoUploads = 'photoUploads';
  static const dispatchV2 = 'dispatchV2';
  static const uiV2 = 'uiV2';
  static const bizCard = 'bizCard';
  static const khata = 'khata';
  static const safetyCheckin = 'safetyCheckin';
  static const payHold = 'payHold';
  static const rateRange = 'rateRange';
  static const tripTrustCard = 'tripTrustCard';
  static const appCheckEnforce = 'appCheckEnforce';
  static const kycVerify = 'kycVerify';
  static const smsGateway = 'smsGateway';
  static const liveLocation = 'liveLocation';
  static const maps = 'maps';
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
    // Task 67: the Transporter role. ON by default (also in pilot mode) for testing.
    FeatureSpec(FeatureKey.transporter, pilotOn: true),
    // Task 70: numbered LR (bilty) with copy types, PDF and share links. ON for testing.
    FeatureSpec(FeatureKey.bilty, pilotOn: true),
    // F4: OFF until the owner has tried it on a real phone.
    FeatureSpec(FeatureKey.secureScreens, pilotOn: false, normalOn: false, group: FeatureGroup.security),
    FeatureSpec(FeatureKey.walletHub, pilotOn: false, normalOn: false, group: FeatureGroup.money),
    FeatureSpec(FeatureKey.walletMakerChecker, pilotOn: false, normalOn: false, group: FeatureGroup.money),
    FeatureSpec(FeatureKey.walletStepUp, pilotOn: false, normalOn: false, group: FeatureGroup.money),
    FeatureSpec(FeatureKey.walletLimits, pilotOn: false, normalOn: false, group: FeatureGroup.money),
    FeatureSpec(FeatureKey.appLock, pilotOn: false, normalOn: false, group: FeatureGroup.security),
    FeatureSpec(FeatureKey.serverLimits, pilotOn: false, normalOn: false, group: FeatureGroup.server),
    FeatureSpec(FeatureKey.serverChatScan, pilotOn: false, normalOn: false, group: FeatureGroup.server),
    FeatureSpec(FeatureKey.serverCredits, pilotOn: false, normalOn: false, group: FeatureGroup.server),
    FeatureSpec(FeatureKey.serverTrust, pilotOn: false, normalOn: false, group: FeatureGroup.server),
    FeatureSpec(FeatureKey.serverJobs, pilotOn: false, normalOn: false, group: FeatureGroup.server),
    FeatureSpec(FeatureKey.serverAdminActions, pilotOn: false, normalOn: false, group: FeatureGroup.server),
    FeatureSpec(FeatureKey.serverDeletion, pilotOn: false, normalOn: false, group: FeatureGroup.server),
    FeatureSpec(FeatureKey.serverWallet, pilotOn: false, normalOn: false, group: FeatureGroup.server),
    FeatureSpec(FeatureKey.paymentGateway, pilotOn: false, normalOn: false, group: FeatureGroup.money),
    FeatureSpec(FeatureKey.pushNotifications, pilotOn: false, normalOn: false, group: FeatureGroup.connect),
    FeatureSpec(FeatureKey.adminBroadcast, pilotOn: false, normalOn: false, group: FeatureGroup.server),
    FeatureSpec(FeatureKey.photoUploads, pilotOn: false, normalOn: false, group: FeatureGroup.connect),
    FeatureSpec(FeatureKey.dispatchV2, pilotOn: false, normalOn: false, group: FeatureGroup.server),
    FeatureSpec(FeatureKey.uiV2, pilotOn: true, normalOn: true, group: FeatureGroup.design),
    FeatureSpec(FeatureKey.bizCard, pilotOn: false, normalOn: false),
    FeatureSpec(FeatureKey.khata, pilotOn: false, normalOn: false),
    FeatureSpec(FeatureKey.safetyCheckin, pilotOn: false, normalOn: false, group: FeatureGroup.security),
    FeatureSpec(FeatureKey.payHold, pilotOn: false, normalOn: false, group: FeatureGroup.money),
    FeatureSpec(FeatureKey.rateRange, pilotOn: false, normalOn: false),
    FeatureSpec(FeatureKey.tripTrustCard, pilotOn: false, normalOn: false),
    FeatureSpec(FeatureKey.appCheckEnforce, pilotOn: false, normalOn: false, group: FeatureGroup.security),
    FeatureSpec(FeatureKey.kycVerify, pilotOn: false, normalOn: false, group: FeatureGroup.connect),
    FeatureSpec(FeatureKey.smsGateway, pilotOn: false, normalOn: false, group: FeatureGroup.connect),
    FeatureSpec(FeatureKey.liveLocation, pilotOn: false, normalOn: false, group: FeatureGroup.connect),
    FeatureSpec(FeatureKey.maps, pilotOn: false, normalOn: false, group: FeatureGroup.connect),
  ];

  static final _byKey = {for (final s in registry) s.key: s};

  /// E3: the registry entries under one Admin > Features heading, in registry order.
  static List<FeatureSpec> inGroup(String group) => [
    for (final s in registry)
      if (s.group == group) s,
  ];

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
      flags: raw is Map
          ? {
              for (final e in raw.entries)
                if (e.key is String && _byKey.containsKey(e.key) && e.value is bool) e.key as String: e.value as bool,
            }
          : const {},
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
