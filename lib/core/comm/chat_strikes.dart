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
