import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/core/models/local_query.dart';
import 'package:private_concierge/core/models/opening_hours.dart';
import 'package:private_concierge/core/models/poi.dart';
import 'package:private_concierge/repositories/poi_repository.dart';
import 'package:private_concierge/services/nearby/nearby_service.dart';
import 'package:private_concierge/services/query/conversation_context.dart';
import 'package:private_concierge/services/query/local_query_engine.dart';
import 'package:private_concierge/services/query/poi_capabilities.dart';
import 'package:private_concierge/services/query/query_capability.dart';
import 'package:private_concierge/services/query/query_interpreter.dart';
import 'package:private_concierge/services/query/response_generator.dart';

class MemoryRepository implements PoiRepository {
  MemoryRepository(this.points);
  final List<PointOfInterest> points;
  @override
  Future<void> open() async {}
  @override
  Future<void> deleteRegion(String regionId) async {}
  @override
  Future<void> replaceRegion(
    String regionId,
    List<PointOfInterest> points,
  ) async {}
  @override
  Future<List<PointOfInterest>> nearby(
    Coordinates origin, {
    String? category,
    String? query,
    double radiusMeters = 15000,
  }) async {
    final normalized = query?.toLowerCase();
    return points
        .where((point) => category == null || point.category == category)
        .where(
          (point) =>
              normalized == null ||
              point.name.toLowerCase().contains(normalized) ||
              point.subcategory.contains(normalized),
        )
        .map(
          (point) =>
              point.withDistance(distanceMeters(origin, point.coordinates)),
        )
        .where((point) => point.distanceMeters! <= radiusMeters)
        .toList()
      ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
  }
}

LocalQueryEngine makeEngine({
  DateTime Function()? clock,
  List<PointOfInterest>? points,
}) {
  final nearby = NearbyService(MemoryRepository(points ?? const []));
  final context = BoundedConversationContext(clock: clock);
  return LocalQueryEngine(
    interpreter: RuleBasedQueryInterpreter(),
    contextResolver: QueryContextResolver(context),
    registry: CapabilityRegistry([
      FindPoiCapability(nearby),
      DistanceCapability(nearby),
      ComparisonCapability(nearby),
      NavigationCapability(nearby),
    ]),
    responseGenerator: const TemplateQueryResponseGenerator(),
    context: context,
  );
}

const places = [
  PointOfInterest(
    id: 'near',
    regionId: 'r',
    name: 'Near Cafe',
    coordinates: Coordinates(35.001, -90),
    category: 'restaurant',
    subcategory: 'mexican',
    address: '1 Main',
  ),
  PointOfInterest(
    id: 'far',
    regionId: 'r',
    name: 'Far Grill',
    coordinates: Coordinates(35.01, -90),
    category: 'restaurant',
    subcategory: 'american',
    address: '2 Main',
  ),
];

