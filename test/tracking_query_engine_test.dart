import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/core/models/parking_event.dart';
import 'package:private_concierge/core/models/visit_session.dart';
import 'package:private_concierge/core/models/visited_place.dart';
import 'package:private_concierge/services/tracking/tracking_query_engine.dart';

import 'visit_tracker_test.dart';

void main() {
  late MemoryPrivateDataStore store;
  late TrackingQueryEngine engine;

  setUp(() {
    store = MemoryPrivateDataStore();
    store.sessions.addAll([
      VisitSession(
        id: 2,
        poiId: 'home',
        name: 'Home',
        category: 'home',
        arrival: DateTime(2026, 8, 7, 18, 15),
        departure: DateTime(2026, 8, 8, 8),
      ),
      VisitSession(
        id: 1,
        poiId: 'work',
        name: 'Work',
        category: 'office',
        arrival: DateTime(2026, 8, 7, 9, 5),
        departure: DateTime(2026, 8, 7, 17, 10),
      ),
    ]);
    store.aggregate.addAll([
      VisitedPlace(
        poiId: 'home',
        name: 'Home',
        category: 'home',
        address: '1 Main Street',
        coordinates: const Coordinates(35.1, -89.6),
        visitCount: 8,
        firstVisited: DateTime(2026, 7),
        lastVisited: DateTime(2026, 8, 7),
      ),
      VisitedPlace(
        poiId: 'work',
        name: 'Work',
        category: 'office',
        address: '2 Main Street',
        coordinates: const Coordinates(35.2, -89.7),
        visitCount: 5,
        firstVisited: DateTime(2026, 7),
        lastVisited: DateTime(2026, 8, 7),
      ),
    ]);
    engine = TrackingQueryEngine(store, clock: () => DateTime(2026, 8, 13, 12));
  });

  test('answers arrival on last Friday', () async {
    final result = await engine.answer(
      'At what time did I arrive home last Friday?',
    );
    expect(result, isNotNull);
    expect(result!.spokenResponse, contains('6:15 PM'));
  });

  test('answers duration and departure questions', () async {
    final duration = await engine.answer('How long was I at work last Friday?');
    expect(duration!.spokenResponse, contains('8 hours and 5 minutes'));
    final departure = await engine.answer(
      'What time did I leave work last Friday?',
    );
    expect(departure!.spokenResponse, contains('5:10 PM'));
  });

  test('returns latest parking coordinate as a navigable result', () async {
    store.parking.add(
      ParkingEvent(
        id: 1,
        coordinates: const Coordinates(35.3, -89.8),
        at: DateTime(2026, 8, 13, 10),
      ),
    );
    final result = await engine.answer('Where did I park the car?');
    expect(result!.places.single.name, 'Parked car');
    expect(result.actions.single.placeId, 'parking-1');
  });

  test('does not intercept ordinary nearby place search', () async {
    expect(await engine.answer('Find the closest restaurant'), isNull);
  });

  group('recent-history intent precedence', () {
    test(
      'most recently returns one place rather than yes/no aggregate',
      () async {
        final result = await engine.answer('Where did I go most recently?');
        expect(result!.spokenResponse, startsWith('You were at Home'));
        expect(result.places, hasLength(1));
      },
    );

    test('where was I last returns one place', () async {
      final result = await engine.answer('Where was I last?');
      expect(result!.places.single.name, 'Home');
    });

    test('dated history returns a list, not a yes/no answer', () async {
      final result = await engine.answer('Where did I go last Friday?');
      expect(result!.spokenResponse, 'I found 2 visits, and here is the list:');
      expect(result.places, hasLength(2));
    });

    test('yes/no visit question remains yes/no', () async {
      final result = await engine.answer('Did I visit work last Friday?');
      expect(result!.spokenResponse, startsWith('Yes.'));
    });

    test('after question uses sequence logic', () async {
      final result = await engine.answer('Where did I go after work?');
      expect(
        result!.spokenResponse,
        startsWith('After Work, you visited Home'),
      );
    });

    test('visit and unique-place counts are not treated as yes/no', () async {
      final visits = await engine.answer(
        'How many visits did I make last Friday?',
      );
      expect(visits!.spokenResponse, contains('2 recorded visits'));
      final places = await engine.answer(
        'How many unique places did I visit last Friday?',
      );
      expect(places!.spokenResponse, contains('2 unique places'));
    });
  });
}
