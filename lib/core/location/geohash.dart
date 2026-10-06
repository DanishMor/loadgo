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

/// Size in degrees of one geohash cell of [precision] characters.
({double lat, double lng}) geohashCellSize(int precision) {
  final bits = precision * 5;
  final lngBits = (bits + 1) ~/ 2;
  final latBits = bits ~/ 2;
  return (lat: 180 / (1 << latBits), lng: 360 / (1 << lngBits));
}

/// The cell containing the point plus its neighbours (up to 9 prefixes).
/// A prefix range query over these cells finds everything within roughly one
/// cell width of the point, whichever side of a cell border it sits on.
List<String> geohashCells(double lat, double lng, int precision) {
  final size = geohashCellSize(precision);
  final out = <String>{};
  for (final dLat in [-1, 0, 1]) {
    for (final dLng in [-1, 0, 1]) {
      final la = lat + dLat * size.lat;
      var lo = lng + dLng * size.lng;
      if (la < -90 || la > 90) continue;
      if (lo > 180) lo -= 360;
      if (lo < -180) lo += 360;
      out.add(geohashEncode(la, lo, precision: precision));
    }
  }
  return out.toList()..sort();
}

/// The point's cell plus the three neighbours on the side the point leans to
/// (a 2 x 2 block, so 4 live queries instead of 9). Everything within half a
/// cell width of the point is covered; farther loads stay in the full list.
List<String> geohashCoreCells(double lat, double lng, int precision) {
  final size = geohashCellSize(precision);
  double frac(double v, double offset, double step) {
    final x = (v + offset) / step;
    return x - x.floorToDouble();
  }

  final dLat = frac(lat, 90, size.lat) < 0.5 ? -1 : 1;
  final dLng = frac(lng, 180, size.lng) < 0.5 ? -1 : 1;
  final out = <String>{};
  for (final a in [0, dLat]) {
    for (final b in [0, dLng]) {
      final la = lat + a * size.lat;
      var lo = lng + b * size.lng;
      if (la < -90 || la > 90) continue;
      if (lo > 180) lo -= 360;
      if (lo < -180) lo += 360;
      out.add(geohashEncode(la, lo, precision: precision));
    }
  }
  return out.toList()..sort();
}

/// Cell length (characters) whose cell is at least [radiusKm] wide, so the
/// 3 x 3 block around the driver covers that radius. Capped to 3..5.
int geohashPrecisionForKm(double radiusKm) {
  if (radiusKm <= 4) return 5;
  if (radiusKm <= 39) return 4;
  return 3;
}
