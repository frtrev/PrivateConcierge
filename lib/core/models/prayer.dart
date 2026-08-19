class Prayer {
  const Prayer({
    required this.id,
    required this.name,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class PrayerRoutine {
  const PrayerRoutine({
    required this.id,
    required this.name,
    required this.steps,
    required this.createdAt,
  });

  final int id;
  final String name;
  final List<PrayerRoutineStep> steps;
  final DateTime createdAt;

  List<Prayer> get prayers => [
    for (final step in steps)
      if (step.prayer != null)
        for (var index = 0; index < step.repeatCount; index++) step.prayer!,
  ];
}

enum PrayerRoutineStepType { prayer, routine }

class PrayerRoutineStep {
  const PrayerRoutineStep({
    required this.type,
    required this.referenceId,
    required this.name,
    required this.repeatCount,
    this.prayer,
  });

  final PrayerRoutineStepType type;
  final int referenceId;
  final String name;
  final int repeatCount;
  final Prayer? prayer;

  PrayerRoutineStep copyWith({int? repeatCount}) => PrayerRoutineStep(
    type: type,
    referenceId: referenceId,
    name: name,
    repeatCount: repeatCount ?? this.repeatCount,
    prayer: prayer,
  );
}
