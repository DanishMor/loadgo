/// Per-feature translation tables, merged into `T.data` in main.dart.
///
/// Each value is a 12-item list in `AppLanguage` order:
/// en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur.
library;

import 'auth_strings.dart';
import 'chat_strings.dart';
import 'load_strings.dart';
import 'offer_strings.dart';
import 'payment_strings.dart';
import 'pricing_strings.dart';
import 'risk_strings.dart';
import 'support_strings.dart';
import 'trip_strings.dart';
import 'vehicle_strings.dart';

const List<Map<String, List<String>>> stringTables = [
  authStrings,
  vehicleStrings,
  pricingStrings,
  loadStrings,
  offerStrings,
  tripStrings,
  chatStrings,
  supportStrings,
  paymentStrings,
  riskStrings,
];

final Map<String, List<String>> extraStrings = {
  for (final table in stringTables) ...table,
};
