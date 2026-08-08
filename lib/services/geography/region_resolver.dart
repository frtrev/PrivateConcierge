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
    version: 20260808,
    downloadUrl: Uri.parse(
      'https://raw.githubusercontent.com/frtrev/PrivateConcierge/main/assets/overture/us-tn-memphis.jsonl.gz',
    ),
    approximateBytes: 443716,
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
