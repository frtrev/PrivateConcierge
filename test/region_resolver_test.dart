import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/services/geography/region_resolver.dart';

void main() {
  test('resolves Memphis coordinates to stable region id', () async {
    final region = await BundledRegionResolver().resolve(
      const Coordinates(35.1495, -90.0490),
    );
    expect(region?.id, 'us-tn-memphis');
  });
  test('returns null outside the bundled index', () async {
    expect(
      await BundledRegionResolver().resolve(const Coordinates(0, 0)),
      isNull,
    );
  });

  test('current area rounds coordinates and covers a local 50-mile radius', () {
    const location = Coordinates(41.8781, -87.6298);
    final region = const CurrentAreaRegionFactory().create(location);
    expect(region.id, 'osm-area-41p9-m87p6');
    expect(region.bounds.contains(location), isTrue);
    expect(
      distanceMeters(
        location,
        Coordinates(location.latitude + 50 / 69, location.longitude),
      ),
      closeTo(50 * metersPerMile, 1500),
    );
    expect(
      region.bounds.contains(
        Coordinates(location.latitude + 50 / 69, location.longitude),
      ),
      isTrue,
    );
  });
}
