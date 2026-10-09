import '../errors/error_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../widgets/common.dart';
import 'lr_model.dart';
import 'lr_service.dart';

int _paise(String s) {
  final n = double.tryParse(s.trim());
  return (n == null || n < 0) ? 0 : (n * 100).round();
}

String _rupees(int paise) => paise == 0 ? '' : (paise % 100 == 0 ? '${paise ~/ 100}' : (paise / 100).toStringAsFixed(2));

/// Create an LR, or edit one (which saves a new version). The margin field is
/// only for the transporter; the e-way bill is a record, nothing is filed.
class LrFormScreen extends StatefulWidget {
  final Booking booking;
  final String issuerRole;

  /// Set when editing: the current version and what it holds.
  final LrBundle? editing;
  const LrFormScreen({super.key, required this.booking, required this.issuerRole, this.editing});

  @override
  State<LrFormScreen> createState() => _LrFormScreenState();
}

class _LrFormScreenState extends State<LrFormScreen> {
  late final LrDraft _start = widget.editing == null
      ? LrDraft.fromBooking(widget.booking, issuerRole: widget.issuerRole)
      : LrDraft(
          consignorName: widget.editing!.pub.consignorName,
          consigneeName: widget.editing!.pub.consigneeName,
          goods: widget.editing!.pub.goods,
          packages: widget.editing!.pub.packages,
          weightTons: widget.editing!.pub.weightTons,
          freightPaise: widget.editing!.details?.freightPaise ?? 0,
          advancePaise: widget.editing!.details?.advancePaise ?? 0,
          marginPaise: widget.editing!.details?.marginPaise ?? 0,
          gstPaise: widget.editing!.details?.gstPaise ?? 0,
          consignorPhone: widget.editing!.details?.consignorPhone ?? '',
          consigneePhone: widget.editing!.details?.consigneePhone ?? '',
          goodsValuePaise: widget.editing!.compliance?.goodsValuePaise ?? 0,
          invoiceNo: widget.editing!.compliance?.invoiceNo ?? '',
          consignorGstin: widget.editing!.compliance?.consignorGstin ?? '',
          consigneeGstin: widget.editing!.compliance?.consigneeGstin ?? '',
          ewayBillNo: widget.editing!.compliance?.ewayBillNo ?? '',
          ewayValidUntil: widget.editing!.compliance?.ewayValidUntil,
          complianceMode: widget.editing!.pub.complianceMode,
        );

  late final _consignor = TextEditingController(text: _start.consignorName);
  late final _consignee = TextEditingController(text: _start.consigneeName);
  late final _goods = TextEditingController(text: _start.goods);
  late final _packages = TextEditingController(text: _start.packages == 0 ? '' : '${_start.packages}');
  late final _weight = TextEditingController(text: _start.weightTons == 0 ? '' : formatNum(_start.weightTons));
  late final _freight = TextEditingController(text: _rupees(_start.freightPaise));
  late final _advance = TextEditingController(text: _rupees(_start.advancePaise));
  late final _margin = TextEditingController(text: _rupees(_start.marginPaise));
  late final _gst = TextEditingController(text: _rupees(_start.gstPaise));
  late final _consignorPhone = TextEditingController(text: _start.consignorPhone);
  late final _consigneePhone = TextEditingController(text: _start.consigneePhone);
  late final _goodsValue = TextEditingController(text: _rupees(_start.goodsValuePaise));
  late final _invoice = TextEditingController(text: _start.invoiceNo);
  late final _consignorGstin = TextEditingController(text: _start.consignorGstin);
  late final _consigneeGstin = TextEditingController(text: _start.consigneeGstin);
  late final _eway = TextEditingController(text: _start.ewayBillNo);
  late DateTime? _ewayUntil = _start.ewayValidUntil;
  late String _mode = _start.complianceMode;
  bool _saving = false;

  bool get _transporter => widget.issuerRole == LrIssuerRole.transporter;

  @override
  void dispose() {
    for (final c in [_consignor, _consignee, _goods, _packages, _weight, _freight, _advance, _margin, _gst, _consignorPhone, _consigneePhone, _goodsValue, _invoice, _consignorGstin, _consigneeGstin, _eway]) {
      c.dispose();
    }
    super.dispose();
  }

