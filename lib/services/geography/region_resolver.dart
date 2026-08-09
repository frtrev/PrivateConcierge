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
    version: 20260809,
    downloadUrl: Uri.parse(
      'https://raw.githubusercontent.com/frtrev/PrivateConcierge/916aa91077f1f86014b6781b7b0912fe6bff5bbf/assets/overture/us-tn-memphis-50mi.jsonl.gz',
    ),
    approximateBytes: 677771,
    coverageMiles: 50,
    approximatePoiCount: 12448,
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
    version: 20260809,
    downloadUrl: Uri.parse(
      'https://raw.githubusercontent.com/frtrev/PrivateConcierge/201e2b63a234f004fb2b0c04778011459ccbb276/assets/overture/us-tn-memphis-100mi.jsonl.gz',
    ),
    approximateBytes: 1324428,
    coverageMiles: 100,
    approximatePoiCount: 24219,
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
    version: 20260809,
    downloadUrl: Uri.parse(
      'https://raw.githubusercontent.com/frtrev/PrivateConcierge/201e2b63a234f004fb2b0c04778011459ccbb276/assets/overture/us-tn-memphis-150mi.jsonl.gz',
    ),
    approximateBytes: 2494370,
    coverageMiles: 150,
    approximatePoiCount: 45489,
  ),
];

const legacyRegionIds = {'us-tn-memphis', 'us-tn-nashville', 'us-tx-dallas'};

List<Region> downloadOptionsFor(Coordinates coordinates) =>
    bundledRegions
        .where((region) => region.bounds.contains(coordinates))
        .toList()
      ..sort((a, b) => a.coverageMiles.compareTo(b.coverageMiles));
