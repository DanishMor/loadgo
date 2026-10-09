import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';

import '../features/features.dart';
import '../l10n/l10n.dart';
import '../models/booking.dart';
import '../services/features_service.dart';
import '../services/safety_service.dart';
import '../services/user_service.dart';
import '../trip/trip_alerts.dart';
import 'trip_share_service.dart';
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
    String? link;
    if (FeaturesService.isOn(FeatureKey.tripShare)) {
      try {
        link = TripShareService.linkFor(await TripShareService.createOrReuse(booking));
      } catch (_) {
        link = null; // The text is still sent without a link.
      }
    }
    final text = tripSummaryText(booking, who: who, link: link);
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

/// "Share tracking link" (MASTER-6 Task 18): a link to follow the trip, sent
/// with any app (WhatsApp, SMS, mail), for a consignee or an office. Needs the
/// trip-share feature; the link works for 24 hours and the owner can stop it.
class ShareTrackingLinkButton extends StatelessWidget {
  final Booking booking;
  const ShareTrackingLinkButton({super.key, required this.booking});

  /// Hook for tests; defaults to the system share sheet.
  static Future<void> Function(String text)? shareOverride;

  Future<void> _share(BuildContext context) async {
    final route = booking.route.join(' -> ');
    final text0 = tr(context, 'trackLinkText');
    try {
      final token = await TripShareService.createOrReuse(booking);
      final until = formatDateTime(DateTime.now().add(TripShareService.validFor));
      final text = text0.replaceAll('{app}', AppInfo.name).replaceAll('{route}', route).replaceAll('{until}', until).replaceAll('{link}', TripShareService.linkFor(token));
      if (shareOverride != null) {
        await shareOverride!(text);
      } else {
        await SharePlus.instance.share(ShareParams(text: text));
      }
    } catch (_) {
      if (context.mounted) showSnack(context, tr(context, 'somethingWrong'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!FeaturesService.isOn(FeatureKey.tripShare)) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('shareTrackingLink'),
        onPressed: () => _share(context),
        icon: const Icon(Icons.link_rounded, size: 18),
        label: Text(tr(context, 'trackLinkShare')),
      ),
    );
  }
}
