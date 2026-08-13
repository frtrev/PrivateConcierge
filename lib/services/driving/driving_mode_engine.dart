import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/geo.dart';
import '../nearby/nearby_service.dart';
import '../notifications/notification_service.dart';
import '../profile/user_profile_service.dart';
import '../routines/routine_engine.dart';
import '../storage/private_data_store.dart';

enum MotionMode { stationary, walking, driving }

class MotionEstimate {
  const MotionEstimate({
    required this.mode,
    required this.speedMetersPerSecond,
  });
  final MotionMode mode;
  final double speedMetersPerSecond;
}

class DrivingModeDetector {
  DrivingModeDetector({
    this.enterSpeedMetersPerSecond = 4.5,
    this.exitSpeedMetersPerSecond = 2,
    this.enterSamples = 2,
    this.exitSamples = 3,
  });
  final double enterSpeedMetersPerSecond;
  final double exitSpeedMetersPerSecond;
  final int enterSamples;
  final int exitSamples;
  Coordinates? _lastCoordinates;
  DateTime? _lastAt;
  int _fastSamples = 0;
  int _slowSamples = 0;
  MotionMode _mode = MotionMode.stationary;

  MotionMode get mode => _mode;

  MotionEstimate observe(Coordinates coordinates, DateTime at) {
    final previous = _lastCoordinates;
    final previousAt = _lastAt;
    _lastCoordinates = coordinates;
    _lastAt = at;
    if (previous == null || previousAt == null) {
      return MotionEstimate(mode: _mode, speedMetersPerSecond: 0);
    }
    final seconds = at.difference(previousAt).inMilliseconds / 1000;
    if (seconds < 2) {
      return MotionEstimate(mode: _mode, speedMetersPerSecond: 0);
    }
    if (seconds > 180) {
      _fastSamples = 0;
      _slowSamples = 0;
      _mode = MotionMode.stationary;
      return MotionEstimate(mode: _mode, speedMetersPerSecond: 0);
    }
    final speed = distanceMeters(previous, coordinates) / seconds;
    if (speed >= enterSpeedMetersPerSecond) {
      _fastSamples++;
      _slowSamples = 0;
    } else if (speed <= exitSpeedMetersPerSecond) {
      _slowSamples++;
      _fastSamples = 0;
    } else {
      _fastSamples = 0;
      _slowSamples = 0;
    }
    if (_mode != MotionMode.driving && _fastSamples >= enterSamples) {
      _mode = MotionMode.driving;
      _slowSamples = 0;
    } else if (_mode == MotionMode.driving && _slowSamples >= exitSamples) {
      _mode = MotionMode.stationary;
      _fastSamples = 0;
    } else if (_mode != MotionMode.driving) {
      _mode = speed > 1.2 ? MotionMode.walking : MotionMode.stationary;
    }
    return MotionEstimate(mode: _mode, speedMetersPerSecond: speed);
  }
}

class DrivingContextEngine {
  DrivingContextEngine({
    required this.privateData,
    required this.routines,
    required this.nearby,
    required this.notifications,
    required this.profiles,
    required this.preferences,
    DrivingModeDetector? detector,
    this.minimumFuelDrive = Duration.zero,
  }) : detector = detector ?? DrivingModeDetector();

  final PrivateDataStore privateData;
  final RoutineEngine routines;
  final NearbyService nearby;
  final NotificationService notifications;
  final UserProfileService profiles;
  final SharedPreferences preferences;
  final DrivingModeDetector detector;
  final Duration minimumFuelDrive;
  DateTime? _drivingSince;
  DateTime? _lastEvaluation;
  String? _nearbyFuelStationId;

  Future<void> observe(Coordinates coordinates, DateTime at) async {
    final previousMode = detector.mode;
    final estimate = detector.observe(coordinates, at);
    if (estimate.mode != previousMode && privateData is VisitDiagnosticStore) {
      await (privateData as VisitDiagnosticStore).recordVisitDiagnostic(
        estimate.mode == MotionMode.driving
            ? 'driving_mode_entered'
            : 'driving_mode_exited',
        'Inferred speed ${estimate.speedMetersPerSecond.toStringAsFixed(1)} m/s',
        at,
      );
    }
    if (estimate.mode != previousMode) {
      if (estimate.mode == MotionMode.driving) {
        await notifications.show(
          id: 21001,
          title: 'Driving detected',
          body: 'Charon detected that you are driving.',
        );
      } else if (previousMode == MotionMode.driving &&
          estimate.mode == MotionMode.stationary) {
        await privateData.recordParking(coordinates, at);
        await notifications.show(
          id: 21002,
          title: 'Parking detected',
          body: 'Charon detected that you have parked.',
        );
      }
    }
    if (estimate.mode != MotionMode.driving) {
      _drivingSince = null;
      _nearbyFuelStationId = null;
      return;
    }
    _drivingSince ??= at;
    if (_lastEvaluation != null &&
        at.difference(_lastEvaluation!) < const Duration(minutes: 2)) {
      return;
    }
    _lastEvaluation = at;
    try {
      await _checkRoutineApproach(coordinates, at);
      await _checkFuelOpportunity(coordinates, at);
    } catch (error) {
      if (kDebugMode) debugPrint('Driving context evaluation skipped: $error');
    }
  }

  Future<void> _checkRoutineApproach(
    Coordinates coordinates,
    DateTime at,
  ) async {
    final minute = at.hour * 60 + at.minute;
    final visited = await privateData.mostVisited();
    final places = {for (final value in visited) value.poiId: value};
    for (final pattern in await routines.patterns()) {
      if (pattern.weekday != at.weekday ||
          minute < pattern.typicalArrivalMinute - 60 ||
          minute > pattern.typicalArrivalMinute + 20) {
        continue;
      }
      final place = places[pattern.poiId];
      if (place == null) continue;
      final meters = distanceMeters(coordinates, place.coordinates);
      if (meters > 5000 || meters < 400) continue;
      final date = '${at.year}-${at.month}-${at.day}';
      final key = 'driving.routine.${pattern.poiId}.$date';
      if (preferences.getBool(key) == true) continue;
      await preferences.setBool(key, true);
      final address = profiles.load()?.preferredAddress.trim() ?? '';
      await notifications.show(
        id: Object.hash('driving-routine', pattern.poiId, date) & 0x7fffffff,
        title: 'Your routine is nearby',
        body:
            '${address.isEmpty ? '' : '$address, '}you are getting close to ${pattern.placeName}.',
      );
    }
  }

  Future<void> _checkFuelOpportunity(
    Coordinates coordinates,
    DateTime at,
  ) async {
    final since = _drivingSince;
    if (since == null || at.difference(since) < minimumFuelDrive) return;
    final stations = await nearby.search(
      coordinates,
      category: 'gas',
      radiusMeters: 2 * 1609.344,
    );
    if (stations.isEmpty) {
      _nearbyFuelStationId = null;
      return;
    }
    final station = stations.first;
    if (_nearbyFuelStationId == station.id) return;
    _nearbyFuelStationId = station.id;
    final miles =
        (station.distanceMeters ??
            distanceMeters(coordinates, station.coordinates)) /
        1609.344;
    await notifications.show(
      id: Object.hash('driving-fuel', station.id) & 0x7fffffff,
      title: 'Gas station nearby',
      body: '${station.name} is ${miles.toStringAsFixed(1)} miles away.',
    );
  }
}
