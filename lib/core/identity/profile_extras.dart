import 'masking.dart';

/// What kind of business a customer or fleet account is (A5). Stored in
/// `users.businessType`; the rules accept only these five.
class BusinessType {
  BusinessType._();
  static const shipper = 'shipper';
  static const importer = 'importer';
  static const exporter = 'exporter';
  static const trader = 'trader';
  static const transporter = 'transporter';
  static const all = [shipper, importer, exporter, trader, transporter];
}

final _upi = RegExp(r'^[a-zA-Z0-9._-]{2,40}@[a-zA-Z]{2,20}$');

/// Format only (`name@bank`). LATER(paid): confirm the id with a payment partner.
bool isValidUpiId(String s) => _upi.hasMatch(s.trim());

/// `ravi.kumar@okaxis` -> `ra••••••••@okaxis`.
String maskUpiId(String? upi) {
  final v = (upi ?? '').trim();
  final at = v.indexOf('@');
  if (at < 0) return maskId(v);
  return '${maskId(v.substring(0, at))}${v.substring(at)}';
}

/// Address shown to admins and in lists: first words only.
String maskAddress(String? a, {int keep = 14}) {
  final v = (a ?? '').trim();
  return v.length <= keep ? v : '${v.substring(0, keep).trimRight()}…';
}

/// The optional profile fields added in Task 32, read from `users/{uid}`.
class ProfileExtras {
  final String currentAddress;
  final String permanentAddress;
  final String? businessType;
  final String upiId;
  final String holder;

  const ProfileExtras({this.currentAddress = '', this.permanentAddress = '', this.businessType, this.upiId = '', this.holder = ''});

  factory ProfileExtras.fromProfile(Map<String, dynamic> p) {
    final a = (p['addresses'] as Map?) ?? const {};
    final pay = (p['payoutProfile'] as Map?) ?? const {};
    final t = p['businessType'] as String?;
    return ProfileExtras(
      currentAddress: a['current'] as String? ?? '',
      permanentAddress: a['permanent'] as String? ?? '',
      businessType: BusinessType.all.contains(t) ? t : null,
      upiId: pay['upiId'] as String? ?? '',
      holder: pay['holder'] as String? ?? '',
    );
  }
}
