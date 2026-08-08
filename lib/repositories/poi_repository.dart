import '../core/models/geo.dart';
import '../core/models/poi.dart';

abstract interface class PoiRepository {
  Future<void> open();
  Future<void> replaceRegion(String regionId, List<PointOfInterest> points);
  Future<void> deleteRegion(String regionId);
  Future<List<PointOfInterest>> nearby(
    Coordinates origin, {
    String? category,
    double radiusMeters = 50 * metersPerMile,
  });
}
