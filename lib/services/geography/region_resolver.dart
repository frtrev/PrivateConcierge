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
    version: 2026080902,
    downloadUrl: Uri.parse(
      'https://raw.githubusercontent.com/frtrev/PrivateConcierge/39cb6b4a332b74e9f0ba381f3ae22cdfd4f55763/assets/overture/us-tn-memphis-50mi.jsonl.gz',
    ),
    approximateBytes: 3420539,
    coverageMiles: 50,
    approximatePoiCount: 58453,
  ),
  Region(
    id: 'us-tn-memphis-100mi',
    name: 'Memphis',
    administrativeArea: 'Tennessee',
    country: 'US',
    bounds: const GeoBounds(
      south: 33.70,
      west: -91.67,
      north: 36.60,
      east: -88.13,
    ),
    version: 2026080902,
    downloadUrl: Uri.parse(
      'https://raw.githubusercontent.com/frtrev/PrivateConcierge/39cb6b4a332b74e9f0ba381f3ae22cdfd4f55763/assets/overture/us-tn-memphis-100mi.jsonl.gz',
    ),
    approximateBytes: 6735068,
    coverageMiles: 100,
    approximatePoiCount: 114715,
  ),
  Region(
    id: 'us-tn-memphis-150mi',
    name: 'Memphis',
    administrativeArea: 'Tennessee',
    country: 'US',
    bounds: const GeoBounds(
      south: 32.98,
      west: -92.56,
      north: 37.32,
      east: -87.24,
    ),
    version: 2026080902,
    downloadUrl: Uri.parse(
      'https://raw.githubusercontent.com/frtrev/PrivateConcierge/39cb6b4a332b74e9f0ba381f3ae22cdfd4f55763/assets/overture/us-tn-memphis-150mi.jsonl.gz',
    ),
    approximateBytes: 12940421,
    coverageMiles: 150,
    approximatePoiCount: 219574,
  ),
];

const legacyRegionIds = {'us-tn-memphis', 'us-tn-nashville', 'us-tx-dallas'};

List<Region> downloadOptionsFor(Coordinates coordinates) =>
    bundledRegions
        .where((region) => region.bounds.contains(coordinates))
        .toList()
      ..sort((a, b) => a.coverageMiles.compareTo(b.coverageMiles));
