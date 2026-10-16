import 'package:flutter_test/flutter_test.dart';
import 'package:transport_app/core/models/app_notification.dart';
import 'package:transport_app/core/notifications/push_target.dart';

/// F24: where a tapped push goes.
void main() {
  PushTarget t(Map<String, dynamic>? d) => PushTarget.fromData(d);

  test('each message type opens its screen with the id', () {
    expect(t({'type': 'chat_message', 'bookingId': 'B1'}), const PushTarget(PushScreen.chat, 'B1'));
    expect(t({'type': 'inspection_request', 'bookingId': 'B1'}), const PushTarget(PushScreen.lr, 'B1'));
    expect(t({'type': 'lr_sent', 'bookingId': 'B1'}), const PushTarget(PushScreen.lr, 'B1'));
    expect(t({'type': 'payout_status'}), const PushTarget(PushScreen.wallet));
    expect(t({'type': 'payment_marked', 'bookingId': 'B1'}), const PushTarget(PushScreen.wallet));
    expect(t({'type': 'new_load', 'loadId': 'L7'}), const PushTarget(PushScreen.load, 'L7'));
    expect(t({'type': 'bid_received', 'loadId': 'L7'}), const PushTarget(PushScreen.load, 'L7'));
    expect(t({'type': 'bid_accepted', 'bookingId': 'B2'}), const PushTarget(PushScreen.booking, 'B2'));
    expect(t({'type': 'trip_status', 'bookingId': 'B2'}), const PushTarget(PushScreen.booking, 'B2'));
    expect(t({'type': 'status_changed', 'bookingId': 'B2'}), const PushTarget(PushScreen.booking, 'B2'));
  });

  test('every existing in-app notification type goes somewhere sensible', () {
    for (final type in NotificationType.all) {
      final target = t({'type': type, 'bookingId': 'B1', 'loadId': 'L1'});
      expect(PushScreen.values.contains(target.screen), isTrue, reason: type);
    }
  });

  test('a missing or unsafe id falls back to the notification list, never to a broken screen', () {
    for (final d in <Map<String, dynamic>?>[
      null,
      {},
      {'type': 'chat_message'},
      {'type': 'chat_message', 'bookingId': ''},
      {'type': 'chat_message', 'bookingId': '../x'},
      {'type': 'chat_message', 'bookingId': 5},
      {'type': 'new_load', 'loadId': 'a b'},
      {'type': 'trip_status', 'bookingId': 'x' * 200},
      {'type': 'something_new'},
      {'type': 7, 'bookingId': 'B1'},
    ]) {
      expect(t(d), const PushTarget(PushScreen.notifications), reason: '$d');
    }
  });

  test('payload data never carries a phone number: the target only keeps an id', () {
    final target = t({'type': 'chat_message', 'bookingId': 'B1', 'phone': '9876543210', 'text': 'call me'});
    expect(target.toString().contains('9876543210'), isFalse);
    expect(target.id, 'B1');
  });

  test('every message type has a channel and the channels are the known five', () {
    expect(PushTarget.channels, ['bookings', 'chat', 'payments', 'offers', 'admin']);
    for (final type in [...NotificationType.all, 'new_load', 'bid_received', 'bid_accepted', 'trip_status', 'chat_message', 'inspection_request', 'sos', 'doc_expiry', 'payout_status', 'announcement']) {
      expect(PushTarget.channels, contains(PushTarget.channelFor(type)), reason: type);
    }
    expect(PushTarget.channelFor(null), 'bookings');
    expect(PushTarget.channelFor('chat_message'), 'chat');
    expect(PushTarget.channelFor('payout_status'), 'payments');
    expect(PushTarget.channelFor('sos'), 'admin');
  });
}
