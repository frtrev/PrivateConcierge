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
    required this.prayers,
    required this.createdAt,
  });

  final int id;
  final String name;
  final List<Prayer> prayers;
  final DateTime createdAt;
}
