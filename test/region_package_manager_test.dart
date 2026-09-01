import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/core/models/poi.dart';
import 'package:private_concierge/core/models/region.dart';
import 'package:private_concierge/services/downloads/overture_package_source.dart';
import 'package:private_concierge/services/downloads/region_package_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'nearby_service_test.dart';

class FakePackageSource extends OverturePackageSource {
  const FakePackageSource();
  @override
  Stream<OverturePackageDownload> download(Region region) async* {
    yield const OverturePackageDownload(bytes: 100, fraction: .5);
    yield OverturePackageDownload(
      bytes: 200,
      fraction: 1,
      points: [
        PointOfInterest(
          id: 'real',
          regionId: region.id,
          name: 'Test Place',
          coordinates: region.center,
          category: 'other',
          subcategory: 'place',
          address: '',
        ),
      ],
    );
  }
}

void main() {
  test('installs and restores a dynamic area catalog', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = MemoryPoiRepository();
    final manager = OvertureRegionPackageManager(
      await SharedPreferences.getInstance(),
      repository,
      const FakePackageSource(),
    );
    final region = Region(
      id: 'okc',
      name: 'Oklahoma City',
      administrativeArea: 'Oklahoma',
      country: 'US',
      center: const Coordinates(35.4676, -97.5164),
      bounds: const GeoBounds(south: 34, west: -99, north: 37, east: -96),
      version: 202607220,
      release: '2026-07-22.0',
      downloadUrl: Uri.parse('https://example.test/places.pmtiles'),
      approximateBytes: 1000,
      coverageMiles: 50,
    );
    final updates = await manager.install(region).toList();
    expect(updates.last.fraction, 1);
    expect(await manager.isCurrent(region), isTrue);
    expect(repository.points.single.name, 'Test Place');
    expect(
      (await manager.installedRegions()).single.displayName,
      'Oklahoma City, Oklahoma',
    );
  });

  test('tile selection changes with the requested bounds', () {
    const memphis = GeoBounds(
      south: 35.0,
      west: -90.2,
      north: 35.2,
      east: -89.9,
    );
    const okc = GeoBounds(south: 35.3, west: -97.7, north: 35.6, east: -97.3);
    final a = OverturePackageSource.tileCoordinatesFor(memphis, 14);
    final b = OverturePackageSource.tileCoordinatesFor(okc, 14);
    expect(a, isNotEmpty);
    expect(b, isNotEmpty);
    expect(a.toSet().intersection(b.toSet()), isEmpty);
  });
}
