/// Why a customer or a driver cancelled. The code is stored (`cancelReason`
/// on a cancelled load, `cancellation.reason` on a cancelled booking); the
/// text comes from the translation key `cr_<code>`. firestore.rules keeps the
/// same lists.
class CancelReasons {
  CancelReasons._();

  static const customer = ['found_other', 'plan_changed', 'price_high', 'driver_delay', 'wrong_details', 'other'];
  static const driver = ['vehicle_problem', 'load_mismatch', 'customer_unreachable', 'personal', 'price_low', 'other'];

  /// Largest declared goods value: 10 crore rupees, in paise.
  static const maxDeclaredValuePaise = 10000000000;

  /// Codes for who is cancelling: `customer` or `driver`.
  static List<String> forRole(String by) => by == 'driver' ? driver : customer;

  /// Null (no reason given) is valid; a code must belong to [by].
  static bool valid(String by, String? code) => code == null || forRole(by).contains(code);

  static String labelKey(String code) => 'cr_$code';
}
