/// Deep link for a load, plus reading the id back out of a shared link.
class ShareLinks {
  ShareLinks._();

  /// Hosting site of the project; change it when a custom domain is added.
  static String host = 'loadgo-defc2.web.app';

  static String loadLink(String id) => 'https://$host/load/${Uri.encodeComponent(id)}';

  /// Id of a load link on [host] (or the same path on another host), or null.
  static String? parseLoadId(String? link) {
    if (link == null) return null;
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) return null;
    final seg = uri.pathSegments;
    if (seg.length != 2 || seg[0] != 'load' || seg[1].isEmpty || seg[1].length > 64) return null;
    return seg[1];
  }

  /// `wa.me` chooses WhatsApp or WhatsApp Business on the device.
  static Uri whatsAppUri(String text) => Uri.https('wa.me', '/', {'text': text});

  /// Text sent with the link (English: the receiver may use another language).
  static String withLink(String text, String id) => '$text\n${loadLink(id)}';
}

/// Phone numbers of the customer, the driver and the transporter are never
/// shown to each other (Task 68): they chat and call inside the app. Admins
/// see them in the admin screens, and every view is written to `audit_events`.
/// Only SOS, 112 and the user's own emergency contacts open the dialer.
class PhoneVisibility {
  PhoneVisibility._();

  static bool canShow(String? status) => false;

  /// Always empty: the other party's number stays hidden.
  static String visiblePhone(String? status, String phone) => '';
}

/// Google Maps directions link. No API key: it opens the Maps app or site.
class NavLinks {
  NavLinks._();

  static Uri directions({String? place, double? lat, double? lng}) {
    final destination = (lat != null && lng != null) ? '${_fmt(lat)},${_fmt(lng)}' : (place ?? '').trim();
    return Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': destination, 'travelmode': 'driving'});
  }

  static String _fmt(double v) => v.toStringAsFixed(6);
}
