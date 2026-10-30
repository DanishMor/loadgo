import 'features.dart';

/// Part 5 (H31): one tap switches off a whole group of features when something goes wrong (money, cost, abuse).
/// Switching off writes an explicit OFF for each key in `config/features.flags`; switching a group back on is done
/// per feature on the same screen (Default / On / Off), so nothing here can turn a feature ON by accident.
class KillGroup {
  final String id;
  final List<String> flags;

  const KillGroup(this.id, this.flags);
}

class KillSwitches {
  KillSwitches._();

  /// The groups, in the order of docs/INCIDENT_RESPONSE.md.
  static const groups = <KillGroup>[
    // Money is wrong or being drained: no gateway payment, no server wallet work, no held payments.
    KillGroup('money', [FeatureKey.paymentGateway, FeatureKey.serverWallet, FeatureKey.payHold]),
    // Text messages and ID checks cost money per call (SMS pumping, a bill spike).
    KillGroup('costs', [FeatureKey.smsGateway, FeatureKey.kycVerify, FeatureKey.maps, FeatureKey.adminBroadcast, FeatureKey.photoUploads, FeatureKey.vehiclePhotos]),
    // Loads go out in waves and bids are taken (a wrong price, a flood of bids).
    KillGroup('dispatch', [FeatureKey.dispatchV2]),
    // Push notifications (spam, wrong text).
    KillGroup('push', [FeatureKey.pushNotifications]),
    // Everything the server does on its own: the app keeps working on the rules alone.
    KillGroup('server', [
      FeatureKey.serverLimits,
      FeatureKey.serverChatScan,
      FeatureKey.serverCredits,
      FeatureKey.serverTrust,
      FeatureKey.serverJobs,
      FeatureKey.serverAdminActions,
      FeatureKey.serverDeletion,
      FeatureKey.serverWallet,
      FeatureKey.paymentGateway,
      FeatureKey.pushNotifications,
      FeatureKey.dispatchV2,
    ]),
  ];

  static KillGroup? byId(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }
}

extension FeaturesKill on Features {
  /// Explicit OFF for every key of [group]. Keys that are not features are ignored.
  Features withGroupOff(KillGroup group) {
    var next = this;
    for (final key in group.flags) {
      next = next.withFlag(key, false);
    }
    return next;
  }
}
