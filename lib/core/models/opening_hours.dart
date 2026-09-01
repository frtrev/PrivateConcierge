class OpeningInterval {
  const OpeningInterval(this.opensMinute, this.closesMinute);

  final int opensMinute;
  final int closesMinute;

  Map<String, int> toMap() => {'opens': opensMinute, 'closes': closesMinute};

  factory OpeningInterval.fromMap(Map<String, dynamic> value) =>
      OpeningInterval(value['opens'] as int, value['closes'] as int);
}

class PlaceOpeningHours {
  const PlaceOpeningHours(this.weekly);

  final Map<int, List<OpeningInterval>> weekly;

  bool isOpenAt(DateTime localTime) {
    final minute = localTime.hour * 60 + localTime.minute;
    for (final interval in weekly[localTime.weekday] ?? const []) {
      if (interval.closesMinute > interval.opensMinute &&
          minute >= interval.opensMinute &&
          minute < interval.closesMinute) {
        return true;
      }
      if (interval.closesMinute <= interval.opensMinute &&
          minute >= interval.opensMinute) {
        return true;
      }
    }
    final previousDay = localTime.weekday == 1 ? 7 : localTime.weekday - 1;
    return (weekly[previousDay] ?? const []).any(
      (interval) =>
          interval.closesMinute <= interval.opensMinute &&
          minute < interval.closesMinute,
    );
  }

  DateTime? nextClosingTime(DateTime localTime) {
    if (!isOpenAt(localTime)) return null;
    final minute = localTime.hour * 60 + localTime.minute;
    for (final interval in weekly[localTime.weekday] ?? const []) {
      if (interval.closesMinute > interval.opensMinute &&
          minute >= interval.opensMinute &&
          minute < interval.closesMinute) {
        return DateTime(
          localTime.year,
          localTime.month,
          localTime.day,
          interval.closesMinute ~/ 60,
          interval.closesMinute % 60,
        );
      }
      if (interval.closesMinute <= interval.opensMinute &&
          minute >= interval.opensMinute) {
        return DateTime(
          localTime.year,
          localTime.month,
          localTime.day + 1,
          interval.closesMinute ~/ 60,
          interval.closesMinute % 60,
        );
      }
    }
    final previousDay = localTime.weekday == 1 ? 7 : localTime.weekday - 1;
    for (final interval in weekly[previousDay] ?? const []) {
      if (interval.closesMinute <= interval.opensMinute &&
          minute < interval.closesMinute) {
        return DateTime(
          localTime.year,
          localTime.month,
          localTime.day,
          interval.closesMinute ~/ 60,
          interval.closesMinute % 60,
        );
      }
    }
    return null;
  }

  Map<String, Object?> toMap() => {
    for (final entry in weekly.entries)
      '${entry.key}': entry.value.map((value) => value.toMap()).toList(),
  };

  factory PlaceOpeningHours.fromMap(Map<String, dynamic> value) =>
      PlaceOpeningHours({
        for (final entry in value.entries)
          int.parse(entry.key): (entry.value as List)
              .map(
                (item) => OpeningInterval.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(growable: false),
      });
}
