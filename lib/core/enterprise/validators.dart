// Format checks for business and trade identifiers. Nothing here proves a
// number is real: LATER(paid) verify GSTIN with the GST portal / a KYC API.

final _gstin = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

/// GSTIN: 15 characters, state code, PAN, entity number, 'Z', check char.
/// Format only (the check character is not verified).
bool isValidGstinFormat(String s) => _gstin.hasMatch(s.trim().toUpperCase());

String normaliseGstin(String s) => s.trim().toUpperCase();

final _containerFormat = RegExp(r'^[A-Z]{4}[0-9]{7}$');

/// ISO 6346 container number: 3-letter owner code + category letter + 6
/// digit serial + check digit, e.g. CSQU3054383.
bool isValidContainerNumber(String s) {
  final c = s.trim().toUpperCase();
  if (!_containerFormat.hasMatch(c)) return false;
  return _containerCheckDigit(c.substring(0, 10)) == int.parse(c[10]);
}

String normaliseContainer(String s) => s.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

int _containerCheckDigit(String first10) {
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    final ch = first10.codeUnitAt(i);
    final value = ch >= 65 ? _letterValue(ch - 65) : ch - 48;
    sum += value * (1 << i);
  }
  return sum % 11 % 10;
}

/// A=10, B=12, C=13 ... letter values skip multiples of 11 (11, 22, 33).
int _letterValue(int index) {
  var v = 10 + index;
  v += (v - 1) ~/ 11; // skip 11, 22, 33
  return v;
}

final _seal = RegExp(r'^[A-Za-z0-9-]{1,20}$');

/// Customs / shipping-line seal numbers are short alphanumerics.
bool isValidSealNumber(String s) => _seal.hasMatch(s.trim());
