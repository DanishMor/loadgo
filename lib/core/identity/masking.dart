/// Shows only the edges of an identifier: `ABCDE1234F` -> `AB••••••4F`.
/// Values of 4 characters or fewer are hidden completely.
String maskId(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return '';
  if (v.length <= 4) return '•' * v.length;
  return '${v.substring(0, 2)}${'•' * (v.length - 4)}${v.substring(v.length - 2)}';
}

/// Aadhaar is only ever the last four digits: `•••• •••• 4321`.
String maskAadhaarLast4(String? last4) {
  final v = (last4 ?? '').trim();
  return v.isEmpty ? '' : '•••• •••• $v';
}
