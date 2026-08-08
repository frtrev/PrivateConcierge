import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/core/models/poi.dart';
import 'package:private_concierge/core/models/visited_place.dart';
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
}

class MemoryPrivateDataStore implements PrivateDataStore {
  final recorded = <PointOfInterest>[];
  @override
  Future<void> open() async {}
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
    expect(privateData.recorded.map((place) => place.id), ['cafe']);
  });
}
