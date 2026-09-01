import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/routine_pattern.dart';
import '../notifications/notification_service.dart';
import '../profile/user_profile_service.dart';
import '../storage/private_data_store.dart';
import 'routine_learner.dart';

class RoutineEngine {
  RoutineEngine(
    this._privateData,
    this._notifications,
    this._profiles,
    this._preferences, {
    this.learner = const RoutineLearner(),
  });

  final PrivateDataStore _privateData;
  final NotificationService _notifications;
  final UserProfileService _profiles;
  final SharedPreferences _preferences;
  final RoutineLearner learner;

  Future<List<RoutinePattern>> patterns() async =>
      learner.learn(await _privateData.visitSessions());

  Future<void> evaluate(DateTime now) async {
    final todayMinute = now.hour * 60 + now.minute;
    final visits = await _privateData.mostVisited();
    final visitedToday = visits
        .where(
          (visit) =>
              visit.lastVisited.year == now.year &&
              visit.lastVisited.month == now.month &&
              visit.lastVisited.day == now.day,
        )
        .map((visit) => visit.poiId)
        .toSet();
    for (final pattern in await patterns()) {
      if (pattern.weekday != now.weekday ||
          visitedToday.contains(pattern.poiId) ||
          todayMinute < pattern.typicalArrivalMinute + 10 ||
          todayMinute > pattern.typicalArrivalMinute + 60) {
        continue;
      }
      final date = '${now.year}-${now.month}-${now.day}';
      final key = 'routine.notified.${pattern.poiId}.$date';
      if (_preferences.getBool(key) == true) continue;
      await _preferences.setBool(key, true);
      final profile = _profiles.load();
      final address = profile?.preferredAddress.trim() ?? '';
      final body = _message(
        personality: profile?.personality ?? 'warm',
        address: address,
        place: pattern.placeName,
      );
      await _notifications.show(
        id: Object.hash(pattern.poiId, date) & 0x7fffffff,
        title: 'A gentle routine check-in',
        body: body,
      );
    }
  }

  String _message({
    required String personality,
    required String address,
    required String place,
  }) {
    final prefix = address.isEmpty ? '' : '$address, ';
    return switch (personality) {
      'professional' =>
        '${prefix}your usual arrival time for $place has passed. You may be running late.',
      'playful' =>
        '$prefix$place may be wondering where you are—you might be running a little late.',
      _ =>
        '${prefix}you might be running late for $place. I thought a quiet reminder could help.',
    };
  }
}
