import 'app_notification.dart';

/// In-app notification switches (`users/{uid}.notificationPrefs`). Missing
/// values mean "on". Push delivery is LATER(paid) (FCM); these filter the
/// in-app list and badge today.
class NotificationPrefs {
  final bool bookingUpdates;
  final bool ratings;
  final bool promotions;

  const NotificationPrefs({this.bookingUpdates = true, this.ratings = true, this.promotions = true});

  static const keys = ['bookingUpdates', 'ratings', 'promotions'];

  factory NotificationPrefs.fromMap(Object? m) {
    final d = m is Map ? m : const {};
    bool on(String k) => d[k] != false;
    return NotificationPrefs(bookingUpdates: on('bookingUpdates'), ratings: on('ratings'), promotions: on('promotions'));
  }

  Map<String, bool> toMap() => {'bookingUpdates': bookingUpdates, 'ratings': ratings, 'promotions': promotions};

  NotificationPrefs copyWith({bool? bookingUpdates, bool? ratings, bool? promotions}) => NotificationPrefs(
        bookingUpdates: bookingUpdates ?? this.bookingUpdates,
        ratings: ratings ?? this.ratings,
        promotions: promotions ?? this.promotions,
      );

  /// Whether an in-app notification of [type] should be shown.
  bool allows(String type) => type == NotificationType.ratingReceived ? ratings : bookingUpdates;
}

/// Optional data-use choices (`users/{uid}.consents`). Everything defaults
/// to off until the user opts in.
class Consents {
  final bool location;
  final bool analytics;
  final bool marketing;

  const Consents({this.location = false, this.analytics = false, this.marketing = false});

  static const keys = ['location', 'analytics', 'marketing'];

  factory Consents.fromMap(Object? m) {
    final d = m is Map ? m : const {};
    return Consents(location: d['location'] == true, analytics: d['analytics'] == true, marketing: d['marketing'] == true);
  }

  Map<String, bool> toMap() => {'location': location, 'analytics': analytics, 'marketing': marketing};

  Consents copyWith({bool? location, bool? analytics, bool? marketing}) => Consents(
        location: location ?? this.location,
        analytics: analytics ?? this.analytics,
        marketing: marketing ?? this.marketing,
      );
}
