import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/core/models/poi.dart';
import 'package:private_concierge/repositories/poi_repository.dart';
import 'package:private_concierge/services/nearby/nearby_service.dart';

class MemoryPoiRepository implements PoiRepository {
  final points = <PointOfInterest>[];
  @override
  Future<void> open() async {}
  @override
  Future<void> deleteRegion(String regionId) async =>
      points.removeWhere((p) => p.regionId == regionId);
  @override
  Future<void> replaceRegion(
    String regionId,
    List<PointOfInterest> values,
  ) async {
    await deleteRegion(regionId);
    points.addAll(values);
  }

  @override
  Future<List<PointOfInterest>> nearby(
    Coordinates origin, {
    String? category,
    String? query,
    double radiusMeters = 15000,
  }) async =>
      points
          .where((p) => category == null || p.category == category)
          .where(
            (p) =>
                query == null ||
                query.isEmpty ||
                p.name.toLowerCase().contains(query.toLowerCase()),
          )
          .map((p) => p.withDistance(distanceMeters(origin, p.coordinates)))
          .where((p) => p.distanceMeters! <= radiusMeters)
          .toList()
        ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));
}

void main() {
  test('filters locally and orders by distance', () async {
    final repository = MemoryPoiRepository();
    repository.points.addAll(const [
      PointOfInterest(
        id: 'far',
        regionId: 'r',
        name: 'Far Food',
        coordinates: Coordinates(35.02, -90),
        category: 'restaurant',
        subcategory: '',
        address: '',
      ),
      PointOfInterest(
        id: 'near',
        regionId: 'r',
        name: 'Near Food',
        coordinates: Coordinates(35.001, -90),
        category: 'restaurant',
        subcategory: '',
        address: '',
      ),
      PointOfInterest(
        id: 'park',
        regionId: 'r',
        name: 'Park',
        coordinates: Coordinates(35, -90),
        category: 'park',
        subcategory: '',
        address: '',
      ),
    ]);
    final result = await NearbyService(
      repository,
    ).search(const Coordinates(35, -90), category: 'restaurant');
    expect(result.map((p) => p.id), ['near', 'far']);
  });
}
