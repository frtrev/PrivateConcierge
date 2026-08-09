import 'geo.dart';

class UnknownPlaceCandidate {
  const UnknownPlaceCandidate({
    required this.id,
    required this.coordinates,
    required this.visitCount,
    required this.lastVisited,
  });

  final int id;
  final Coordinates coordinates;
  final int visitCount;
  final DateTime lastVisited;
}
