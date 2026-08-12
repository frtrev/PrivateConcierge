import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/core/models/poi.dart';
import 'package:private_concierge/core/models/visited_place.dart';
import 'package:private_concierge/core/models/unknown_place_candidate.dart';
import 'package:private_concierge/core/models/visit_session.dart';
import 'package:private_concierge/services/location/location_service.dart';
import 'package:private_concierge/services/storage/private_data_store.dart';
import 'package:private_concierge/services/visits/visit_tracker.dart';

import 'nearby_service_test.dart';

class UnusedLocationService implements LocationService {
  @override
  Future<Coordinates> currentLocation() => throw UnimplementedError();
  @override
  Future<LocationPermissionState> permissionState() =>
      throw UnimplementedError();
  @override
  Future<LocationPermissionState> requestWhenInUsePermission() =>
      throw UnimplementedError();
  @override
  Future<bool> hasBackgroundPermission() async => false;
  @override
  Future<bool> requestBackgroundPermission() async => false;
  @override
  Stream<Coordinates> locationUpdates({required bool background}) =>
      const Stream.empty();
  @override
  Stream<LocationVisit> visitEvents() => const Stream.empty();
}

class MemoryPrivateDataStore implements PrivateDataStore {
  final recorded = <PointOfInterest>[];
  final custom = <PointOfInterest>[];
  final unknownStays = <Coordinates>[];
  final sessions = <VisitSession>[];
  @override
  Future<void> open() async {}
  @override
  Future<PointOfInterest> saveCustomPlace({
    required String name,
    required String tag,
    required Coordinates coordinates,
    bool overwrite = false,
  }) async {
    final place = PointOfInterest(
      id: 'custom-${custom.length}',
      regionId: 'private-custom',
      name: name,
      coordinates: coordinates,
      category: tag,
      subcategory: 'custom',
      address: '',
    );
    custom.add(place);
    return place;
  }

  @override
  Future<List<PointOfInterest>> customPlaces() async => custom;
  @override
  Future<List<PointOfInterest>> customPlacesNear(
    Coordinates coordinates, {
    double radiusMeters = 100,
  }) async => custom
      .map(
        (place) =>
            place.withDistance(distanceMeters(coordinates, place.coordinates)),
      )
      .where((place) => place.distanceMeters! <= radiusMeters)
      .toList();
  @override
  Future<void> deleteCustomPlace(String id) async =>
      custom.removeWhere((place) => place.id == id);
  @override
  Future<void> deleteCustomPlaces() async => custom.clear();
  @override
  Future<void> recordVisit(PointOfInterest place, DateTime visitedAt) async {
    recorded.add(place);
  }

  @override
  Future<List<VisitedPlace>> mostVisited() async => [];
  @override
  Future<void> deleteVisitHistory() async => recorded.clear();
  @override
  Future<void> deleteEverything() async => recorded.clear();
  @override
  Future<void> recordUnknownStay(
    Coordinates coordinates,
    DateTime visitedAt,
  ) async => unknownStays.add(coordinates);
  @override
  Future<UnknownPlaceCandidate?> pendingUnknownSuggestion() async => null;
  @override
  Future<void> dismissUnknownSuggestion(int id) async {}
  @override
  Future<void> resolveUnknownSuggestion(int id) async {}
  @override
  Future<int> beginVisitSession(PointOfInterest place, DateTime arrival) async {
    sessions.add(
      VisitSession(
        id: sessions.length + 1,
        poiId: place.id,
        name: place.name,
        category: place.category,
        arrival: arrival,
        departure: null,
      ),
    );
    return sessions.length;
  }

  @override
  Future<void> endVisitSession(int id, DateTime departure) async {
    final index = sessions.indexWhere((session) => session.id == id);
    final session = sessions[index];
    sessions[index] = VisitSession(
      id: session.id,
      poiId: session.poiId,
      name: session.name,
      category: session.category,
      arrival: session.arrival,
      departure: departure,
    );
  }

  @override
  Future<List<VisitSession>> visitSessions() async => sessions;
}

