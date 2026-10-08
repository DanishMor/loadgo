import '../app_info.dart';
/// UPI payment link (`upi://pay`) for [amountPaise] to [upiId] (P0-06, PAY1).
/// Opens the customer's own UPI app, which does the payment; LoadGo only
/// records that the customer says they paid. [ref] is the booking id.
/// LATER(paid): gateway with automatic confirmation.
Uri upiPayUri({required String upiId, required String payeeName, required int amountPaise, required String note, required String ref}) {
  final rupees = '${amountPaise ~/ 100}.${(amountPaise % 100).toString().padLeft(2, '0')}';
  return Uri(scheme: 'upi', host: 'pay', queryParameters: {
    'pa': upiId.trim(),
    'pn': payeeName.trim().isEmpty ? '${AppInfo.name} driver' : payeeName.trim(),
    'am': rupees,
    'cu': 'INR',
    'tn': note.length > 40 ? note.substring(0, 40) : note,
    'tr': ref,
  });
}

/// Smallest advance a customer can record (Re 1), in paise.
const minAdvancePaise = 100;

/// Advance and balance of a booking (PAY3), in paise.
class AdvanceSummary {
  final int advancePaise;
  final int totalPaise;
  final bool confirmed;
  const AdvanceSummary({required this.advancePaise, required this.totalPaise, required this.confirmed});

  int get balancePaise => totalPaise > advancePaise ? totalPaise - advancePaise : 0;
}

/// Can [advancePaise] be recorded against [totalPaise]? One advance per booking,
/// at least Re 1 and below the total (the rest is the balance on delivery).
bool validAdvance(int advancePaise, int? totalPaise) =>
    advancePaise >= minAdvancePaise && advancePaise <= 100000000 && (totalPaise == null || advancePaise < totalPaise);

/// State of an e-way bill's validity date (DOC4). The date is recorded by
/// the user; checking it against the GST portal needs a provider
/// (LATER(paid)).
enum EwayState { missing, noDate, valid, expiring, expired }

/// Warn when less than this is left.
const ewayWarnWindow = Duration(hours: 12);

({EwayState state, Duration? left}) ewayStatus({required String number, required DateTime? validUntil, required DateTime now, DateTime? expectedDelivery}) {
  if (number.isEmpty) return (state: EwayState.missing, left: null);
  if (validUntil == null) return (state: EwayState.noDate, left: null);
  final left = validUntil.difference(now);
  if (left.isNegative || left == Duration.zero) return (state: EwayState.expired, left: left);
  // The bill must still be valid when the truck is expected to arrive.
  if (left < ewayWarnWindow || (expectedDelivery != null && validUntil.isBefore(expectedDelivery))) return (state: EwayState.expiring, left: left);
  return (state: EwayState.valid, left: left);
}
