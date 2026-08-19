import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/prayer.dart';
import 'package:private_concierge/services/prayers/prayer_routine_sequence.dart';

void main() {
  final now = DateTime(2026, 8, 17);
  final hailMary = Prayer(
    id: 1,
    name: 'Hail Mary',
    text: 'Hail Mary.',
    createdAt: now,
    updatedAt: now,
  );
  final ourFather = Prayer(
    id: 2,
    name: 'Our Father',
    text: 'Our Father.',
    createdAt: now,
    updatedAt: now,
  );

  test('expands repeated prayers and nested routines in order', () {
    final decade = PrayerRoutine(
      id: 10,
      name: 'Decade',
      createdAt: now,
      steps: [
        PrayerRoutineStep(
          type: PrayerRoutineStepType.prayer,
          referenceId: hailMary.id,
          name: hailMary.name,
          repeatCount: 10,
          prayer: hailMary,
        ),
        PrayerRoutineStep(
          type: PrayerRoutineStepType.prayer,
          referenceId: ourFather.id,
          name: ourFather.name,
          repeatCount: 1,
          prayer: ourFather,
        ),
      ],
    );
    final rosary = PrayerRoutine(
      id: 11,
      name: 'Rosary',
      createdAt: now,
      steps: const [
        PrayerRoutineStep(
          type: PrayerRoutineStepType.routine,
          referenceId: 10,
          name: 'Decade',
          repeatCount: 5,
        ),
      ],
    );

    final prayers = PrayerRoutineSequence.expand(rosary, [decade, rosary]);

    expect(prayers, hasLength(55));
    expect(prayers.take(10), everyElement(hailMary));
    expect(prayers[10], ourFather);
  });

  test('rejects recursive routines', () {
    final recursive = PrayerRoutine(
      id: 20,
      name: 'Recursive',
      createdAt: now,
      steps: const [
        PrayerRoutineStep(
          type: PrayerRoutineStepType.routine,
          referenceId: 20,
          name: 'Recursive',
          repeatCount: 1,
        ),
      ],
    );

    expect(
      () => PrayerRoutineSequence.expand(recursive, [recursive]),
      throwsStateError,
    );
  });
}
