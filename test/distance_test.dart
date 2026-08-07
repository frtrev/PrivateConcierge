import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';

void main() {
  test('haversine distance is symmetric and realistic', () {
    const memphis = Coordinates(35.1495, -90.0490);
    const nashville = Coordinates(36.1627, -86.7816);
    final distance = distanceMeters(memphis, nashville);
    expect(distance, closeTo(315000, 15000));
    expect(distanceMeters(nashville, memphis), closeTo(distance, .001));
  });
}
