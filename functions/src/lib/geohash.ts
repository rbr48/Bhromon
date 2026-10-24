/**
 * Geohash encoding and radius query bounds, following geofire-common's
 * algorithm (the Dart app uses the same one, see lib/core/geo/geohash.dart).
 */
const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/** Characters stored on each pin: ~1 m cells. */
export const GEOHASH_PRECISION = 10;

/** Geohash of ([lat], [lng]) with [precision] characters. */
export function encodeGeohash(lat: number, lng: number, precision = GEOHASH_PRECISION): string {
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw new Error(`invalid coordinates (${lat}, ${lng})`);
  }
  let latMin = -90;
  let latMax = 90;
  let lngMin = -180;
  let lngMax = 180;
  let hash = '';
  let value = 0;
  let bits = 0;
  let evenBit = true;
  while (hash.length < precision) {
    if (evenBit) {
      const mid = (lngMin + lngMax) / 2;
      if (lng > mid) {
        value = (value << 1) + 1;
        lngMin = mid;
      } else {
        value = value << 1;
        lngMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (lat > mid) {
        value = (value << 1) + 1;
        latMin = mid;
      } else {
        value = value << 1;
        latMax = mid;
      }
    }
    evenBit = !evenBit;
    if (bits < 4) {
      bits++;
    } else {
      hash += BASE32[value];
      bits = 0;
      value = 0;
    }
  }
  return hash;
}
