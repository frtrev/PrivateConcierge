import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/visit_session.dart';
import 'package:private_concierge/services/routines/routine_learner.dart';

void main() {
  test('learns weekday arrival and departure after three sessions', () {
    final sessions = [
      _session(1, DateTime(2026, 8, 2, 9, 55), DateTime(2026, 8, 2, 11, 5)),
      _session(2, DateTime(2026, 8, 9, 10, 0), DateTime(2026, 8, 9, 11, 0)),
      _session(3, DateTime(2026, 8, 16, 10, 5), DateTime(2026, 8, 16, 10, 55)),
    ];

    final pattern = const RoutineLearner().learn(sessions).single;

    expect(pattern.placeName, 'Church');
    expect(pattern.weekday, DateTime.sunday);
    expect(pattern.typicalArrivalMinute, 10 * 60);
    expect(pattern.typicalDepartureMinute, 11 * 60);
    expect(pattern.sampleCount, 3);
  });

  test('does not infer a routine from fewer than three sessions', () {
    final sessions = [
      _session(1, DateTime(2026, 8, 2, 10), DateTime(2026, 8, 2, 11)),
      _session(2, DateTime(2026, 8, 9, 10), DateTime(2026, 8, 9, 11)),
    ];

    expect(const RoutineLearner().learn(sessions), isEmpty);
  });
}

VisitSession _session(int id, DateTime arrival, DateTime departure) =>
    VisitSession(
      id: id,
      poiId: 'church',
      name: 'Church',
      category: 'church',
      arrival: arrival,
      departure: departure,
    );
