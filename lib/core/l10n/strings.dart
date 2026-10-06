/// Per-feature translation tables, merged into `T.data` in core/l10n/l10n.dart.
///
/// Each value is a 12-item list in `AppLanguage` order:
/// en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur.
library;

import 'badge_strings.dart';
import 'booking_type_strings.dart';
import 'consent_strings.dart';
import 'identity_strings.dart';
import 'admin_strings.dart';
import 'auth_strings.dart';
import 'chat_strings.dart';
import 'driver_extras_strings.dart';
import 'enterprise_strings.dart';
import 'evidence_strings.dart';
import 'load_strings.dart';
import 'match_strings.dart';
import 'offer_strings.dart';
import 'offers_strings.dart';
import 'ops_strings.dart';
import 'payment_strings.dart';
import 'pricing_strings.dart';
import 'profile_strings.dart';
import 'reminder_strings.dart';
import 'risk_strings.dart';
import 'schedule_strings.dart';
import 'security_strings.dart';
import 'settings_strings.dart';
import 'support_strings.dart';
import 'trip_strings.dart';
import 'truck_board_strings.dart';
import 'fleet_strings.dart';
import 'business_team_strings.dart';
import 'repeat_strings.dart';
import 'rating_strings.dart';
import 'dispute_strings.dart';
import 'invoice_strings.dart';
import 'txn_strings.dart';
import 'doc_expiry_strings.dart';
import 'search_strings.dart';
import 'eta_strings.dart';
import 'notif_center_strings.dart';
import 'limit_strings.dart';
import 'admin_user_strings.dart';
import 'trend_strings.dart';
import 'trip_watch_strings.dart';
import 'vehicle_strings.dart';
import 'help_strings.dart';

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
  reminderStrings,
  profileFieldStrings,
  badgeStrings,
  opsStrings,
  evidenceStrings,
  securityStrings,
  tripWatchStrings,
  scheduleStrings,
  truckBoardStrings,
  fleetStrings,
  businessTeamStrings,
  repeatStrings,
  ratingStrings,
  disputeStrings,
  invoiceStrings,
  txnStrings,
  docExpiryStrings,
  searchStrings,
  etaStrings,
  notifCenterStrings,
  limitStrings,
  adminUserStrings,
  trendStrings,
  adminStrings,
  matchStrings,
  settingsStrings,
  enterpriseStrings,
  helpStrings,
];

final Map<String, List<String>> extraStrings = {
  for (final table in stringTables) ...table,
};
