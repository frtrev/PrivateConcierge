class VisitSession {
  const VisitSession({
    required this.id,
    required this.poiId,
    required this.name,
    required this.category,
    required this.arrival,
    required this.departure,
  });

  final int id;
  final String poiId;
  final String name;
  final String category;
  final DateTime arrival;
  final DateTime? departure;
}
