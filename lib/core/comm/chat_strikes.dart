/// The chat strike ladder (Task 68), pure. Keep in sync with the `users`
/// rules in firestore.rules (`chatViolationStep`, `chatBlockOk`,
/// `chatDecayStep`).
///
/// * Strike 1 and 2: a warning.
/// * Strike 3: chat and calls off for 24 hours.
/// * Strike 4: 3 days.
/// * Strike 5 and more: 7 days and an admin review.
/// * 30 clean days after the last strike take one strike off.
class ChatLadder {
  ChatLadder._();

  static const warnings = 2;
  static const decayDays = 30;

  /// How long chat and calls stay off after reaching [strikes] strikes
  /// (null = only a warning).
  static Duration? blockFor(int strikes) {
    if (strikes >= 5) return const Duration(days: 7);
    if (strikes == 4) return const Duration(days: 3);
    if (strikes == 3) return const Duration(hours: 24);
    return null;
  }

  static bool needsReview(int strikes) => strikes >= 5;

  /// True when one strike may come off: there are strikes and [decayDays]
  /// have passed since the last change.
  static bool canDecay({required int strikes, required DateTime? lastChange, required DateTime now}) =>
      strikes > 0 && lastChange != null && !now.isBefore(lastChange.add(const Duration(days: decayDays)));
}

/// What `users` says about a person's chat standing.
class ChatStatus {
  final int strikes;
  final int seq;
  final DateTime? blockedUntil;
  final DateTime? strikeAt;
  final bool review;

  const ChatStatus({this.strikes = 0, this.seq = 0, this.blockedUntil, this.strikeAt, this.review = false});

  bool isBlocked(DateTime now) => blockedUntil != null && blockedUntil!.isAfter(now);

  factory ChatStatus.fromUser(Map<String, dynamic>? u, DateTime Function(Object?) toDate) {
    DateTime? d(Object? v) => v == null ? null : toDate(v);
    return ChatStatus(
      strikes: (u?['chatStrikes'] as num?)?.toInt() ?? 0,
      seq: (u?['chatSeq'] as num?)?.toInt() ?? 0,
      blockedUntil: d(u?['chatBlockedUntil']),
      strikeAt: d(u?['chatStrikeAt']),
      review: u?['chatReview'] == true,
    );
  }
}

/// What a granted appeal does to a person's standing (MASTER-6 Task 34): one
/// strike off. The suspension is lifted when the lower count no longer calls
/// for one, and the review flag when it no longer calls for a review.
class AppealOutcome {
  final int strikes;
  final bool liftBlock;
  final bool clearReview;
  const AppealOutcome(this.strikes, {required this.liftBlock, required this.clearReview});

  static AppealOutcome grant(int strikesNow) {
    final s = strikesNow > 0 ? strikesNow - 1 : 0;
    return AppealOutcome(s, liftBlock: ChatLadder.blockFor(s) == null, clearReview: !ChatLadder.needsReview(s));
  }

  /// A person may appeal a strike for this many days after it was given.
  static const windowDays = 14;

  static bool open(DateTime violationAt, DateTime now) => now.isBefore(violationAt.add(const Duration(days: windowDays)));
}
