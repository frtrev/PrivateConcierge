import '../../core/models/geo.dart';
import '../../core/models/poi.dart';
import '../../repositories/poi_repository.dart';

class NearbyService {
  const NearbyService(this._repository);
  final PoiRepository _repository;
  Future<List<PointOfInterest>> search(
    Coordinates origin, {
    String? category,
    double radiusMeters = 50 * metersPerMile,
  }) => _repository.nearby(
    origin,
    category: category,
    radiusMeters: radiusMeters,
  );
}
