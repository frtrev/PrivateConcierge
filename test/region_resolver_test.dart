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
}
