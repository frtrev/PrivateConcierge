import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/core/models/local_query.dart';
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
}
