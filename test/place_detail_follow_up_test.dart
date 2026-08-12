import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/core/models/opening_hours.dart';
import 'package:private_concierge/core/models/poi.dart';
import 'package:private_concierge/services/query/place_detail_follow_up.dart';

const _hours = PlaceOpeningHours({
  1: [OpeningInterval(9 * 60, 17 * 60)],
});

PointOfInterest place({
  PlaceOpeningHours? hours = _hours,
  String? phone = '+1 901 555 0100',
  Uri? website,
}) => PointOfInterest(
  id: 'cafe',
  regionId: 'test',
  name: 'Test Cafe',
  coordinates: const Coordinates(35, -90),
  category: 'restaurant',
  subcategory: 'cafe',
  address: '1 Main Street',
  openingHours: hours,
  phoneNumber: phone,
  website: website,
);

void main() {
  test('opening hours calculate open-now and closing time locally', () {
    final resolver = PlaceDetailFollowUpResolver(
      clock: () => DateTime(2026, 8, 10, 14), // Monday.
    );
    expect(
      resolver.resolve('Are they open now?', place()).message,
      contains('is open'),
    );
    expect(
      resolver.resolve('What time do they close?', place()).message,
      contains('5:00 PM'),
    );
  });

  test('missing hours are reported instead of invented', () {
    final resolver = PlaceDetailFollowUpResolver();
    expect(
      resolver.resolve('Are they open now?', place(hours: null)).message,
      contains("don't have reliable opening hours"),
    );
  });

  test('phone number retrieval and call action use selected place data', () {
    final resolver = PlaceDetailFollowUpResolver();
    expect(
      resolver.resolve("What's their phone number?", place()).message,
      contains('+1 901 555 0100'),
    );
    expect(resolver.resolve('Call them.', place()).action?.name, 'call');
  });

  test('follow-ups require a previously selected place', () {
    final resolver = PlaceDetailFollowUpResolver();
    expect(
      resolver.resolve("What's their phone number?", null).message,
      contains('Find a place first'),
    );
  });
}
