import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/geo.dart';
import '../../repositories/poi_repository.dart';
import '../location/location_service.dart';
import '../storage/private_data_store.dart';

class VisitTracker {
  VisitTracker(
    this._locationService,
    this._poiRepository,
    this._privateDataStore, {
    this.visitRadiusMeters = 40,
    this.minimumDwell = const Duration(minutes: 5),
    this.pollInterval = const Duration(seconds: 30),
    this.minimumObservations = 3,
    this.ambiguityMarginMeters = 20,
    this.onObservation,
  });

  final LocationService _locationService;
  final PoiRepository _poiRepository;
  final PrivateDataStore _privateDataStore;
  final double visitRadiusMeters;
  final Duration minimumDwell;
  final Duration pollInterval;
  final int minimumObservations;
  final double ambiguityMarginMeters;
  final Future<void> Function(DateTime at)? onObservation;

  Timer? _timer;
  StreamSubscription<Coordinates>? _locationSubscription;
  String? _candidateId;
  DateTime? _candidateSince;
  bool _recordedCandidate = false;
  int _candidateObservations = 0;
  Coordinates? _unknownCenter;
  int? _activeSessionId;
  bool _observing = false;

  void start() {
    if (_timer != null || _locationSubscription != null) return;
    unawaited(_startLocationUpdates());
  }

  Future<void> _startLocationUpdates() async {
    final background = await _locationService.hasBackgroundPermission();
    _locationSubscription = _locationService
        .locationUpdates(background: background)
        .listen(
          (coordinates) {
            final now = DateTime.now();
            unawaited(
              recordObservation(
                coordinates,
                now,
              ).whenComplete(() => onObservation?.call(now)),
            );
          },
          onError: (Object error) {
            if (kDebugMode) debugPrint('Visit location stream skipped: $error');
          },
        );
    unawaited(_poll());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_poll()));
  }

  Future<bool> enableBackgroundTracking() async {
    final granted = await _locationService.requestBackgroundPermission();
    if (!granted) return false;
    stop(resetCandidate: false);
    start();
    return true;
  }

  Future<bool> get backgroundTrackingEnabled =>
      _locationService.hasBackgroundPermission();

  void stop({bool resetCandidate = true}) {
    _timer?.cancel();
    _timer = null;
    unawaited(_locationSubscription?.cancel());
    _locationSubscription = null;
    if (resetCandidate) {
      unawaited(_endActiveVisit(DateTime.now()));
      _resetCandidate();
    }
  }

  Future<void> _poll() async {
    if (_observing) return;
    _observing = true;
    try {
      await recordObservation(
        await _locationService.currentLocation(),
        DateTime.now(),
      );
      await onObservation?.call(DateTime.now());
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Foreground visit observation skipped: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    } finally {
      _observing = false;
    }
  }

  @visibleForTesting
  Future<void> recordObservation(Coordinates coordinates, DateTime at) async {
    final custom = await _privateDataStore.customPlacesNear(
      coordinates,
      radiusMeters: visitRadiusMeters,
    );
    final nearby = custom.isNotEmpty
        ? custom
        : await _poiRepository.nearby(
            coordinates,
            radiusMeters: visitRadiusMeters,
          );
    if (nearby.isEmpty) {
      await _recordUnknownObservation(coordinates, at);
      return;
    }
    if (nearby.length > 1 &&
        nearby[1].distanceMeters! - nearby[0].distanceMeters! <
            ambiguityMarginMeters) {
      await _recordUnknownObservation(coordinates, at);
      return;
    }
    final candidate = nearby.first;
    if (_candidateId != candidate.id) {
      await _endActiveVisit(at);
      _candidateId = candidate.id;
      _unknownCenter = null;
      _candidateSince = at;
      _candidateObservations = 1;
      _recordedCandidate = false;
      return;
    }
    _candidateObservations++;
    if (_recordedCandidate ||
        _candidateObservations < minimumObservations ||
        at.difference(_candidateSince!) < minimumDwell) {
      return;
    }
    await _privateDataStore.recordVisit(candidate, at);
    _activeSessionId = await _privateDataStore.beginVisitSession(
      candidate,
      _candidateSince!,
    );
    _recordedCandidate = true;
  }

  Future<void> _recordUnknownObservation(
    Coordinates coordinates,
    DateTime at,
  ) async {
    if (_candidateId != null && _candidateId != 'unknown') {
      await _endActiveVisit(at);
    }
    final sameCluster =
        _candidateId == 'unknown' &&
        _unknownCenter != null &&
        distanceMeters(_unknownCenter!, coordinates) <= 60;
    if (!sameCluster) {
      _candidateId = 'unknown';
      _unknownCenter = coordinates;
      _candidateSince = at;
      _candidateObservations = 1;
      _recordedCandidate = false;
      return;
    }
    _candidateObservations++;
    final count = _candidateObservations;
    _unknownCenter = Coordinates(
      ((_unknownCenter!.latitude * (count - 1)) + coordinates.latitude) / count,
      ((_unknownCenter!.longitude * (count - 1)) + coordinates.longitude) /
          count,
    );
    if (_recordedCandidate ||
        count < minimumObservations ||
        at.difference(_candidateSince!) < minimumDwell) {
      return;
    }
    await _privateDataStore.recordUnknownStay(_unknownCenter!, at);
    _recordedCandidate = true;
  }

  Future<void> _endActiveVisit(DateTime departure) async {
    final id = _activeSessionId;
    if (id == null) return;
    _activeSessionId = null;
    await _privateDataStore.endVisitSession(id, departure);
  }

  void _resetCandidate() {
    _candidateId = null;
    _candidateSince = null;
    _candidateObservations = 0;
    _unknownCenter = null;
    _recordedCandidate = false;
  }
}
