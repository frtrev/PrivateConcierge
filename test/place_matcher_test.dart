import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/core/models/place_query.dart';
import 'package:private_concierge/core/models/poi.dart';
import 'package:private_concierge/services/query/place_matcher.dart';

PointOfInterest place({
  required String id,
  required String name,
  required String category,
  required double distance,
  String subcategory = '',
}) => PointOfInterest(
  id: id,
  regionId: 'r',
  name: name,
  coordinates: const Coordinates(35, -90),
  category: category,
  subcategory: subcategory,
  address: '',
  distanceMeters: distance,
);

void main() {
  test('Walmart brand can match provider grocery categorization', () {
    const query = PlaceQuery(
      category: 'shopping',
      brand: 'Walmart',
      limit: 1,
      sort: PlaceSort.distance,
    );
    final result = const PlaceMatcher().match(query, [
      place(
        id: 'walmart',
        name: 'Walmart Supercenter',
        category: 'grocery',
        distance: 1200,
      ),
    ]);
    expect(result.matches.single.place.name, 'Walmart Supercenter');
  });

  const matcher = PlaceMatcher();

  test('explicit BP rejects an unrelated closer location', () {
    final result = matcher
        .match(const PlaceQuery(category: 'gas', brand: 'BP', limit: 1), [
          place(
            id: 'wrong',
            name: 'Brady Bunch House',
            category: 'gas',
            distance: 25,
          ),
          place(id: 'bp', name: 'BP Fuel', category: 'gas', distance: 4000),
        ]);
    expect(result.matches, hasLength(1));
    expect(result.matches.single.place.id, 'bp');
  });

  test('missing explicit brand produces only a category alternative', () {
    final result = matcher.match(
      const PlaceQuery(category: 'gas', brand: 'BP', limit: 1),
      [place(id: 'shell', name: 'Shell', category: 'gas', distance: 1200)],
    );
    expect(result.matches, isEmpty);
    expect(result.alternative?.id, 'shell');
  });

  test('category and cuisine are hard filters before distance ranking', () {
    final result = matcher.match(
      const PlaceQuery(category: 'restaurant', searchTerm: 'mexican', limit: 1),
      [
        place(
          id: 'near-wrong',
          name: 'Near Grill',
          category: 'restaurant',
          subcategory: 'american',
          distance: 20,
        ),
        place(
          id: 'far-right',
          name: 'Casa Azul',
          category: 'restaurant',
          subcategory: 'mexican restaurant',
          distance: 3000,
        ),
      ],
    );
    expect(result.matches.single.place.id, 'far-right');
  });
}
