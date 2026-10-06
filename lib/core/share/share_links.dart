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

/// The driver's or customer's phone is private until the booking exists:
/// shown from `accepted` onwards, never on a cancelled booking.
class PhoneVisibility {
  PhoneVisibility._();

  static const _confirmed = ['accepted', 'driver_arriving', 'loading', 'picked_up', 'in_transit', 'unloading', 'delivered'];

  static bool canShow(String? status) => _confirmed.contains(status);

  /// The phone to show, or an empty string while it must stay hidden.
  static String visiblePhone(String? status, String phone) => canShow(status) ? phone : '';
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
