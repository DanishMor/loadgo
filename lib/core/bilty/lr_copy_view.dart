import '../l10n/l10n.dart';
import '../widgets/common.dart';
import 'lr_model.dart';

/// One printed line of an LR copy: a label key and the text to show.
class LrRow {
  final String labelKey;
  final String value;
  const LrRow(this.labelKey, this.value);
}

/// Rows in print order for a snapshot made by `LrVisibility.snapshot`. The
/// screen, the preview and the PDF all use this, so they never differ.
List<LrRow> lrRows(Map<String, Object> f) {
  String s(String k) => '${f[k] ?? ''}';
  String paise(String k) => f[k] is num ? formatPaise((f[k] as num).toInt()) : '';
  final rows = <LrRow>[
    LrRow('lrNumber', s('lrNo')),
    if (f.containsKey('version')) LrRow('blVersionWord', '${(f['version'] as num).toInt()}'),
    if (f.containsKey('date')) LrRow('date', s('date')),
    if (f.containsKey('consignorName')) LrRow('consignor', s('consignorName')),
    if (f.containsKey('consigneeName')) LrRow('consignee', s('consigneeName')),
    LrRow('route', s('route')),
    if (f.containsKey('goods')) LrRow('goods', s('goods')),
    if (f.containsKey('packages') && (f['packages'] as num) > 0) LrRow('blPackages', s('packages')),
    if (f.containsKey('weightTons')) LrRow('weightTons', formatNum(f['weightTons'] as num)),
    if (f.containsKey('vehicleNumber') && s('vehicleNumber').isNotEmpty) LrRow('vehicle', s('vehicleNumber')),
    if (f.containsKey('driverName') && s('driverName').isNotEmpty) LrRow('driver', s('driverName')),
    if (f.containsKey('freightPaise')) LrRow('blFreight', paise('freightPaise')),
    if (f.containsKey('advancePaise')) LrRow('blAdvance', paise('advancePaise')),
    if (f.containsKey('balancePaise')) LrRow('blBalance', paise('balancePaise')),
    if (f.containsKey('gstPaise') && (f['gstPaise'] as num) > 0) LrRow('blGst', paise('gstPaise')),
    if (f.containsKey('marginPaise')) LrRow('blMargin', paise('marginPaise')),
    if (f.containsKey('goodsValuePaise') && (f['goodsValuePaise'] as num) > 0) LrRow('blGoodsValue', paise('goodsValuePaise')),
    if (s('invoiceNo').isNotEmpty) LrRow('blInvoiceNo', s('invoiceNo')),
    if (s('consignorGstin').isNotEmpty) LrRow('blConsignorGstin', s('consignorGstin')),
    if (s('consigneeGstin').isNotEmpty) LrRow('blConsigneeGstin', s('consigneeGstin')),
    if (s('ewayBillNo').isNotEmpty) LrRow('blEway', s('ewayBillNo')),
    if (s('ewayValidUntil').isNotEmpty) LrRow('blPickDate', s('ewayValidUntil')),
    if (s('consignorPhone').isNotEmpty) LrRow('blConsignorPhone', s('consignorPhone')),
    if (s('consigneePhone').isNotEmpty) LrRow('blConsigneePhone', s('consigneePhone')),
  ];
  return rows;
}

/// Heading key for the LR of [issuerRole].
String lrHeadingKey(String issuerRole) => issuerRole == LrIssuerRole.customer ? 'blTitleSlip' : 'blTitleLr';

String lrCopyKey(String copy) => switch (copy) {
      LrCopy.driver => 'blCopyDriver',
      LrCopy.consignee => 'blCopyConsignee',
      _ => 'blCopyFull',
    };

String lrStatusKey(String status) => switch (status) {
      LrStatus.superseded => 'blStatusSuperseded',
      LrStatus.cancelled => 'blCancelled',
      _ => 'blStatusIssued',
    };

/// Text outside a widget tree (the PDF): same lookup as [tr] with a language.
String trLang(String key, AppLanguage language) => T.get(key, language);