void main() {
  test('records one visit only after a sustained nearby observation', () async {
    final repository = MemoryPoiRepository()
      ..points.add(
        const PointOfInterest(
          id: 'cafe',
          regionId: 'region',
          name: 'Local Cafe',
          coordinates: Coordinates(35.1, -89.6),
          category: 'restaurant',
          subcategory: 'cafe',
          address: 'Main Street',
        ),
      );
    final privateData = MemoryPrivateDataStore();
    final tracker = VisitTracker(
      UnusedLocationService(),
      repository,
      privateData,
      minimumDwell: const Duration(minutes: 2),
    );
    final started = DateTime(2026, 8, 8, 12);

    await tracker.recordObservation(const Coordinates(35.1, -89.6), started);
    await tracker.recordObservation(
      const Coordinates(35.1, -89.6),
      started.add(const Duration(minutes: 1)),
    );
    expect(privateData.recorded, isEmpty);

    await tracker.recordObservation(
      const Coordinates(35.1, -89.6),
      started.add(const Duration(minutes: 2)),
    );
    await tracker.recordObservation(
      const Coordinates(35.1, -89.6),
      started.add(const Duration(minutes: 3)),
    );
    await tracker.recordObservation(
      const Coordinates(36, -90),
      started.add(const Duration(minutes: 4)),
    );
    await tracker.recordObservation(
      const Coordinates(36, -90),
      started.add(const Duration(minutes: 4, seconds: 30)),
    );
    await tracker.recordObservation(
      const Coordinates(36, -90),
      started.add(const Duration(minutes: 5)),
    );
    expect(privateData.recorded.map((place) => place.id), ['cafe']);
    expect(privateData.sessions.single.departure, isNotNull);
  });

  test('prefers a private custom POI over overlapping public data', () async {
    final repository = MemoryPoiRepository()
      ..points.add(
        const PointOfInterest(
          id: 'public-cafe',
          regionId: 'region',
          name: 'Public Cafe',
          coordinates: Coordinates(35.1, -89.6),
          category: 'restaurant',
          subcategory: 'cafe',
          address: '',
        ),
      );
    final privateData = MemoryPrivateDataStore();
    await privateData.saveCustomPlace(
      name: 'Home',
      tag: 'home',
      coordinates: const Coordinates(35.1, -89.6),
    );
    final tracker = VisitTracker(
      UnusedLocationService(),
      repository,
      privateData,
      minimumDwell: Duration.zero,
      minimumObservations: 2,
    );
    final at = DateTime(2026, 8, 8, 12);

    await tracker.recordObservation(const Coordinates(35.1, -89.6), at);
    await tracker.recordObservation(
      const Coordinates(35.1, -89.6),
      at.add(const Duration(seconds: 20)),
    );

    expect(privateData.recorded.single.id, 'custom-0');
  });

  test('does not turn a drive-by into a visit on a later departure', () async {
    final repository = MemoryPoiRepository()
      ..points.add(
        const PointOfInterest(
          id: 'church',
          regionId: 'region',
          name: 'Neighborhood Church',
          coordinates: Coordinates(35.1, -89.6),
          category: 'religion',
          subcategory: 'church',
          address: '',
        ),
      );
    final privateData = MemoryPrivateDataStore();
    final tracker = VisitTracker(
      UnusedLocationService(),
      repository,
      privateData,
      minimumDwell: const Duration(minutes: 2),
    );
    final arrived = DateTime(2026, 8, 8, 9);

    await tracker.recordObservation(const Coordinates(35.1, -89.6), arrived);
    await tracker.recordObservation(
      const Coordinates(36, -90),
      arrived.add(const Duration(hours: 2)),
    );

    expect(privateData.recorded, isEmpty);
  });

  test('GPS noise and one away sample do not end an active visit', () async {
    final repository = MemoryPoiRepository()
      ..points.add(
        const PointOfInterest(
          id: 'home',
          regionId: 'region',
          name: 'Home',
          coordinates: Coordinates(35.1, -89.6),
          category: 'home',
          subcategory: 'custom',
          address: '',
        ),
      );
    final privateData = MemoryPrivateDataStore();
    final tracker = VisitTracker(
      UnusedLocationService(),
      repository,
      privateData,
      minimumDwell: Duration.zero,
      minimumObservations: 2,
    );
    final at = DateTime(2026, 8, 8, 12);

    await tracker.recordObservation(const Coordinates(35.1, -89.6), at);
    await tracker.recordObservation(
      const Coordinates(35.1, -89.6),
      at.add(const Duration(seconds: 20)),
    );
    await tracker.recordObservation(
      const Coordinates(35.1015, -89.6),
      at.add(const Duration(minutes: 1)),
    );
    await tracker.recordObservation(
      const Coordinates(35.10002, -89.6),
      at.add(const Duration(minutes: 2)),
    );

    expect(privateData.sessions.single.departure, isNull);
  });

  test('ends a visit only after sustained observations elsewhere', () async {
    final repository = MemoryPoiRepository()
      ..points.addAll(const [
        PointOfInterest(
          id: 'home',
          regionId: 'region',
          name: 'Home',
          coordinates: Coordinates(35.1, -89.6),
          category: 'home',
          subcategory: 'custom',
          address: '',
        ),
        PointOfInterest(
          id: 'store',
          regionId: 'region',
          name: 'Store',
          coordinates: Coordinates(35.11, -89.6),
          category: 'store',
          subcategory: 'store',
          address: '',
        ),
      ]);
    final privateData = MemoryPrivateDataStore();
    final tracker = VisitTracker(
      UnusedLocationService(),
      repository,
      privateData,
      minimumDwell: Duration.zero,
      minimumObservations: 2,
    );
    final at = DateTime(2026, 8, 8, 12);
    await tracker.recordObservation(const Coordinates(35.1, -89.6), at);
    await tracker.recordObservation(
      const Coordinates(35.1, -89.6),
      at.add(const Duration(seconds: 20)),
    );
    await tracker.recordObservation(
      const Coordinates(35.11, -89.6),
      at.add(const Duration(minutes: 1)),
    );
    await tracker.recordObservation(
      const Coordinates(35.11, -89.6),
      at.add(const Duration(minutes: 1, seconds: 30)),
    );
    expect(privateData.sessions.single.departure, isNull);
    await tracker.recordObservation(
      const Coordinates(35.11, -89.6),
      at.add(const Duration(minutes: 2)),
    );

    expect(
      privateData.sessions.single.departure,
      at.add(const Duration(minutes: 1)),
    );
  });

  test('records one qualifying unknown stay without guessing a POI', () async {
    final privateData = MemoryPrivateDataStore();
    final tracker = VisitTracker(
      UnusedLocationService(),
      MemoryPoiRepository(),
      privateData,
      minimumDwell: const Duration(minutes: 2),
      minimumObservations: 3,
    );
    final arrived = DateTime(2026, 8, 8, 18);
    const location = Coordinates(35.047, -89.71);

    await tracker.recordObservation(location, arrived);
    await tracker.recordObservation(
      location,
      arrived.add(const Duration(minutes: 1)),
    );
    await tracker.recordObservation(
      location,
      arrived.add(const Duration(minutes: 2)),
    );
    await tracker.recordObservation(
      location,
      arrived.add(const Duration(minutes: 3)),
    );

    expect(privateData.unknownStays, hasLength(1));
    expect(
      distanceMeters(privateData.unknownStays.single, location),
      lessThan(1),
    );
    expect(privateData.recorded, isEmpty);
  });

  test(
    'records a completed native visit without repeated stationary updates',
    () async {
      final repository = MemoryPoiRepository()
        ..points.add(
          const PointOfInterest(
            id: 'cinema',
            regionId: 'region',
            name: 'Local Cinema',
            coordinates: Coordinates(35.1, -89.6),
            category: 'entertainment',
            subcategory: 'cinema',
            address: '',
          ),
        );
      final privateData = MemoryPrivateDataStore();
      final tracker = VisitTracker(
        UnusedLocationService(),
        repository,
        privateData,
      );
      final arrival = DateTime(2026, 8, 9, 19);

      await tracker.recordCompletedVisit(
        LocationVisit(
          coordinates: const Coordinates(35.1, -89.6),
          arrival: arrival,
          departure: arrival.add(const Duration(hours: 2)),
        ),
      );

      expect(privateData.recorded.single.name, 'Local Cinema');
      expect(privateData.sessions.single.arrival, arrival);
      expect(
        privateData.sessions.single.departure,
        arrival.add(const Duration(hours: 2)),
      );
    },
  );

  test('stores an unknown completed native stay without guessing', () async {
    final privateData = MemoryPrivateDataStore();
    final tracker = VisitTracker(
      UnusedLocationService(),
      MemoryPoiRepository(),
      privateData,
    );
    final arrival = DateTime(2026, 8, 9, 19);

    await tracker.recordCompletedVisit(
      LocationVisit(
        coordinates: const Coordinates(35.1, -89.6),
        arrival: arrival,
        departure: arrival.add(const Duration(hours: 2)),
      ),
    );

    expect(privateData.recorded, isEmpty);
    expect(privateData.unknownStays, hasLength(1));
  });
}
