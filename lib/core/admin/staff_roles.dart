/// Staff roles of the admin panel (BE7). `admins/{uid}.role` holds one; a
/// MISSING value means [StaffRole.superAdmin] (like the rules: `get('role', 'super')`),
/// a value that is not one of [all] means [StaffRole.none]: no area, same as the rules (Z21, BUG_REPORT H-7).
/// The rules (`adminIn([...])`) decide who may write what; this table only hides what a role cannot use.
class StaffRole {
  StaffRole._();
  static const superAdmin = 'super';
  static const support = 'support';
  static const verifier = 'verifier';
  static const ops = 'ops';
  static const finance = 'finance';
  static const all = [superAdmin, support, verifier, ops, finance];

  /// A role the panel does not know: it opens nothing.
  static const none = 'none';

  static String normalise(Object? v) => v == null ? superAdmin : (all.contains(v) ? v as String : none);
}

/// Dashboard entry key (`admin_<key>`) -> roles that work on it. Every staff
/// role may read everything the panel lists; these are the ones that can act.
const Map<String, List<String>> staffAreas = {
  'adminAnalytics': StaffRole.all,
  'adminUsers': StaffRole.all,
  'driverVerification': [StaffRole.superAdmin, StaffRole.verifier],
  'adminVehicles': [StaffRole.superAdmin, StaffRole.verifier],
  'adminLoads': StaffRole.all,
  'adminBookings': StaffRole.all,
  'adminTickets': [StaffRole.superAdmin, StaffRole.support],
  'adminSos': [StaffRole.superAdmin, StaffRole.support, StaffRole.ops],
  'adminReports': [StaffRole.superAdmin, StaffRole.support, StaffRole.ops],
  'pcAdminViolations': [StaffRole.superAdmin, StaffRole.support, StaffRole.ops],
  'adminSignals': [StaffRole.superAdmin, StaffRole.ops, StaffRole.verifier],
  'adminFraudCases': [StaffRole.superAdmin, StaffRole.ops],
  'adminDisputes': [StaffRole.superAdmin, StaffRole.support],
  'adminRatingFlags': [StaffRole.superAdmin, StaffRole.support, StaffRole.ops],
  'adminRatingBurst': [StaffRole.superAdmin, StaffRole.support, StaffRole.ops],
  'adminAssistant': [StaffRole.superAdmin, StaffRole.support],
  'adminHealth': [StaffRole.superAdmin, StaffRole.ops],
  'adminTemplates': [StaffRole.superAdmin],
  'adminDemo': [StaffRole.superAdmin],
  'adminFeatures': [StaffRole.superAdmin],
  'adminUnitEconomics': [StaffRole.superAdmin, StaffRole.finance],
  'adminSupplyDemand': [StaffRole.superAdmin, StaffRole.ops],
  'adminPilotControl': [StaffRole.superAdmin, StaffRole.ops, StaffRole.support],
  'adminAppeals': [StaffRole.superAdmin, StaffRole.support, StaffRole.ops],
  'adminAlerts': StaffRole.all,
  'adminSearch': StaffRole.all,
  'adminPayAging': [StaffRole.superAdmin, StaffRole.ops, StaffRole.support, StaffRole.finance],
  'adminSurveys': [StaffRole.superAdmin, StaffRole.ops],
  'adminCohorts': [StaffRole.superAdmin, StaffRole.ops],
  'adminPilotReport': [StaffRole.superAdmin, StaffRole.ops],
  'adminDispatch': [StaffRole.superAdmin, StaffRole.ops],
  'adminDispatchMonitor': [StaffRole.superAdmin, StaffRole.ops],
  'adminWaitlist': [StaffRole.superAdmin, StaffRole.ops],
  'adminInvites': [StaffRole.superAdmin, StaffRole.ops],
  'adminPilotFunnel': [StaffRole.superAdmin, StaffRole.ops],
  'adminFeedback': [StaffRole.superAdmin, StaffRole.support],
  'flaggedUsers': [StaffRole.superAdmin, StaffRole.ops],
  'adminDeletionRequests': [StaffRole.superAdmin, StaffRole.support],
  'adminAudit': [StaffRole.superAdmin, StaffRole.ops],
  'adminDriverRewards': [StaffRole.superAdmin, StaffRole.finance],
  'adminPayouts': [StaffRole.superAdmin, StaffRole.finance],
  'adminFinance': [StaffRole.superAdmin, StaffRole.finance],
  'adminBroadcast': [StaffRole.superAdmin, StaffRole.support, StaffRole.ops],
  'adminOffers': [StaffRole.superAdmin],
  'adminConfig': [StaffRole.superAdmin],
};

bool staffCan(String? role, String area) => staffAreas[area]?.contains(StaffRole.normalise(role)) ?? false;
