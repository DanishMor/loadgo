import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/safety_service.dart';
import '../services/user_service.dart';
import '../trip/trip_alerts.dart';
import '../widgets/common.dart';

/// "Share trip with my emergency contacts" (SAFE2): opens the phone's SMS app
/// with the trip summary for the saved contacts. The phone sends the message
/// (no SMS provider involved); when it cannot, the text is copied instead.
class ShareTripButton extends StatelessWidget {
  final Booking booking;
  const ShareTripButton({super.key, required this.booking});

  Future<void> _share(BuildContext context) async {
    final user = await UserService.getUser();
    final contacts = SafetyService.contactsFrom(user);
    if (!context.mounted) return;
    if (contacts.isEmpty) {
      showSnack(context, tr(context, 'shareTripNoContacts'));
      return;
    }
    final who = (user?['driverName'] ?? user?['name'] ?? '').toString();
    final text = tripSummaryText(booking, who: who);
    final phones = [for (final c in contacts) c.phone.replaceAll(RegExp(r'[^0-9+]'), '')].where((p) => p.isNotEmpty).join(',');
    var ok = false;
    try {
      ok = await launchUrl(Uri(scheme: 'sms', path: phones, queryParameters: {'body': text}));
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) showSnack(context, tr(context, 'shareTripCopied'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('shareTripButton'),
        onPressed: () => _share(context),
        icon: const Icon(Icons.share_location_rounded, size: 18),
        label: Text(tr(context, 'shareTripContacts')),
      ),
    );
  }
}
