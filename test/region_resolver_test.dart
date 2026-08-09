import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/services/geography/region_resolver.dart';

void main() {
  test('resolves Memphis coordinates to stable region id', () async {
    final region = await BundledRegionResolver().resolve(
      const Coordinates(35.1495, -89.9),
    );
    expect(region?.id, 'us-tn-memphis-50mi');
  });

  test('resolves the device area east of the old Memphis boundary', () async {
    final region = await BundledRegionResolver().resolve(
      const Coordinates(35.1, -89.6),
    );
    expect(region?.id, 'us-tn-memphis-50mi');
    expect(
      downloadOptionsFor(
        const Coordinates(35.1, -89.6),
      ).map((option) => option.coverageMiles),
      [50, 100, 150],
    );
  });
  test('returns null outside the bundled index', () async {
    expect(
      await BundledRegionResolver().resolve(const Coordinates(0, 0)),
      isNull,
    );
  });
}
