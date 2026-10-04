/// Per-feature translation tables, merged into `T.data` in main.dart.
///
/// Each value is a 12-item list in `AppLanguage` order:
/// en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur.
library;

import 'auth_strings.dart';
import 'load_strings.dart';
import 'pricing_strings.dart';
import 'vehicle_strings.dart';

const List<Map<String, List<String>>> stringTables = [
  authStrings,
  vehicleStrings,
  pricingStrings,
  loadStrings,
];

final Map<String, List<String>> extraStrings = {
  for (final table in stringTables) ...table,
};
