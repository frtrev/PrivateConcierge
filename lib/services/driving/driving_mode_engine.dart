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
    this.displacementMeters = 0,
    this.elapsedSeconds = 0,
    this.observationAccepted = true,
    this.reason,
  });
  final MotionMode mode;
  final double speedMetersPerSecond;
  final double displacementMeters;
  final double elapsedSeconds;
  final bool observationAccepted;
  final String? reason;
}

class DrivingModeDetector {
  DrivingModeDetector({
    this.enterSpeedMetersPerSecond = 4.5,
    this.exitSpeedMetersPerSecond = 2,
    this.enterSamples = 3,
    this.exitSamples = 4,
    this.maximumAccuracyMeters = 65,
    this.minimumDrivingDuration = const Duration(seconds: 45),
    this.minimumDrivingDisplacementMeters = 150,
    this.minimumStopDuration = const Duration(seconds: 90),
  });
  final double enterSpeedMetersPerSecond;
  final double exitSpeedMetersPerSecond;
  final int enterSamples;
  final int exitSamples;
  final double maximumAccuracyMeters;
  final Duration minimumDrivingDuration;
  final double minimumDrivingDisplacementMeters;
  final Duration minimumStopDuration;
  Coordinates? _lastCoordinates;
  DateTime? _lastAt;
  int _fastSamples = 0;
  int _slowSamples = 0;
  MotionMode _mode = MotionMode.stationary;
  DateTime? _fastSince;
  Coordinates? _fastStart;
  DateTime? _slowSince;

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
      return MotionEstimate(
        mode: _mode,
        speedMetersPerSecond: 0,
        elapsedSeconds: seconds,
        observationAccepted: false,
        reason: 'interval_too_short',
      );
    }
    if (seconds > 180) {
      _resetEvidence();
      return MotionEstimate(
        mode: _mode,
        speedMetersPerSecond: 0,
        elapsedSeconds: seconds,
        observationAccepted: false,
        reason: 'update_gap',
      );
    }
    final currentAccuracy = coordinates.horizontalAccuracyMeters;
    final previousAccuracy = previous.horizontalAccuracyMeters;
    if ((currentAccuracy != null && currentAccuracy > maximumAccuracyMeters) ||
        (previousAccuracy != null &&
            previousAccuracy > maximumAccuracyMeters)) {
      _resetEvidence();
      return MotionEstimate(
        mode: _mode,
        speedMetersPerSecond: 0,
        elapsedSeconds: seconds,
        observationAccepted: false,
        reason: 'poor_accuracy',
      );
    }
    final displacement = distanceMeters(previous, coordinates);
    final uncertainty = (currentAccuracy ?? 0) + (previousAccuracy ?? 0);
    final meaningfulDisplacement = displacement > uncertainty.clamp(25, 100);
    final calculatedSpeed = meaningfulDisplacement
        ? displacement / seconds
        : 0.0;
    final reportedSpeed = coordinates.reportedSpeedMetersPerSecond;
    final speed = reportedSpeed != null && reportedSpeed.isFinite
        ? reportedSpeed
        : calculatedSpeed;
    final vehicleLike =
        speed >= enterSpeedMetersPerSecond &&
        meaningfulDisplacement &&
        (reportedSpeed == null || reportedSpeed >= enterSpeedMetersPerSecond);
    if (vehicleLike) {
      _fastSince ??= previousAt;
      _fastStart ??= previous;
      _fastSamples++;
      _slowSamples = 0;
      _slowSince = null;
    } else if (speed <= exitSpeedMetersPerSecond) {
      _slowSince ??= previousAt;
      _slowSamples++;
      _fastSamples = 0;
      _fastSince = null;
      _fastStart = null;
    } else {
      _resetEvidence();
    }
    final drivingDuration = _fastSince == null
        ? Duration.zero
        : at.difference(_fastSince!);
    final drivingDisplacement = _fastStart == null
        ? 0.0
        : distanceMeters(_fastStart!, coordinates);
    if (_mode != MotionMode.driving &&
        _fastSamples >= enterSamples &&
        drivingDuration >= minimumDrivingDuration &&
        drivingDisplacement >= minimumDrivingDisplacementMeters) {
      _mode = MotionMode.driving;
      _slowSamples = 0;
      _slowSince = null;
    } else if (_mode == MotionMode.driving &&
        _slowSamples >= exitSamples &&
        _slowSince != null &&
        at.difference(_slowSince!) >= minimumStopDuration) {
      _mode = MotionMode.stationary;
      _fastSamples = 0;
      _fastSince = null;
      _fastStart = null;
    } else if (_mode != MotionMode.driving) {
      _mode = speed > 1.2 ? MotionMode.walking : MotionMode.stationary;
    }
    return MotionEstimate(
      mode: _mode,
      speedMetersPerSecond: speed,
      displacementMeters: displacement,
      elapsedSeconds: seconds,
    );
  }

  void _resetEvidence() {
    _fastSamples = 0;
    _slowSamples = 0;
    _fastSince = null;
    _fastStart = null;
    _slowSince = null;
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
    if (!estimate.observationAccepted && privateData is VisitDiagnosticStore) {
      final accuracy = coordinates.horizontalAccuracyMeters;
      await (privateData as VisitDiagnosticStore).recordVisitDiagnostic(
        'driving_observation_ignored',
        '${estimate.reason}; interval=${estimate.elapsedSeconds.toStringAsFixed(1)}s; accuracy=${accuracy?.toStringAsFixed(1) ?? 'unknown'}m',
        at,
      );
    }
    if (estimate.mode != previousMode && privateData is VisitDiagnosticStore) {
      await (privateData as VisitDiagnosticStore).recordVisitDiagnostic(
        estimate.mode == MotionMode.driving
            ? 'driving_mode_entered'
            : 'driving_mode_exited',
        'speed=${estimate.speedMetersPerSecond.toStringAsFixed(1)}m/s; displacement=${estimate.displacementMeters.toStringAsFixed(1)}m; interval=${estimate.elapsedSeconds.toStringAsFixed(1)}s; accuracy=${coordinates.horizontalAccuracyMeters?.toStringAsFixed(1) ?? 'unknown'}m',
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