void main() {
  const origin = Coordinates(35, -90);

  test(
    'nearby, closest, and navigation resolve through bounded context',
    () async {
      final engine = makeEngine(points: places);
      final nearby = await engine.answer(
        'Show me nearby restaurants',
        origin: origin,
      );
      expect(nearby.result.places, hasLength(2));

      final closest = await engine.answer(
        'Which one is closest?',
        origin: origin,
      );
      expect(closest.result.selectedPoi?.id, 'near');
      expect(closest.text, contains('closest'));

      final navigation = await engine.answer('Take me there', origin: origin);
      expect(navigation.result.navigationRequested, isTrue);
      expect(navigation.result.selectedPoi?.id, 'near');

      final affirmative = await engine.answer('Yes please', origin: origin);
      expect(affirmative.result.navigationRequested, isTrue);
      expect(affirmative.result.selectedPoi?.id, 'near');
    },
  );

  test('handles empty results and unavailable location', () async {
    final empty = await makeEngine().answer('nearest pharmacy', origin: origin);
    expect(empty.result.status, QueryResultStatus.empty);
    final unavailable = await makeEngine(
      points: places,
    ).answer('nearest restaurant', origin: null);
    expect(unavailable.result.status, QueryResultStatus.unavailable);
  });

  test('can navigate directly to the closest category match', () async {
    final answer = await makeEngine(
      points: places,
    ).answer('Take me to the closest restaurant', origin: origin);
    expect(answer.result.navigationRequested, isTrue);
    expect(answer.result.selectedPoi?.id, 'near');
  });

  test('asks for a new search when context is stale', () async {
    var now = DateTime(2026, 1, 1, 12);
    final engine = makeEngine(points: places, clock: () => now);
    await engine.answer('nearest restaurant', origin: origin);
    now = now.add(const Duration(minutes: 11));
    final answer = await engine.answer('Take me there', origin: origin);
    expect(answer.result.status, QueryResultStatus.clarification);
    expect(answer.text, contains('expired'));
  });

  test('unsupported rating is reported instead of fabricated', () async {
    final answer = await makeEngine(
      points: places,
    ).answer('Which restaurant is highest rated?', origin: origin);
    expect(answer.result.status, QueryResultStatus.unavailable);
    expect(answer.text, contains('Ratings are not included'));
  });

  test('closest BP never selects an unrelated closer place', () async {
    final answer = await makeEngine(
      points: const [
        PointOfInterest(
          id: 'brady',
          regionId: 'r',
          name: 'Brady Bunch House',
          coordinates: Coordinates(35.0001, -90),
          category: 'gas',
          subcategory: 'landmark',
          address: 'Very close',
        ),
        PointOfInterest(
          id: 'bp',
          regionId: 'r',
          name: 'BP Fuel',
          coordinates: Coordinates(35.02, -90),
          category: 'gas',
          subcategory: 'gas_station',
          address: 'Farther away',
        ),
      ],
    ).answer("Where's the closest BP?", origin: origin);
    expect(answer.result.status, QueryResultStatus.success);
    expect(answer.result.selectedPoi?.id, 'bp');
    expect(
      answer.result.places.map((place) => place.id),
      isNot(contains('brady')),
    );
  });

  test('finds Walmart, donuts, pizza, and Memphis Pizza Cafe', () async {
    final engine = makeEngine(
      points: const [
        PointOfInterest(
          id: 'walmart',
          regionId: 'r',
          name: 'Walmart Supercenter',
          coordinates: Coordinates(35.01, -90),
          category: 'grocery',
          subcategory: 'supermarket',
          address: '7525 Winchester Road',
        ),
        PointOfInterest(
          id: 'donut',
          regionId: 'r',
          name: 'Gibson Donuts',
          coordinates: Coordinates(35.02, -90),
          category: 'other',
          subcategory: 'donuts',
          address: '760 Mount Moriah Road',
        ),
        PointOfInterest(
          id: 'pizza',
          regionId: 'r',
          name: 'Aldo\'s Pizza Pies',
          coordinates: Coordinates(35.03, -90),
          category: 'restaurant',
          subcategory: 'pizza_restaurant',
          address: '100 South Main Street',
        ),
        PointOfInterest(
          id: 'memphis-pizza-cafe',
          regionId: 'r',
          name: 'Memphis Pizza Cafe',
          coordinates: Coordinates(35.04, -90),
          category: 'restaurant',
          subcategory: 'pizza_restaurant',
          address: '2087 Madison Avenue',
        ),
      ],
    );

    final expectations = <String, String>{
      'Where is the nearest Walmart?': 'walmart',
      'Where is the nearest donut place?': 'donut',
      'Where is the nearest pizza place?': 'pizza',
      'Where is the nearest pizza restaurant?': 'pizza',
      'Where is the nearest Memphis Pizza Cafe?': 'memphis-pizza-cafe',
    };
    for (final entry in expectations.entries) {
      final answer = await engine.answer(entry.key, origin: origin);
      expect(answer.result.selectedPoi?.id, entry.value, reason: entry.key);
    }
  });

  test('top searches work with prefixes, plurals, and NAPA brand', () async {
    final points = <PointOfInterest>[
      for (var index = 0; index < 6; index++)
        PointOfInterest(
          id: 'church-$index',
          regionId: 'r',
          name: 'Church $index',
          coordinates: Coordinates(35 + (index + 1) / 1000, -90),
          category: 'church',
          subcategory: 'place_of_worship',
          address: '$index Church Street',
        ),
      const PointOfInterest(
        id: 'napa',
        regionId: 'r',
        name: 'NAPA Auto Parts',
        coordinates: Coordinates(35.01, -90),
        category: 'automotive',
        subcategory: 'auto_parts_store',
        address: '1 Parts Way',
      ),
    ];

    for (final phrase in [
      'Top 5 churches',
      'Top five churches',
      'Show me the top five churches',
      'Find me the top five churches',
    ]) {
      final answer = await makeEngine(
        points: points,
      ).answer(phrase, origin: origin);
      expect(answer.result.places, hasLength(5), reason: phrase);
    }

    final napa = await makeEngine(
      points: points,
    ).answer('Top five NAPA', origin: origin);
    expect(napa.result.places.single.id, 'napa');
  });

  test('missing BP is explicit and labels Shell as an alternative', () async {
    final answer = await makeEngine(
      points: const [
        PointOfInterest(
          id: 'shell',
          regionId: 'r',
          name: 'Shell',
          coordinates: Coordinates(35.01, -90),
          category: 'gas',
          subcategory: 'gas_station',
          address: '1 Fuel Way',
        ),
      ],
    ).answer("Where's the closest BP?", origin: origin);
    expect(answer.result.status, QueryResultStatus.empty);
    expect(answer.result.selectedPoi, isNull);
    expect(answer.result.alternativePoi?.id, 'shell');
    expect(answer.text, contains("couldn't find a BP"));
    expect(answer.text, contains('closest gas station is Shell'));
  });

  test('open-now constraint is never silently discarded', () async {
    final answer = await makeEngine().answer(
      "Find a BP that's open.",
      origin: origin,
    );
    expect(answer.result.status, QueryResultStatus.unavailable);
    expect(answer.text, contains('opening hours'));
  });

  test('closest open restaurant skips a closer closed restaurant', () async {
    const alwaysOpen = PlaceOpeningHours({
      1: [OpeningInterval(0, 1440)],
      2: [OpeningInterval(0, 1440)],
      3: [OpeningInterval(0, 1440)],
      4: [OpeningInterval(0, 1440)],
      5: [OpeningInterval(0, 1440)],
      6: [OpeningInterval(0, 1440)],
      7: [OpeningInterval(0, 1440)],
    });
    const alwaysClosed = PlaceOpeningHours({});
    final answer = await makeEngine(
      points: const [
        PointOfInterest(
          id: 'closed-near',
          regionId: 'r',
          name: 'Closed Near Restaurant',
          coordinates: Coordinates(35.0001, -90),
          category: 'restaurant',
          subcategory: 'restaurant',
          address: '1 Near Street',
          openingHours: alwaysClosed,
        ),
        PointOfInterest(
          id: 'open-farther',
          regionId: 'r',
          name: 'Open Restaurant',
          coordinates: Coordinates(35.01, -90),
          category: 'restaurant',
          subcategory: 'restaurant',
          address: '2 Open Street',
          openingHours: alwaysOpen,
        ),
      ],
    ).answer('Where is the closest restaurant that is open?', origin: origin);
    expect(answer.result.selectedPoi?.id, 'open-farther');
  });

  test(
    'top open restaurants and branded restaurants filter independently',
    () async {
      const alwaysOpen = PlaceOpeningHours({
        1: [OpeningInterval(0, 1440)],
        2: [OpeningInterval(0, 1440)],
        3: [OpeningInterval(0, 1440)],
        4: [OpeningInterval(0, 1440)],
        5: [OpeningInterval(0, 1440)],
        6: [OpeningInterval(0, 1440)],
        7: [OpeningInterval(0, 1440)],
      });
      const alwaysClosed = PlaceOpeningHours({});
      final engine = makeEngine(
        points: const [
          PointOfInterest(
            id: 'open-local',
            regionId: 'r',
            name: 'Open Local Restaurant',
            coordinates: Coordinates(35.001, -90),
            category: 'restaurant',
            subcategory: 'restaurant',
            address: '1 Local Street',
            openingHours: alwaysOpen,
          ),
          PointOfInterest(
            id: 'closed-local',
            regionId: 'r',
            name: 'Closed Local Restaurant',
            coordinates: Coordinates(35.002, -90),
            category: 'restaurant',
            subcategory: 'restaurant',
            address: '2 Local Street',
            openingHours: alwaysClosed,
          ),
          PointOfInterest(
            id: 'open-mcdonalds',
            regionId: 'r',
            name: "McDonald's",
            coordinates: Coordinates(35.003, -90),
            category: 'restaurant',
            subcategory: 'fast_food',
            address: '3 Burger Street',
            openingHours: alwaysOpen,
          ),
          PointOfInterest(
            id: 'closed-mcdonalds',
            regionId: 'r',
            name: "McDonald's",
            coordinates: Coordinates(35.0001, -90),
            category: 'restaurant',
            subcategory: 'fast_food',
            address: '4 Burger Street',
            openingHours: alwaysClosed,
          ),
        ],
      );

      final restaurants = await engine.answer(
        'Find me the top five restaurants that are open',
        origin: origin,
      );
      expect(
        restaurants.result.places.map((place) => place.id),
        containsAll(['open-local', 'open-mcdonalds']),
      );
      expect(
        restaurants.result.places.map((place) => place.id),
        isNot(contains('closed-local')),
      );

      final branded = await engine.answer(
        "Find me the top five McDonald's that are open",
        origin: origin,
      );
      expect(branded.result.places.map((place) => place.id), [
        'open-mcdonalds',
      ]);
    },
  );

  test('map follow-up navigates to the exact previous BP result', () async {
    final engine = makeEngine(
      points: const [
        PointOfInterest(
          id: 'bp-follow-up',
          regionId: 'r',
          name: 'BP',
          coordinates: Coordinates(35.02, -90),
          category: 'gas',
          subcategory: 'gas_station',
          address: '2 Fuel Way',
        ),
      ],
    );
    final found = await engine.answer(
      "Where's the closest BP?",
      origin: origin,
    );
    final navigation = await engine.answer('Open it in maps.', origin: origin);
    expect(found.result.selectedPoi?.id, 'bp-follow-up');
    expect(navigation.result.navigationRequested, isTrue);
    expect(navigation.result.selectedPoi?.id, found.result.selectedPoi?.id);
    expect(navigation.plan.placeQuery?.brand, 'BP');
  });

  test(
    'restaurant list follow-ups retain selection through navigation',
    () async {
      final engine = makeEngine(
        points: const [
          PointOfInterest(
            id: 'mexican-near',
            regionId: 'r',
            name: 'Casa Near',
            coordinates: Coordinates(35.001, -90),
            category: 'restaurant',
            subcategory: 'mexican restaurant',
            address: '1 Taco Lane',
          ),
          PointOfInterest(
            id: 'mexican-far',
            regionId: 'r',
            name: 'Casa Far',
            coordinates: Coordinates(35.01, -90),
            category: 'restaurant',
            subcategory: 'mexican restaurant',
            address: '9 Taco Lane',
          ),
        ],
      );
      final list = await engine.answer(
        'Show me nearby Mexican restaurants.',
        origin: origin,
      );
      final closest = await engine.answer(
        'Which one is closest?',
        origin: origin,
      );
      final navigation = await engine.answer('Navigate there.', origin: origin);
      expect(list.result.places, hasLength(2));
      expect(closest.result.selectedPoi?.id, 'mexican-near');
      expect(navigation.result.selectedPoi?.id, 'mexican-near');
      expect(navigation.result.navigationRequested, isTrue);
    },
  );

  test('Starbucks result survives show-it-on-map follow-up', () async {
    final engine = makeEngine(
      points: const [
        PointOfInterest(
          id: 'closer-cafe',
          regionId: 'r',
          name: 'Closer Cafe',
          coordinates: Coordinates(35.0001, -90),
          category: 'restaurant',
          subcategory: 'coffee_shop',
          address: '1 Coffee Way',
        ),
        PointOfInterest(
          id: 'starbucks',
          regionId: 'r',
          name: 'Starbucks',
          coordinates: Coordinates(35.005, -90),
          category: 'restaurant',
          subcategory: 'coffee_shop',
          address: '5 Coffee Way',
        ),
      ],
    );
    await engine.answer('Find a Starbucks.', origin: origin);
    final navigation = await engine.answer(
      'Show it on the map.',
      origin: origin,
    );
    expect(navigation.result.selectedPoi?.id, 'starbucks');
    expect(navigation.result.navigationRequested, isTrue);
  });
}
