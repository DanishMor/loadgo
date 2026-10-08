/// An amount in words, Indian style (lakh, crore): `Rupees One Lakh Twenty
/// Three Thousand Four Hundred Fifty Six and Seventy Paise Only`. Integer
/// paise in, no floating point (MASTER-5 Task 36, used on the invoice).
String amountInWords(int paise) {
  if (paise < 0) return 'Minus ${amountInWords(-paise)}';
  final rupees = paise ~/ 100;
  final p = paise % 100;
  final r = rupees == 0 ? 'Zero' : _words(rupees);
  final buf = StringBuffer('Rupees $r');
  if (p > 0) buf.write(' and ${_words(p)} Paise');
  buf.write(' Only');
  return buf.toString();
}

const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen',
  'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

String _below100(int n) => n < 20 ? _ones[n] : (n % 10 == 0 ? _tens[n ~/ 10] : '${_tens[n ~/ 10]} ${_ones[n % 10]}');

String _below1000(int n) {
  final h = n ~/ 100, rest = n % 100;
  return [if (h > 0) '${_ones[h]} Hundred', if (rest > 0) _below100(rest)].join(' ');
}

String _words(int n) {
  final parts = <String>[];
  final crore = n ~/ 10000000;
  var rest = n % 10000000;
  final lakh = rest ~/ 100000;
  rest %= 100000;
  final thousand = rest ~/ 1000;
  rest %= 1000;
  if (crore > 0) parts.add('${_words(crore)} Crore');
  if (lakh > 0) parts.add('${_below100(lakh)} Lakh');
  if (thousand > 0) parts.add('${_below100(thousand)} Thousand');
  if (rest > 0) parts.add(_below1000(rest));
  return parts.join(' ');
}
