import 'kyc_validators.dart';

/// Reasons an automatic check gives for sending a driver profile to manual
/// review (R7, R12). Pure: reads the `users/{uid}` map only. Nothing here
/// proves a document is real (LATER(paid): source verification).
class KycProblem {
  KycProblem._();
  static const licenceExpired = 'licenceExpired';
  static const licenceFormat = 'licenceFormat';
  static const panFormat = 'panFormat';
  static const rcFormat = 'rcFormat';
  static const aadhaarFormat = 'aadhaarFormat';
  static const nameMissing = 'nameMissing';
  static const editedAfterReview = 'editedAfterReview';
  static const adminFlag = 'adminFlag';
}

DateTime? _date(Object? v) {
  if (v is DateTime) return v;
  try {
    final d = (v as dynamic)?.toDate();
    return d is DateTime ? d : null;
  } catch (_) {
    return null;
  }
}

/// Empty list = nothing found. Order is stable (shown as chips).
List<String> kycAutoCheck(Map<String, dynamic> user, {DateTime? now}) {
  final out = <String>[];
  final k = (user['driverKyc'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  if (k.isNotEmpty) {
    if (!isValidDlNumber(k['dlNumber']?.toString() ?? '')) out.add(KycProblem.licenceFormat);
    if (!isDlExpiryValid(_date(k['dlExpiry']), now ?? DateTime.now())) out.add(KycProblem.licenceExpired);
    if (!isValidVehicleNumber(k['rcNumber']?.toString() ?? '')) out.add(KycProblem.rcFormat);
    if (!isValidPan(k['pan']?.toString() ?? '')) out.add(KycProblem.panFormat);
    if (!isValidAadhaarLast4(k['aadhaarLast4']?.toString() ?? '')) out.add(KycProblem.aadhaarFormat);
  }
  if ((user['driverName']?.toString() ?? '').trim().length < 2) out.add(KycProblem.nameMissing);
  // A licence or RC edited after the admin last reviewed it needs another look.
  final edited = _date(user['kycEditedAt']);
  final reviewed = _date((user['verificationMeta'] as Map?)?['at']);
  if (edited != null && reviewed != null && edited.isAfter(reviewed)) out.add(KycProblem.editedAfterReview);
  if (user['reviewFlag'] is Map) out.add(KycProblem.adminFlag);
  return out;
}
