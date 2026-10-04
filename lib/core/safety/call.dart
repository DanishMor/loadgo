import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../widgets/common.dart';

/// Opens the phone dialer for [phone] (tel: link). Shows a snack if the
/// device cannot place calls (e.g. web/desktop).
Future<void> callNumber(BuildContext context, String phone) async {
  final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));
  var ok = false;
  try {
    ok = await launchUrl(uri);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) showSnack(context, tr(context, 'cannotCall'));
}
