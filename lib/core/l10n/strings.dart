/// Per-feature translation tables, merged into `T.data` in core/l10n/l10n.dart.
///
/// Each value is a 12-item list in `AppLanguage` order:
/// en, hi, hinglish, kn, ta, te, mr, gu, bn, pa, ks, ur.
library;

import 'private_comm_strings.dart';
import 'transporter_strings.dart';
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
import 'bilty_strings.dart';
import 'a11y_strings.dart';
import 'tour_strings.dart';
import 'notif_group_strings.dart';
import 'wizard_strings.dart';
import 'discard_strings.dart';
import 'faq_role_strings.dart';
import 'announcement_strings.dart';
import 'pilot_funnel_strings.dart';
import 'invite_strings.dart';
import 'waitlist_strings.dart';
import 'pilot_control_strings.dart';
import 'dispatch_strings.dart';
import 'pilot_report_strings.dart';
import 'pilot_cohort_strings.dart';
import 'survey_strings.dart';
import 'payment_aging_strings.dart';
import 'admin_search_strings.dart';
import 'user_overview_strings.dart';
import 'config_editor_strings.dart';
import 'admin_alerts_strings.dart';
import 'draft_strings.dart';
import 'smart_defaults_strings.dart';
import 'fare_explain_strings.dart';
import 'delay_strings.dart';
import 'address_book_strings.dart';
import 'delivered_strings.dart';
import 'onboarding_strings.dart';
import 'driver_today_strings.dart';
import 'sync_strings.dart';
import 'bid_assistant_strings.dart';
import 'wallet_clarity_strings.dart';
import 'safety_checks_strings.dart';
import 'transporter_onboarding_strings.dart';
import 'transporter_board_strings.dart';
import 'bulk_bid_strings.dart';
import 'lr_register_strings.dart';
import 'inspection_polish_strings.dart';
import 'chat_quick_strings.dart';
import 'admin_list_strings.dart';
import 'statement_strings.dart';
import 'evidence_timeline_strings.dart';
import 'inspection_strings.dart';
import 'vehicle_strings.dart';
import 'help_strings.dart';
import 'ui_strings.dart';
import 'fleet_extra_strings.dart';
import 'booking_extra_strings.dart';
import 'profile_extra_strings.dart';
import 'business_role_strings.dart';
import 'risk_extra_strings.dart';
import 'network_strings.dart';
import 'pay_extra_strings.dart';
import 'trip_alert_strings.dart';

import 'app_control_strings.dart';
import 'admin_tools_strings.dart';
import 'demo_strings.dart';
import 'permission_strings.dart';
import 'friendly_error_strings.dart';
import 'abuse_strings.dart';
import 'feature_strings.dart';
import 'supply_demand_strings.dart';
import 'unit_economics_strings.dart';
import 'payment_timeline_strings.dart';
import 'problem_report_strings.dart';
import 'assistant_strings.dart';
import 'earn_history_strings.dart';
import 'feedback_cancel_strings.dart';
import 'global_search_strings.dart';
import 'offers_switch_strings.dart';
import 'share_nav_strings.dart';
import 'simple_mode_strings.dart';
import 'surge_strings.dart';
import 'trip_cost_strings.dart';

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
  biltyStrings,
  inspectionStrings,
  a11yStrings,
  tourStrings,
  notifGroupStrings,
  wizardStrings,
  discardStrings,
  faqRoleStrings,
  announcementStrings,
  pilotFunnelStrings,
  inviteStrings,
  waitlistStrings,
  pilotControlStrings,
  dispatchStrings,
  pilotReportStrings,
  pilotCohortStrings,
  surveyStrings,
  paymentAgingStrings,
  adminSearchStrings,
  userOverviewStrings,
  configEditorStrings,
  adminAlertsStrings,
  draftStrings,
  smartDefaultsStrings,
  fareExplainStrings,
  delayStrings,
  addressBookStrings,
  deliveredStrings,
  onboardingStrings,
  driverTodayStrings,
  syncStrings,
  bidAssistantStrings,
  walletClarityStrings,
  safetyChecksStrings,
  transporterOnboardingStrings,
  transporterBoardStrings,
  bulkBidStrings,
  lrRegisterStrings,
  inspectionPolishStrings,
  chatQuickStrings,
  adminListStrings,
  statementStrings,
  evidenceTimelineStrings,
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
  uiStrings,
  fleetExtraStrings,
  bookingExtraStrings,
  profileExtraStrings,
  networkStrings,
  tripAlertStrings,
  payExtraStrings,
  businessRoleStrings,
  riskExtraStrings,
  offersSwitchStrings,
  appControlStrings,
  shareNavStrings,
  surgeStrings,
  tripCostStrings,
  simpleModeStrings,
  assistantStrings,
  earnHistoryStrings,
  feedbackCancelStrings,
  globalSearchStrings,
  adminToolsStrings,
  demoStrings,
  permissionStrings,
  friendlyErrorStrings,
  abuseStrings,
  featureStrings,
  supplyDemandStrings,
  unitEconomicsStrings,
  paymentTimelineStrings,
  problemReportStrings,
  transporterStrings,
  privateCommStrings,
];

final Map<String, List<String>> extraStrings = {
  for (final table in stringTables) ...table,
};
