/// Per-feature translation tables, merged into `T.data` in core/l10n/l10n.dart.
///
/// Each value is a 12-item list in `AppLanguage` order:
/// en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur.
library;

import 'booking_type_strings.dart';
import 'consent_strings.dart';
import 'identity_strings.dart';
import 'admin_strings.dart';
import 'auth_strings.dart';
import 'chat_strings.dart';
import 'driver_extras_strings.dart';
import 'enterprise_strings.dart';
import 'load_strings.dart';
import 'match_strings.dart';
import 'offer_strings.dart';
import 'offers_strings.dart';
import 'payment_strings.dart';
import 'pricing_strings.dart';
import 'risk_strings.dart';
import 'settings_strings.dart';
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
  identityStrings,
  consentStrings,
  bookingTypeStrings,
  customerOffersStrings,
  driverExtrasStrings,
  adminStrings,
  matchStrings,
  settingsStrings,
  enterpriseStrings,
];

final Map<String, List<String>> extraStrings = {
  for (final table in stringTables) ...table,
};
