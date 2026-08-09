class RoutinePattern {
  const RoutinePattern({
    required this.poiId,
    required this.placeName,
    required this.category,
    required this.weekday,
    required this.typicalArrivalMinute,
    required this.typicalDepartureMinute,
    required this.sampleCount,
  });

  final String poiId;
  final String placeName;
  final String category;
  final int weekday;
  final int typicalArrivalMinute;
  final int typicalDepartureMinute;
  final int sampleCount;
}
