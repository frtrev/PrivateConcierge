import '../../core/models/prayer.dart';

class PrayerRoutineSequence {
  static List<Prayer> expand(
    PrayerRoutine root,
    List<PrayerRoutine> routines, {
    int maximumPrayers = 1000,
  }) {
    final byId = {for (final routine in routines) routine.id: routine};
    final output = <Prayer>[];

    void addRoutine(PrayerRoutine routine, Set<int> ancestors) {
      if (!ancestors.add(routine.id)) {
        throw StateError('A prayer routine contains itself.');
      }
      for (final step in routine.steps) {
        for (var repetition = 0; repetition < step.repeatCount; repetition++) {
          if (step.type == PrayerRoutineStepType.prayer) {
            final prayer = step.prayer;
            if (prayer != null) output.add(prayer);
          } else {
            final nested = byId[step.referenceId];
            if (nested != null) addRoutine(nested, {...ancestors});
          }
          if (output.length > maximumPrayers) {
            throw StateError(
              'This routine expands beyond $maximumPrayers prayers.',
            );
          }
        }
      }
    }

    addRoutine(root, <int>{});
    return output;
  }
}
