import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../models/load.dart';
import '../safety/call.dart';
import '../share_text.dart';
import '../widgets/common.dart';
import 'share_links.dart';

/// Opens [uri] in another app; shows a snack when nothing can handle it.
Future<void> openExternal(BuildContext context, Uri uri) async {
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) showSnack(context, tr(context, 'cannotOpenLink'));
}

/// Share menu of a load: system share sheet, WhatsApp, or copy (text + link).
class LoadShareButton extends StatelessWidget {
  final Load load;
  const LoadShareButton({super.key, required this.load});

  String get _text => ShareLinks.withLink(loadShareText(load), load.id);

  Future<void> _pick(BuildContext context, String choice) async {
    switch (choice) {
      case 'system':
        try {
          await SharePlus.instance.share(ShareParams(text: _text, subject: 'LoadGo'));
        } catch (_) {
          if (context.mounted) showSnack(context, tr(context, 'cannotOpenLink'));
        }
      case 'whatsapp':
        await openExternal(context, ShareLinks.whatsAppUri(_text));
      default:
        await Clipboard.setData(ClipboardData(text: _text));
        if (context.mounted) showSnack(context, tr(context, 'copiedToClipboard'));
    }
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        key: ValueKey('loadShare_${load.id}'),
        tooltip: tr(context, 'share'),
        icon: Icon(Icons.share_outlined, size: 20, color: AppColors.muted),
        style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
        onSelected: (v) => _pick(context, v),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'system', child: Text(tr(context, 'shareMore'))),
          PopupMenuItem(value: 'whatsapp', child: Text(tr(context, 'shareWhatsApp'))),
          PopupMenuItem(value: 'copy', child: Text(tr(context, 'shareCopyLink'))),
        ],
      );
}

/// Call button that stays hidden until the booking is confirmed.
class ConfirmedPhoneButton extends StatelessWidget {
  final String? status;
  final String phone;
  final String label;

  const ConfirmedPhoneButton({super.key, required this.status, required this.phone, required this.label});

  @override
  Widget build(BuildContext context) {
    final shown = PhoneVisibility.visiblePhone(status, phone);
    if (shown.isEmpty) return const SizedBox.shrink();
    return TextButton.icon(
      key: const ValueKey('confirmedCall'),
      icon: const Icon(Icons.call_rounded, size: 18),
      label: Text(label),
      onPressed: () => callNumber(context, shown),
    );
  }
}

/// Opens Google Maps directions to [place] (or the saved GPS point).
class NavigateButton extends StatelessWidget {
  final String label;
  final String place;
  final double? lat;
  final double? lng;

  const NavigateButton({super.key, required this.label, required this.place, this.lat, this.lng});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        icon: const Icon(Icons.navigation_rounded, size: 18),
        label: Text(label),
        onPressed: () => openExternal(context, NavLinks.directions(place: place, lat: lat, lng: lng)),
      );
}
