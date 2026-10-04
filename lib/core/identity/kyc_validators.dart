// Format checks for driver onboarding documents. Nothing here proves a
// document is real: LATER(paid) verify with Parivahan / NSDL / UIDAI partners.

final _dl = RegExp(r'^[A-Z]{2}[0-9]{2}[0-9]{4}[0-9]{7}$');
final _vehicle = RegExp(r'^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{4}$');
final _pan = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
final _last4 = RegExp(r'^[0-9]{4}$');

/// Upper-case, no spaces or dashes: the form identity checks compare.
String normaliseDocNumber(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Indian driving licence: state code, RTO code, year, 7 digit serial.
bool isValidDlNumber(String s) => _dl.hasMatch(normaliseDocNumber(s));

/// Registration plate such as MH12AB1234 or DL1CAB1234.
bool isValidVehicleNumber(String s) => _vehicle.hasMatch(normaliseDocNumber(s));

bool isValidPan(String s) => _pan.hasMatch(normaliseDocNumber(s));

/// Aadhaar is only ever collected as its last four digits.
bool isValidAadhaarLast4(String s) => _last4.hasMatch(s.trim());

/// Licence must still be valid today (compared by date, not time).
bool isDlExpiryValid(DateTime? expiry, DateTime now) {
  if (expiry == null) return false;
  final today = DateTime(now.year, now.month, now.day);
  return !DateTime(expiry.year, expiry.month, expiry.day).isBefore(today);
}

/// What the driver typed on the onboarding screen.
class DriverKyc {
  final String dlNumber;
  final DateTime dlExpiry;
  final String rcNumber;
  final String aadhaarLast4;
  final String pan;

  DriverKyc({
    required String dlNumber,
    required this.dlExpiry,
    required String rcNumber,
    required String aadhaarLast4,
    required String pan,
  })  : dlNumber = normaliseDocNumber(dlNumber),
        rcNumber = normaliseDocNumber(rcNumber),
        aadhaarLast4 = aadhaarLast4.trim(),
        pan = normaliseDocNumber(pan);

  /// Firestore form. Only the Aadhaar last four digits are ever stored.
  Map<String, Object?> toMap() => {
        'dlNumber': dlNumber,
        'dlExpiry': dlExpiry,
        'rcNumber': rcNumber,
        'aadhaarLast4': aadhaarLast4,
        'pan': pan,
      };
}
