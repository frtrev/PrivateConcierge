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
    this.visitRadiusMeters = 100,
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
  StreamSubscription<LocationVisit>? _visitSubscription;
  String? _candidateId;
  DateTime? _candidateSince;
  bool _recordedCandidate = false;
  int _candidateObservations = 0;
  Coordinates? _unknownCenter;
  int? _activeSessionId;
  bool _observing = false;
  bool _starting = false;
  Future<void> _observationChain = Future.value();

  void start() {
    if (_starting ||
        _timer != null ||
        _locationSubscription != null ||
        _visitSubscription != null) {
      return;
    }
    _starting = true;
    unawaited(_startLocationUpdates());
  }

  Future<void> _startLocationUpdates() async {
    try {
      final background = await _locationService.hasBackgroundPermission();
      await _diagnostic(
        'tracker_started',
        background
            ? 'Always permission confirmed'
            : 'Background permission missing',
      );
      _visitSubscription = _locationService.visitEvents().listen(
        (visit) => _enqueue(() => recordCompletedVisit(visit)),
        onError: (Object error) =>
            _diagnostic('native_visit_error', _safeError(error)),
      );
      _locationSubscription = _locationService
          .locationUpdates(background: background)
          .listen(
            (coordinates) {
              final now = DateTime.now();
              _enqueue(
                () => recordObservation(
                  coordinates,
                  now,
                ).whenComplete(() => onObservation?.call(now)),
              );
            },
            onError: (Object error) {
              unawaited(
                _diagnostic('location_stream_error', _safeError(error)),
              );
              if (kDebugMode) {
                debugPrint('Visit location stream skipped: $error');
              }
            },
          );
      unawaited(_poll());
      _timer = Timer.periodic(pollInterval, (_) => unawaited(_poll()));
    } catch (error) {
      await _diagnostic('tracker_start_error', _safeError(error));
    } finally {
      _starting = false;
    }
  }

  Future<bool> enableBackgroundTracking() async {
    final granted = await _locationService.requestBackgroundPermission();
    await _diagnostic(
      'permission_result',
      granted ? 'Always permission granted' : 'Always permission not granted',
    );
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
    unawaited(_visitSubscription?.cancel());
    _visitSubscription = null;
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
      await _diagnostic('foreground_poll_error', _safeError(error));
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
    await _diagnostic('location_received', _coordinateDetail(coordinates));
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
      await _diagnostic('no_poi_match', _coordinateDetail(coordinates));
      await _recordUnknownObservation(coordinates, at);
      return;
    }
    if (_isAmbiguous(nearby)) {
      await _diagnostic(
        'ambiguous_poi',
        '${nearby[0].name} ${nearby[0].distanceMeters!.round()}m; '
            '${nearby[1].name} ${nearby[1].distanceMeters!.round()}m',
      );
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
      await _diagnostic(
        'candidate_started',
        '${candidate.name} ${candidate.distanceMeters!.round()}m away',
      );
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
    await _diagnostic('visit_recorded', candidate.name);
  }

  @visibleForTesting
  Future<void> recordCompletedVisit(LocationVisit visit) async {
    final duration = visit.departure.difference(visit.arrival);
    await _diagnostic(
      'native_visit_received',
      '${duration.inMinutes}m at ${_coordinateDetail(visit.coordinates)}',
      at: visit.departure,
    );
    if (duration < minimumDwell || duration > const Duration(days: 2)) {
      await _diagnostic(
        'native_visit_ignored',
        'Duration ${duration.inMinutes}m is outside accepted range',
        at: visit.departure,
      );
      return;
    }
    final custom = await _privateDataStore.customPlacesNear(
      visit.coordinates,
      radiusMeters: 150,
    );
    final nearby = custom.isNotEmpty
        ? custom
        : await _poiRepository.nearby(visit.coordinates, radiusMeters: 150);
    if (nearby.isEmpty || _isAmbiguous(nearby)) {
      await _privateDataStore.recordUnknownStay(
        visit.coordinates,
        visit.departure,
      );
      await _diagnostic(
        nearby.isEmpty ? 'native_visit_unknown' : 'native_visit_ambiguous',
        nearby.isEmpty
            ? 'No POI within 150m'
            : '${nearby[0].name}; ${nearby[1].name}',
        at: visit.departure,
      );
      return;
    }
    final place = nearby.first;
    await _privateDataStore.recordVisit(place, visit.departure);
    final sessionId = await _privateDataStore.beginVisitSession(
      place,
      visit.arrival,
    );
    await _privateDataStore.endVisitSession(sessionId, visit.departure);
    await _diagnostic(
      'native_visit_recorded',
      '${place.name}; ${duration.inMinutes}m; ${place.distanceMeters!.round()}m away',
      at: visit.departure,
    );
    await onObservation?.call(visit.departure);
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

  void _enqueue(Future<void> Function() work) {
    _observationChain = _observationChain
        .then((_) => work())
        .catchError(
          (Object error) =>
              _diagnostic('tracker_processing_error', _safeError(error)),
        );
  }

  Future<void> _diagnostic(String event, String detail, {DateTime? at}) async {
    final store = _privateDataStore;
    if (store is! VisitDiagnosticStore) return;
    try {
      await (store as VisitDiagnosticStore).recordVisitDiagnostic(
        event,
        detail,
        at ?? DateTime.now(),
      );
    } catch (error) {
      if (kDebugMode) debugPrint('Could not store visit diagnostic: $error');
    }
  }

  String _coordinateDetail(Coordinates value) =>
      '${value.latitude.toStringAsFixed(4)}, ${value.longitude.toStringAsFixed(4)}';

  String _safeError(Object error) {
    final value = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.length <= 240 ? value : value.substring(0, 240);
  }

  bool _isAmbiguous(List<PointOfInterest> nearby) {
    if (nearby.length < 2 ||
        nearby[1].distanceMeters! - nearby[0].distanceMeters! >=
            ambiguityMarginMeters) {
      return false;
    }
    final first = nearby[0];
    final second = nearby[1];
    final firstAddress = first.address.trim().toLowerCase();
    final duplicateAtSameAddress =
        firstAddress.isNotEmpty &&
        firstAddress == second.address.trim().toLowerCase() &&
        first.category == second.category;
    return !duplicateAtSameAddress;
  }
}
