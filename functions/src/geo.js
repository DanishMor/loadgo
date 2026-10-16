'use strict';
// A port of lib/core/location/geohash.dart plus the distance between two points.
// Used to find the drivers around a pickup place (wave dispatch, F25).

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

function encode(lat, lng, precision = 9) {
  if (![lat, lng].every(Number.isFinite) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw new RangeError(`coordinates out of range: ${lat}, ${lng}`);
  }
  let latLo = -90;
  let latHi = 90;
  let lngLo = -180;
  let lngHi = 180;
  let out = '';
  let even = true;
  let bit = 0;
  let ch = 0;
  while (out.length < precision) {
    if (even) {
      const mid = (lngLo + lngHi) / 2;
      if (lng >= mid) {
        ch = (ch << 1) | 1;
        lngLo = mid;
      } else {
        ch <<= 1;
        lngHi = mid;
      }
    } else {
      const mid = (latLo + latHi) / 2;
      if (lat >= mid) {
        ch = (ch << 1) | 1;
        latLo = mid;
      } else {
        ch <<= 1;
        latHi = mid;
      }
    }
    even = !even;
    if (++bit === 5) {
      out += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return out;
}

// The centre of a geohash cell.
function decode(hash) {
  let latLo = -90;
  let latHi = 90;
  let lngLo = -180;
  let lngHi = 180;
  let even = true;
  for (const c of hash) {
    const idx = BASE32.indexOf(c);
    if (idx < 0) throw new RangeError('not a geohash: ' + hash);
    for (let bit = 4; bit >= 0; bit--) {
      const on = (idx >> bit) & 1;
      if (even) {
        const mid = (lngLo + lngHi) / 2;
        if (on) lngLo = mid;
        else lngHi = mid;
      } else {
        const mid = (latLo + latHi) / 2;
        if (on) latLo = mid;
        else latHi = mid;
      }
      even = !even;
    }
  }
  return { lat: (latLo + latHi) / 2, lng: (lngLo + lngHi) / 2 };
}

function cellSize(precision) {
  const bits = precision * 5;
  const lngBits = Math.floor((bits + 1) / 2);
  const latBits = Math.floor(bits / 2);
  return { lat: 180 / 2 ** latBits, lng: 360 / 2 ** lngBits };
}

// The cell of the point plus its neighbours (up to 9 prefixes).
function cells(lat, lng, precision) {
  const size = cellSize(precision);
  const out = new Set();
  for (const dLat of [-1, 0, 1]) {
    for (const dLng of [-1, 0, 1]) {
      const la = lat + dLat * size.lat;
      let lo = lng + dLng * size.lng;
      if (la < -90 || la > 90) continue;
      if (lo > 180) lo -= 360;
      if (lo < -180) lo += 360;
      out.add(encode(la, lo, precision));
    }
  }
  return [...out].sort();
}

// Cell length whose 3 x 3 block covers radiusKm (the same table as the app).
function precisionForKm(radiusKm) {
  if (radiusKm <= 4) return 5;
  if (radiusKm <= 39) return 4;
  return 3;
}

function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
}

module.exports = { encode, decode, cells, cellSize, precisionForKm, haversineKm };
