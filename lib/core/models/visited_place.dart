import 'geo.dart';

class VisitedPlace {
  const VisitedPlace({
    required this.poiId,
    required this.name,
    required this.category,
    required this.address,
    required this.coordinates,
    required this.visitCount,
    required this.firstVisited,
    required this.lastVisited,
  });

  final String poiId;
  final String name;
  final String category;
  final String address;
  final Coordinates coordinates;
  final int visitCount;
  final DateTime firstVisited;
  final DateTime lastVisited;
}
