import 'lr_model.dart';

/// Which fields each copy of an LR carries (Task 70 and 71). Pure, so the
/// matrix is unit tested. The same function builds the on-screen copy, the PDF,
/// the preview and the share-link snapshot, so what the preview shows is what
/// the receiver gets.
///
/// * Public group: every copy.
/// * Rate group (freight, advance, balance, GST): full copy; consignee copy
///   only when the owner switches "show the rate" on; NEVER the driver copy.
/// * Margin and phones: full copy only. Never driver, never consignee.
/// * Compliance group (goods value, invoice no, GSTINs, e-way bill no):
///   full copy always; consignee copy when the mode is `show`; driver copy
///   when the mode is `show` or the driver holds a valid inspection grant.
class LrVisibility {
  LrVisibility._();

  static Set<String> fields(
    String copy, {
    bool consigneeShowsRate = false,
    String complianceMode = ComplianceMode.hide,
    bool grantValid = false,
  }) {
    final out = <String>{...LrFields.publicKeys};
    switch (copy) {
      case LrCopy.full:
        out.addAll(LrFields.rateKeys);
        out.add(LrFields.marginKey);
        out.addAll(LrFields.phoneKeys);
        out.addAll(LrFields.complianceKeys);
      case LrCopy.consignee:
        if (consigneeShowsRate) out.addAll(LrFields.rateKeys);
        if (complianceMode == ComplianceMode.show) out.addAll(LrFields.complianceKeys);
      case LrCopy.driver:
        if (complianceMode == ComplianceMode.show || grantValid) out.addAll(LrFields.complianceKeys);
    }
    return out;
  }

  /// The rate group (and margin and phones) is never part of the driver copy.
  static bool driverMaySeeRate() => false;

  /// True when the compliance fields are in the copy for this mode.
  static bool showsCompliance(String copy, {String complianceMode = ComplianceMode.hide, bool grantValid = false}) =>
      fields(copy, complianceMode: complianceMode, grantValid: grantValid).contains('ewayBillNo');

  /// Builds the snapshot map of a copy from what was read. Keys outside
  /// [fields] are left out even when the data is there.
  static Map<String, Object> snapshot(
    LrBundle b,
    String copy, {
    bool consigneeShowsRate = false,
    bool grantValid = false,
  }) {
    final allowed = fields(copy, consigneeShowsRate: consigneeShowsRate, complianceMode: b.pub.complianceMode, grantValid: grantValid);
    final all = <String, Object>{
      ...b.pub.publicFields(),
      if (b.details != null) ...b.details!.toMap(),
      if (b.compliance != null) ...{
        ...b.compliance!.toMap(),
        if (b.compliance!.ewayValidUntil != null) 'ewayValidUntil': b.compliance!.ewayValidUntil!.toIso8601String().substring(0, 10),
      },
    };
    return {for (final e in all.entries) if (allowed.contains(e.key)) e.key: e.value};
  }

  /// What the verify QR / verify link shows: no rate and no value.
  static Map<String, Object> verifySnapshot(LrPublic p) {
    final f = p.publicFields();
    return {for (final k in LrFields.verifyKeys) k: f[k]!};
  }

  /// Only the transporter and the customer of the booking make an LR; a driver
  /// and an admin never do. [isTransporterOfBooking] is `fleetOwnerId == uid`.
  static bool canIssue({required bool isCustomerOfBooking, required bool isTransporterOfBooking, required bool isDriver, required bool isAdmin}) {
    if (isDriver || isAdmin) return false;
    return isCustomerOfBooking || isTransporterOfBooking;
  }
}
