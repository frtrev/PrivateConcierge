import 'dart:math' as math;

import '../../core/models/geo.dart';
import '../../core/models/region.dart';

abstract interface class RegionResolver {
  Future<Region?> resolve(Coordinates coordinates);
}

class CurrentAreaRegionFactory {
  const CurrentAreaRegionFactory();

  Region create(Coordinates location, {double searchRadiusMiles = 50}) {
    final roundedLat = (location.latitude * 10).round() / 10;
    final roundedLon = (location.longitude * 10).round() / 10;
    // The margin covers the maximum displacement introduced by rounding.
    final coverageMiles = searchRadiusMiles + 8;
    final latDelta = coverageMiles / 69.0;
    final longitudeMilesPerDegree =
        69.172 * math.cos(roundedLat * math.pi / 180).abs().clamp(.2, 1);
    final lonDelta = coverageMiles / longitudeMilesPerDegree;
    final latKey = _key(roundedLat);
    final lonKey = _key(roundedLon);
    return Region(
      id: 'osm-area-$latKey-$lonKey',
      name: 'Current area',
      administrativeArea: '50-mile offline coverage',
      country: '',
      bounds: GeoBounds(
        south: roundedLat - latDelta,
        west: roundedLon - lonDelta,
        north: roundedLat + latDelta,
        east: roundedLon + lonDelta,
      ),
      version: 1,
      downloadUrl: Uri.parse('https://overpass-api.de/api/interpreter'),
      approximateBytes: 8000000,
    );
  }

  String _key(double value) =>
      value.toStringAsFixed(1).replaceAll('-', 'm').replaceAll('.', 'p');
}

class BundledRegionResolver implements RegionResolver {
  BundledRegionResolver([List<Region>? regions])
    : regions = regions ?? bundledRegions;
  final List<Region> regions;
  @override
  Future<Region?> resolve(Coordinates coordinates) async {
    for (final region in regions) {
      if (region.bounds.contains(coordinates)) return region;
    }
    return null;
  }
}

final bundledRegions = <Region>[
  Region(
    id: 'us-tn-memphis',
    name: 'Memphis',
    administrativeArea: 'Tennessee',
    country: 'US',
    bounds: const GeoBounds(
      south: 34.95,
      west: -90.35,
      north: 35.38,
      east: -89.65,
    ),
    version: 2,
    downloadUrl: Uri.parse('https://overpass-api.de/api/interpreter'),
    approximateBytes: 2500000,
  ),
  Region(
    id: 'us-tn-nashville',
    name: 'Nashville',
    administrativeArea: 'Tennessee',
    country: 'US',
    bounds: const GeoBounds(
      south: 35.90,
      west: -87.10,
      north: 36.42,
      east: -86.50,
    ),
    version: 2,
    downloadUrl: Uri.parse('https://overpass-api.de/api/interpreter'),
    approximateBytes: 2500000,
  ),
  Region(
    id: 'us-tx-dallas',
    name: 'Dallas',
    administrativeArea: 'Texas',
    country: 'US',
    bounds: const GeoBounds(
      south: 32.55,
      west: -97.10,
      north: 33.10,
      east: -96.45,
    ),
    version: 2,
    downloadUrl: Uri.parse('https://overpass-api.de/api/interpreter'),
    approximateBytes: 2500000,
  ),
];
