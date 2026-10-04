const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// Standard geohash of a point. Nearby points share a prefix, so a prefix
/// range query finds drivers around a place. [precision] 9 is about 5 m.
/// LATER(paid): wave dispatch (3 km -> 7 km -> 15 km) queries these prefixes.
String geohashEncode(double lat, double lng, {int precision = 9}) {
  if (lat.isNaN || lng.isNaN || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw ArgumentError('Coordinates out of range: $lat, $lng');
  }
  var latLo = -90.0, latHi = 90.0, lngLo = -180.0, lngHi = 180.0;
  final out = StringBuffer();
  var evenBit = true;
  var bit = 0, ch = 0;
  while (out.length < precision) {
    if (evenBit) {
      final mid = (lngLo + lngHi) / 2;
      if (lng >= mid) {
        ch = (ch << 1) | 1;
        lngLo = mid;
      } else {
        ch <<= 1;
        lngHi = mid;
      }
    } else {
      final mid = (latLo + latHi) / 2;
      if (lat >= mid) {
        ch = (ch << 1) | 1;
        latLo = mid;
      } else {
        ch <<= 1;
        latHi = mid;
      }
    }
    evenBit = !evenBit;
    if (++bit == 5) {
      out.write(_base32[ch]);
      bit = 0;
      ch = 0;
    }
  }
  return out.toString();
}
