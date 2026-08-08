import 'dart:math' as math;

const metersPerMile = 1609.344;

class Coordinates {
  const Coordinates(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

class GeoBounds {
  const GeoBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });
  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(Coordinates point) =>
      point.latitude >= south &&
      point.latitude <= north &&
      point.longitude >= west &&
      point.longitude <= east;
}

double distanceMeters(Coordinates a, Coordinates b) {
  const earthRadius = 6371000.0;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final deltaLat = (b.latitude - a.latitude) * math.pi / 180;
  final deltaLon = (b.longitude - a.longitude) * math.pi / 180;
  final h =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(lat1) *
          math.cos(lat2) *
          math.sin(deltaLon / 2) *
          math.sin(deltaLon / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}
