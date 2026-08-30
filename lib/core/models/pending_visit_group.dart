import 'poi.dart';

class PendingVisitGroup {
  const PendingVisitGroup({
    required this.id,
    required this.candidates,
    required this.arrival,
    required this.departure,
    this.suggestedPoiId,
  });

  final int id;
  final List<PointOfInterest> candidates;
  final DateTime arrival;
  final DateTime? departure;
  final String? suggestedPoiId;

  PointOfInterest? get suggestedPlace {
    final id = suggestedPoiId;
    if (id == null) return null;
    for (final candidate in candidates) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }
}
