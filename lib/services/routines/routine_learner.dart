import '../../core/models/routine_pattern.dart';
import '../../core/models/visit_session.dart';

class RoutineLearner {
  const RoutineLearner({this.minimumSamples = 3});

  final int minimumSamples;

  List<RoutinePattern> learn(List<VisitSession> sessions) {
    final groups = <String, List<VisitSession>>{};
    for (final session in sessions.where((value) => value.departure != null)) {
      final key = '${session.poiId}:${session.arrival.weekday}';
      groups.putIfAbsent(key, () => []).add(session);
    }
    final patterns = <RoutinePattern>[];
    for (final values in groups.values) {
      if (values.length < minimumSamples) continue;
      final first = values.first;
      final arrivals = values
          .map((value) => value.arrival.hour * 60 + value.arrival.minute)
          .toList();
      final departures = values.map((value) {
        final departure = value.departure!;
        var minute = departure.hour * 60 + departure.minute;
        if (departure.day != value.arrival.day) minute += 1440;
        return minute;
      }).toList();
      patterns.add(
        RoutinePattern(
          poiId: first.poiId,
          placeName: first.name,
          category: first.category,
          weekday: first.arrival.weekday,
          typicalArrivalMinute: _average(arrivals),
          typicalDepartureMinute: _average(departures),
          sampleCount: values.length,
        ),
      );
    }
    return patterns;
  }

  int _average(List<int> values) =>
      (values.reduce((a, b) => a + b) / values.length).round();
}
