/// Where a tapped push message goes (F24). Pure: the message data in, a place
/// out. The server sends `type` plus an id (`bookingId` or `loadId`). Anything
/// unknown or damaged opens the in-app notification list, which always exists
/// as the fallback.
enum PushScreen {
  /// The booking (the driver's trip screen or the customer's tracking screen).
  booking,

  /// The chat of a booking.
  chat,

  /// The LR (bilty) of a booking: copies, inspection requests.
  lr,

  /// Earnings and accounts.
  wallet,

  /// An open load (drivers can bid or accept).
  load,

  /// The list of notifications inside the app.
  notifications,
}

class PushTarget {
  final PushScreen screen;
  final String? id;
  const PushTarget(this.screen, [this.id]);

  /// The notification channels on the phone (the user can switch each off in
  /// the phone settings). Keep in sync with MainActivity.kt and the functions.
  static const channels = ['bookings', 'chat', 'payments', 'offers', 'admin'];

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  static String? _id(Object? v) => v is String && _safeId.hasMatch(v) ? v : null;

  /// The channel a message type belongs to (the server puts it in the payload too).
  static String channelFor(String? type) => switch (type) {
        'chat_message' => 'chat',
        'payout_status' || 'payment_marked' || 'payment_confirmed' => 'payments',
        'new_load' || 'bid_received' || 'bid_accepted' || 'promo' => 'offers',
        'sos' || 'announcement' || 'doc_expiry' || 'admin_alert' => 'admin',
        _ => 'bookings',
      };

  static PushTarget fromData(Map<String, dynamic>? data) {
    if (data == null) return const PushTarget(PushScreen.notifications);
    final type = data['type'] is String ? data['type'] as String : '';
    final booking = _id(data['bookingId']);
    final load = _id(data['loadId']);
    switch (type) {
      case 'chat_message':
        return booking == null ? const PushTarget(PushScreen.notifications) : PushTarget(PushScreen.chat, booking);
      case 'inspection_request' || 'inspection_approved' || 'inspection_denied' || 'lr_sent':
        return booking == null ? const PushTarget(PushScreen.notifications) : PushTarget(PushScreen.lr, booking);
      case 'payout_status' || 'payment_marked' || 'payment_confirmed':
        return const PushTarget(PushScreen.wallet);
      case 'new_load' || 'bid_received':
        return load == null ? const PushTarget(PushScreen.notifications) : PushTarget(PushScreen.load, load);
      case 'bid_accepted' || 'trip_status' || 'status_changed' || 'load_accepted' || 'booking_cancelled' || 'trip_assigned' || 'driver_arriving_soon' || 'breakdown_reported' || 'accident_reported':
        return booking == null ? const PushTarget(PushScreen.notifications) : PushTarget(PushScreen.booking, booking);
      default:
        return const PushTarget(PushScreen.notifications);
    }
  }

  @override
  bool operator ==(Object other) => other is PushTarget && other.screen == screen && other.id == id;

  @override
  int get hashCode => Object.hash(screen, id);

  @override
  String toString() => 'PushTarget($screen, $id)';
}
