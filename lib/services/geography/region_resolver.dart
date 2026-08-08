import '../../core/models/geo.dart';
import '../../core/models/region.dart';

abstract interface class RegionResolver {
  Future<Region?> resolve(Coordinates coordinates);
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
      south: 34.738,
      west: -90.042,
      north: 35.462,
      east: -89.158,
    ),
    version: 20260809,
    downloadUrl: Uri.parse(
      'https://raw.githubusercontent.com/frtrev/PrivateConcierge/main/assets/overture/us-tn-memphis.jsonl.gz',
    ),
    approximateBytes: 443716,
    coverageMiles: 25,
    approximatePoiCount: 8180,
  ),
  Region(
    id: 'us-tn-memphis-50mi',
    name: 'Memphis',
    administrativeArea: 'Tennessee',
    country: 'US',
    bounds: const GeoBounds(
      south: 34.376,
      west: -90.484,
      north: 35.824,
      east: -88.716,
    ),
    version: 20260809,
    downloadUrl: Uri.parse(
      'https://raw.githubusercontent.com/frtrev/PrivateConcierge/main/assets/overture/us-tn-memphis-50mi.jsonl.gz',
    ),
    approximateBytes: 677771,
    coverageMiles: 50,
    approximatePoiCount: 12448,
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
    version: 20260715,
    downloadUrl: Uri.parse(
      'https://raw.githubusercontent.com/frtrev/PrivateConcierge/main/assets/overture/us-tn-nashville.jsonl.gz',
    ),
    approximateBytes: 568262,
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
    version: 20260715,
    downloadUrl: Uri.parse(
      'https://raw.githubusercontent.com/frtrev/PrivateConcierge/main/assets/overture/us-tx-dallas.jsonl.gz',
    ),
    approximateBytes: 1631087,
  ),
];

List<Region> downloadOptionsFor(Coordinates coordinates) =>
    bundledRegions
        .where((region) => region.bounds.contains(coordinates))
        .toList()
      ..sort((a, b) => a.coverageMiles.compareTo(b.coverageMiles));
