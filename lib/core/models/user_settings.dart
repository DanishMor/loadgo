import '../reminders/reminders.dart';
import 'app_notification.dart';

/// The groups a user can switch on or off in the notification center. The
/// values are the keys stored in `users.notificationPrefs`.
class NotifCategory {
  NotifCategory._();
  static const bookings = 'bookingUpdates';
  static const payments = 'payments';
  static const ratings = 'ratings';
  static const offers = 'promotions';
  static const reminders = 'reminders';

  static const all = [bookings, payments, ratings, offers, reminders];

  /// Category of a stored notification.
  static String ofType(String type) => switch (type) {
        NotificationType.ratingReceived => ratings,
        NotificationType.paymentMarked || NotificationType.paymentConfirmed => payments,
        _ => bookings,
      };

  /// Category of an in-app reminder.
  static String ofReminder(ReminderKind k) => switch (k) {
        ReminderKind.tripDelayed || ReminderKind.pickupSoon || ReminderKind.noDriverYet => bookings,
        ReminderKind.offersWaiting || ReminderKind.counterWaiting || ReminderKind.confirmWaiting => offers,
        ReminderKind.rateTrip => ratings,
        ReminderKind.returnLoads || ReminderKind.vehicleDocs || ReminderKind.serviceDue || ReminderKind.tyreDue || ReminderKind.licenceExpiring => reminders,
      };
}

/// In-app notification switches (`users/{uid}.notificationPrefs`). Missing
/// values mean "on". Push delivery is LATER(paid) (FCM); these filter the
/// in-app list, reminders and badge today. Safety alerts (accident,
/// breakdown) cannot be switched off.
class NotificationPrefs {
  final bool bookingUpdates;
  final bool ratings;
  final bool promotions;
  final bool payments;
  final bool reminders;

  const NotificationPrefs({this.bookingUpdates = true, this.ratings = true, this.promotions = true, this.payments = true, this.reminders = true});

  static const keys = NotifCategory.all;

  factory NotificationPrefs.fromMap(Object? m) {
    final d = m is Map ? m : const {};
    bool on(String k) => d[k] != false;
    return NotificationPrefs(
      bookingUpdates: on('bookingUpdates'),
      ratings: on('ratings'),
      promotions: on('promotions'),
      payments: on('payments'),
      reminders: on('reminders'),
    );
  }

  Map<String, bool> toMap() => {for (final c in NotifCategory.all) c: isOn(c)};

  NotificationPrefs copyWith({bool? bookingUpdates, bool? ratings, bool? promotions, bool? payments, bool? reminders}) => NotificationPrefs(
        bookingUpdates: bookingUpdates ?? this.bookingUpdates,
        ratings: ratings ?? this.ratings,
        promotions: promotions ?? this.promotions,
        payments: payments ?? this.payments,
        reminders: reminders ?? this.reminders,
      );

  bool isOn(String category) => switch (category) {
        NotifCategory.bookings => bookingUpdates,
        NotifCategory.payments => payments,
        NotifCategory.ratings => ratings,
        NotifCategory.offers => promotions,
        NotifCategory.reminders => reminders,
        _ => true,
      };

  NotificationPrefs set(String category, bool value) => switch (category) {
        NotifCategory.bookings => copyWith(bookingUpdates: value),
        NotifCategory.payments => copyWith(payments: value),
        NotifCategory.ratings => copyWith(ratings: value),
        NotifCategory.offers => copyWith(promotions: value),
        NotifCategory.reminders => copyWith(reminders: value),
        _ => this,
      };

  /// Whether an in-app notification of [type] should be shown.
  bool allows(String type) =>
      type == NotificationType.breakdownReported ||
      type == NotificationType.accidentReported ||
      // An inspection is asked for on the road: these are never muted.
      type == NotificationType.inspectionRequest ||
      type == NotificationType.inspectionApproved ||
      type == NotificationType.inspectionDenied ||
      isOn(NotifCategory.ofType(type));

  /// Whether an in-app reminder of [kind] should be shown.
  bool allowsReminder(ReminderKind kind) => isOn(NotifCategory.ofReminder(kind));
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
