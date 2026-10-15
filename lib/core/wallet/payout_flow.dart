import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors/error_text.dart';
import '../l10n/l10n.dart';
import '../models/payout.dart';
import '../models/risk.dart';
import '../services/payout_service.dart';
import '../widgets/common.dart';

/// The "request a payout" steps shared by the older Wallet screen and the new
/// hub (F9): ask for an amount, send the request, say what happened. Records
/// only: LoadGo pays by hand for now. The step-up code check (F11) is added here.
Future<void> startPayoutRequest(BuildContext context, WalletBalances b) async {
  final ctrl = TextEditingController(text: (b.available / 100).toStringAsFixed(b.available % 100 == 0 ? 0 : 2));
  final rupees = await showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr(context, 'requestPayout')),
      content: TextField(
        key: const ValueKey('payoutAmount'),
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [LengthLimitingTextInputFormatter(10), FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(prefixIcon: const Icon(Icons.currency_rupee_rounded), helperText: trf(context, 'payoutAvailable', {'amount': formatPaise(b.available)})),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
        FilledButton(
          key: const ValueKey('payoutSubmit'),
          onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text.trim())),
          child: Text(tr(context, 'requestPayout')),
        ),
      ],
    ),
  );
  // The dialog is still animating out, so the controller is not disposed here.
  if (rupees == null || !context.mounted) return;
  try {
    await PayoutService.request((rupees * 100).round());
    if (context.mounted) showSnack(context, tr(context, 'payoutRequested'));
  } on PayoutException catch (e) {
    if (context.mounted) {
      showSnack(context, tr(context, switch (e.reason) {
        'too_much' => 'payoutTooMuch',
        'open_request' => 'payoutOpenRequest',
        _ => 'payoutAmountInvalid',
      }));
    }
  } on AccountRestrictedException {
    if (context.mounted) showSnack(context, tr(context, 'accountRestricted'));
  } catch (error) {
    if (context.mounted) showSnack(context, errorText(context, error));
  }
}
