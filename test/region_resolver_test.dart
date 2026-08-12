import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/services/geography/region_resolver.dart';

class FakeLabels implements AreaLabelResolver {
  const FakeLabels(this.value);
  final AreaLabel value;
  @override
  Future<AreaLabel> label(Coordinates coordinates) async => value;
}

class FakeRelease implements OvertureReleaseResolver {
  @override
  Future<String> latest() async => '2026-07-22.0';
}

void main() {
  RegionResolver resolver(String city, String state) => LocationRegionResolver(
    labels: FakeLabels(AreaLabel(city, state, 'US')),
    releases: FakeRelease(),
  );

  test('builds coordinate-centered options for Memphis', () async {
    const location = Coordinates(35.1495, -90.049);
    final options = await resolver('Memphis', 'Tennessee').options(location);
    expect(options.map((value) => value.coverageMiles), [50, 100, 150]);
    expect(options.first.displayName, 'Memphis, Tennessee');
    expect(options.first.center, same(location));
    expect(options.first.bounds.contains(location), isTrue);
    expect(options.first.downloadUrl.host, contains('overturemaps-extras'));
  });

  test('Oklahoma coordinates produce an Oklahoma area, not Memphis', () async {
    const location = Coordinates(35.4676, -97.5164);
    final option = (await resolver(
      'Oklahoma City',
      'Oklahoma',
    ).options(location)).first;
    expect(option.displayName, 'Oklahoma City, Oklahoma');
    expect(option.id, contains('35p468_m97p516'));
    expect(option.bounds.contains(location), isTrue);
  });

  test('distant testers receive unique home areas', () async {
    final california = (await resolver(
      'San Diego',
      'California',
    ).options(const Coordinates(32.7157, -117.1611))).first;
    final maine = (await resolver(
      'Portland',
      'Maine',
    ).options(const Coordinates(43.6591, -70.2568))).first;
    expect(california.id, isNot(maine.id));
    expect(california.name, 'San Diego');
    expect(maine.name, 'Portland');
  });
}
