// G14: plain GST and e-way bill rules as pure functions, no network. They check and explain; nothing is
// filed. The e-way bill rules (value threshold, validity per distance) change from time to time: the numbers
// below are the usual ones and MUST be confirmed with a CA before the app says anything legal
// (docs/GST_EWAY.md). Money is integer paise.

/// GST state codes (the first two digits of a GSTIN).
const Map<String, String> gstStates = {
  '01': 'Jammu and Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh', '05': 'Uttarakhand',
  '06': 'Haryana', '07': 'Delhi', '08': 'Rajasthan', '09': 'Uttar Pradesh', '10': 'Bihar', '11': 'Sikkim',
  '12': 'Arunachal Pradesh', '13': 'Nagaland', '14': 'Manipur', '15': 'Mizoram', '16': 'Tripura', '17': 'Meghalaya',
  '18': 'Assam', '19': 'West Bengal', '20': 'Jharkhand', '21': 'Odisha', '22': 'Chhattisgarh', '23': 'Madhya Pradesh',
  '24': 'Gujarat', '26': 'Dadra and Nagar Haveli and Daman and Diu', '27': 'Maharashtra', '29': 'Karnataka', '30': 'Goa',
  '31': 'Lakshadweep', '32': 'Kerala', '33': 'Tamil Nadu', '34': 'Puducherry', '35': 'Andaman and Nicobar Islands',
  '36': 'Telangana', '37': 'Andhra Pradesh', '38': 'Ladakh',
};

/// State code of a GSTIN, or null when the text does not start with a known code.
String? gstinStateCode(String gstin) {
  final g = gstin.trim().toUpperCase();
  if (g.length < 2) return null;
  final c = g.substring(0, 2);
  return gstStates.containsKey(c) ? c : null;
}

String? gstinStateName(String gstin) {
  final c = gstinStateCode(gstin);
  return c == null ? null : gstStates[c];
}

enum SupplyKind { intraState, interState, unknown }

/// Same state for seller and place of supply: CGST + SGST. Different: IGST. Not enough information: unknown
/// (the invoice then keeps showing the CGST + SGST split as before).
SupplyKind supplyKind({required String sellerGstin, String? placeOfSupplyState}) {
  final seller = gstinStateName(sellerGstin);
  if (seller == null || placeOfSupplyState == null || placeOfSupplyState.trim().isEmpty) return SupplyKind.unknown;
  return seller.toLowerCase() == placeOfSupplyState.trim().toLowerCase() ? SupplyKind.intraState : SupplyKind.interState;
}

/// An e-way bill number is 12 digits.
bool isValidEwayBillNo(String s) => RegExp(r'^\d{12}$').hasMatch(s.trim());

/// A vehicle number for an e-way bill: letters and digits only, 7 to 12 characters.
bool isValidEwayVehicle(String s) => RegExp(r'^[A-Z0-9]{7,12}$').hasMatch(s.toUpperCase().replaceAll(RegExp(r'[\s-]'), ''));

/// Usual limit: an e-way bill is needed when the goods are worth more than this (paise). Config can change it.
const int ewayThresholdPaise = 5000000; // 50,000 rupees

bool ewayRequired(int goodsValuePaise, {int thresholdPaise = ewayThresholdPaise}) => goodsValuePaise > thresholdPaise;

/// Days of validity for a distance: one day for each 200 km or part of it (one day each 20 km for over-dimensional
/// cargo), at least one day.
int ewayValidityDays(int distanceKm, {bool overDimensional = false}) {
  if (distanceKm <= 0) return 1;
  final per = overDimensional ? 20 : 200;
  return (distanceKm + per - 1) ~/ per;
}

/// The bill ends at the end of the last valid day (India time), counted from the day it was made.
DateTime ewayValidUntil(DateTime generatedAtIst, int distanceKm, {bool overDimensional = false}) {
  final days = ewayValidityDays(distanceKm, overDimensional: overDimensional);
  final d = DateTime(generatedAtIst.year, generatedAtIst.month, generatedAtIst.day).add(Duration(days: days - 1));
  return DateTime(d.year, d.month, d.day, 23, 59, 59);
}

/// Everything wrong with the details of an e-way bill request, as codes (empty when fine).
List<String> ewayRequestProblems({
  required String sellerGstin,
  required String buyerGstin,
  required String vehicleNumber,
  required int distanceKm,
  required int goodsValuePaise,
  String hsn = '',
}) {
  final problems = <String>[];
  if (gstinStateCode(sellerGstin) == null || sellerGstin.trim().length != 15) problems.add('sellerGstin');
  if (buyerGstin.trim().isNotEmpty && (gstinStateCode(buyerGstin) == null || buyerGstin.trim().length != 15)) problems.add('buyerGstin');
  if (!isValidEwayVehicle(vehicleNumber)) problems.add('vehicle');
  if (distanceKm <= 0 || distanceKm > 4000) problems.add('distance');
  if (goodsValuePaise <= 0) problems.add('value');
  if (hsn.isNotEmpty && !RegExp(r'^\d{4,8}$').hasMatch(hsn)) problems.add('hsn');
  return problems;
}
