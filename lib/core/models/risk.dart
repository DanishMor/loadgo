/// Account risk level, set only by admins. Must stay in sync with firestore.rules.
class RiskTier {
  RiskTier._();
  static const normal = 'normal';

  /// Watched by admins; can still use the app.
  static const review = 'review';

  /// Cannot post or accept loads.
  static const restricted = 'restricted';
  static const suspended = 'suspended';

  static const all = [normal, review, restricted, suspended];

  static bool canTransact(String? tier) => tier == null || tier == normal || tier == review;
}

/// Thrown when a restricted/suspended account tries to post, offer or accept.
class AccountRestrictedException implements Exception {
  final String tier;
  AccountRestrictedException(this.tier);

  @override
  String toString() => 'AccountRestrictedException($tier)';
}

/// Cancellations at or above this count put a user on the admin flag list.
const int cancelFlagThreshold = 3;
