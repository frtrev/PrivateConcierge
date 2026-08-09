import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/geo.dart';
import '../../core/models/poi.dart';
import '../../repositories/poi_repository.dart';
import '../location/location_service.dart';
import '../storage/private_data_store.dart';

class VisitTracker {
  VisitTracker(
    this._locationService,
    this._poiRepository,
    this._privateDataStore, {
    this.visitRadiusMeters = 75,
    this.minimumDwell = const Duration(minutes: 2),
    this.pollInterval = const Duration(seconds: 30),
  });

  final LocationService _locationService;
  final PoiRepository _poiRepository;
  final PrivateDataStore _privateDataStore;
  final double visitRadiusMeters;
  final Duration minimumDwell;
  final Duration pollInterval;

  Timer? _timer;
  StreamSubscription<Coordinates>? _locationSubscription;
  String? _candidateId;
  PointOfInterest? _candidate;
  DateTime? _candidateSince;
  bool _recordedCandidate = false;
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
          (coordinates) =>
              unawaited(recordObservation(coordinates, DateTime.now())),
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
    if (resetCandidate) _resetCandidate();
  }

  Future<void> _poll() async {
    if (_observing) return;
    _observing = true;
    try {
      await recordObservation(
        await _locationService.currentLocation(),
        DateTime.now(),
      );
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
    if (!_recordedCandidate &&
        _candidate != null &&
        _candidateSince != null &&
        at.difference(_candidateSince!) >= minimumDwell) {
      await _privateDataStore.recordVisit(_candidate!, at);
      _recordedCandidate = true;
    }
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
      _resetCandidate();
      return;
    }
    final candidate = nearby.first;
    if (_candidateId != candidate.id) {
      _candidateId = candidate.id;
      _candidate = candidate;
      _candidateSince = at;
      _recordedCandidate = false;
      return;
    }
    if (_recordedCandidate || at.difference(_candidateSince!) < minimumDwell) {
      return;
    }
    await _privateDataStore.recordVisit(candidate, at);
    _recordedCandidate = true;
  }

  void _resetCandidate() {
    _candidateId = null;
    _candidate = null;
    _candidateSince = null;
    _recordedCandidate = false;
  }
}
