import '../models/chat_message.dart';

/// Pure helpers of the chat screen (MASTER-6 Task 33).
class ChatHelpers {
  ChatHelpers._();

  /// Ready-made lines, none of which holds a number or a link, so they never
  /// trip the contact filter. Keys are translation keys (`qr_<id>`).
  static const driverReplies = ['onMyWay', 'reachedPickup', 'loadingDone', 'late30', 'traffic', 'sendLocation', 'thanks', 'ok'];
  static const customerReplies = ['goodsReady', 'wherePlease', 'waitComing', 'gateInfo', 'thanks', 'ok'];

  static List<String> repliesFor({required bool isDriver}) => isDriver ? driverReplies : customerReplies;

  /// A message I sent counts as seen once the other person's last read time is
  /// at or after it. A message without a server time yet is only "sent".
  static bool isSeen(ChatMessage m, DateTime? otherLastRead) => m.createdAt != null && otherLastRead != null && !m.createdAt!.isAfter(otherLastRead);

  /// How many messages can still be sent this hour, given the counter.
  static int remaining({required int limit, required int used}) => (limit - used).clamp(0, limit);

  /// Show the "N left" hint when this few remain.
  static const lowAt = 20;
}