  LrDraft _draft() => LrDraft(
        consignorName: _consignor.text,
        consigneeName: _consignee.text,
        goods: _goods.text,
        packages: int.tryParse(_packages.text.trim()) ?? 0,
        weightTons: double.tryParse(_weight.text.trim()) ?? 0,
        freightPaise: _paise(_freight.text),
        advancePaise: _paise(_advance.text),
        marginPaise: _transporter ? _paise(_margin.text) : 0,
        gstPaise: _paise(_gst.text),
        consignorPhone: _consignorPhone.text,
        consigneePhone: _consigneePhone.text,
        goodsValuePaise: _paise(_goodsValue.text),
        invoiceNo: _invoice.text,
        consignorGstin: _consignorGstin.text,
        consigneeGstin: _consigneeGstin.text,
        ewayBillNo: _eway.text,
        ewayValidUntil: _ewayUntil,
        complianceMode: _mode,
      );

  Future<void> _save() async {
    final d = _draft();
    try {
      d.validate();
    } on LrException catch (e) {
      showSnack(context, tr(context, switch (e.reason) { 'advance' => 'blAdvanceTooHigh', 'gstin' => 'blBadGstin', 'eway' => 'blBadEway', 'phone' => 'blBadPhone', _ => 'blNeedFields' }));
      return;
    }
    setState(() => _saving = true);
    try {
      final made = widget.editing == null ? await LrService.issue(widget.booking, d) : await LrService.newVersion(widget.booking, widget.editing!.pub, d);
      if (!mounted) return;
      showSnack(context, widget.editing == null ? trf(context, 'blIssuedMsg', {'no': made.lrNo}) : tr(context, 'blNewVersionMsg'));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, errorText(context, error));
      }
    }
  }

  Widget _field(String key, TextEditingController c, String labelKey, {TextInputType? type, int? maxLength, List<TextInputFormatter>? formatters}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: ValueKey(key),
          controller: c,
          keyboardType: type,
          maxLength: maxLength,
          inputFormatters: formatters,
          decoration: InputDecoration(labelText: tr(context, labelKey), counterText: ''),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const money = TextInputType.numberWithOptions(decimal: true);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        scrolledUnderElevation: 0,
        title: Text(tr(context, widget.editing == null ? 'blCreate' : 'blEdit'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), children: [
          _field('lrConsignor', _consignor, 'blConsignorName', maxLength: 80),
          _field('lrConsignee', _consignee, 'blConsigneeName', maxLength: 80),
          _field('lrGoods', _goods, 'goods', maxLength: 120),
          _field('lrPackages', _packages, 'blPackages', type: TextInputType.number, formatters: digits, maxLength: 6),
          _field('lrWeight', _weight, 'weightTons', type: money),
          _field('lrFreight', _freight, 'blFreight', type: money),
          _field('lrAdvance', _advance, 'blAdvance', type: money),
          if (_transporter) _field('lrMargin', _margin, 'blMargin', type: money),
          _field('lrGst', _gst, 'blGst', type: money),
          _field('lrConsignorPhone', _consignorPhone, 'blConsignorPhone', type: TextInputType.phone, maxLength: 15),
          _field('lrConsigneePhone', _consigneePhone, 'blConsigneePhone', type: TextInputType.phone, maxLength: 15),
          _field('lrGoodsValue', _goodsValue, 'blGoodsValue', type: money),
          _field('lrInvoice', _invoice, 'blInvoiceNo', maxLength: 40),
          _field('lrConsignorGstin', _consignorGstin, 'blConsignorGstin', maxLength: 15),
          _field('lrConsigneeGstin', _consigneeGstin, 'blConsigneeGstin', maxLength: 15),
          _field('lrEway', _eway, 'blEway', type: TextInputType.number, formatters: digits, maxLength: 12),
          TextButton.icon(
            key: const ValueKey('lrEwayDate'),
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context, initialDate: _ewayUntil ?? now.add(const Duration(days: 1)), firstDate: now.subtract(const Duration(days: 30)), lastDate: now.add(const Duration(days: 365)));
              if (d != null && mounted) setState(() => _ewayUntil = DateTime(d.year, d.month, d.day, 23, 59));
            },
            icon: const Icon(Icons.event_rounded, size: 18),
            label: Text(_ewayUntil == null ? tr(context, 'blPickDate') : '${tr(context, 'blPickDate')}: ${formatDate(_ewayUntil)}'),
          ),
          Text(tr(context, 'blEwayNote'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 14),
          Text(tr(context, 'blComplianceMode'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          RadioGroup<String>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            child: Column(children: [
              for (final (mode, key) in const [(ComplianceMode.hide, 'blModeHide'), (ComplianceMode.show, 'blModeShow'), (ComplianceMode.inspectionOnRequest, 'blModeInspection')])
                RadioListTile<String>(key: ValueKey('lrMode_$mode'), contentPadding: EdgeInsets.zero, dense: true, value: mode, title: Text(tr(context, key))),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton(key: const ValueKey('lrSave'), onPressed: _saving ? null : _save, child: Text(tr(context, 'save'))),
        ]),
      ),
    );
  }
}
