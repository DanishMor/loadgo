import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/l10n.dart';
import '../core/models/booking.dart';

/// Pickup: customer's OTP plus what was loaded. Null when cancelled.
Future<(String, PickupProof)?> askPickupProof(BuildContext context) =>
    showDialog<(String, PickupProof)>(context: context, builder: (_) => const _ProofDialog(pickup: true));

/// Delivery: customer's OTP plus who received the goods. Null when cancelled.
Future<(String, DeliveryProof)?> askDeliveryProof(BuildContext context) =>
    showDialog<(String, DeliveryProof)>(context: context, builder: (_) => const _ProofDialog(pickup: false));

class _ProofDialog extends StatefulWidget {
  final bool pickup;
  const _ProofDialog({required this.pickup});

  @override
  State<_ProofDialog> createState() => _ProofDialogState();
}

class _ProofDialogState extends State<_ProofDialog> {
  final _form = GlobalKey<FormState>();
  final _otp = TextEditingController();
  final _a = TextEditingController(); // packages / receiver name
  final _b = TextEditingController(); // weight / receiver phone
  final _seal = TextEditingController();
  final _damage = TextEditingController();

  @override
  void dispose() {
    for (final c in [_otp, _a, _b, _seal, _damage]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final otp = _otp.text.trim();
    if (widget.pickup) {
      Navigator.of(context).pop((
        otp,
        PickupProof(
          packages: int.parse(_a.text.trim()),
          weightTons: num.parse(_b.text.trim()),
          sealNumber: _seal.text,
          damageNote: _damage.text,
        ),
      ));
    } else {
      Navigator.of(context)
          .pop((otp, DeliveryProof(receiverName: _a.text, receiverPhone: _b.text, damageNote: _damage.text)));
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? tr(context, 'fieldRequired') : null;

  @override
  Widget build(BuildContext context) {
    final pickup = widget.pickup;
    return AlertDialog(
      title: Text(tr(context, pickup ? 'pickupOtp' : 'deliveryOtp')),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('otpField'),
                controller: _otp,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: tr(context, 'enterOtp'), counterText: ''),
                validator: (v) => RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '') ? null : tr(context, 'invalidOtp'),
              ),
              if (pickup) ...[
                TextFormField(
                  key: const ValueKey('packagesField'),
                  controller: _a,
                  keyboardType: TextInputType.number,
                  inputFormatters: [LengthLimitingTextInputFormatter(10), FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: tr(context, 'packages')),
                  validator: (v) => (int.tryParse(v?.trim() ?? '') ?? 0) > 0 ? null : tr(context, 'invalidNumber'),
                ),
                TextFormField(
                  key: const ValueKey('weightField'),
                  controller: _b,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr(context, 'actualWeight')),
                  validator: (v) {
                    final n = num.tryParse(v?.trim() ?? '');
                    return (n == null || n <= 0 || n > 100) ? tr(context, 'invalidNumber') : null;
                  }, inputFormatters: [LengthLimitingTextInputFormatter(10)]),
                TextFormField(
                  controller: _seal,
                  maxLength: 40,
                  decoration: InputDecoration(labelText: tr(context, 'sealNumber'), counterText: ''),
                ),
              ] else ...[
                TextFormField(
                  key: const ValueKey('receiverField'),
                  controller: _a,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr(context, 'receiverName'), counterText: ''),
                  validator: (v) => (v == null || v.trim().length < 2) ? tr(context, 'fieldRequired') : _required(v),
                ),
                TextFormField(
                  controller: _b,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [LengthLimitingTextInputFormatter(100), FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
                  decoration: InputDecoration(labelText: tr(context, 'receiverPhone')),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    return t.isEmpty || RegExp(r'^\+?\d{10,13}$').hasMatch(t) ? null : tr(context, 'invalidMobile');
                  },
                ),
              ],
              TextFormField(
                controller: _damage,
                maxLength: 300,
                maxLines: 2,
                decoration: InputDecoration(labelText: tr(context, 'damageNote'), counterText: ''),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr(context, 'cancel'))),
        FilledButton(
          key: const ValueKey('proofSubmit'),
          onPressed: _submit,
          child: Text(tr(context, pickup ? 'markPickedUp' : 'markDelivered')),
        ),
      ],
    );
  }
}
