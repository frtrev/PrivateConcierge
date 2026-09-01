import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/geo.dart';
import '../../core/models/poi.dart';
import '../../repositories/poi_repository.dart';
import '../location/location_service.dart';
import '../storage/private_data_store.dart';

class VisitTracker {
  static const int maximumAmbiguousCandidates = 5;

  VisitTracker(
    this._locationService,
    this._poiRepository,
    this._privateDataStore, {
    this.visitRadiusMeters = 100,
    this.minimumDwell = const Duration(minutes: 5),
    this.pollInterval = const Duration(seconds: 30),
    this.minimumObservations = 3,
    this.ambiguityMarginMeters = 20,
    this.locationNoiseMeters = 15,
    this.duplicateWindow = const Duration(seconds: 15),
    this.minimumDepartureObservations = 3,
    this.minimumDepartureDwell = const Duration(minutes: 1),
    this.onObservation,
    this.onLocation,
  });

  final LocationService _locationService;
  final PoiRepository _poiRepository;
  final PrivateDataStore _privateDataStore;
  final double visitRadiusMeters;
  final Duration minimumDwell;
  final Duration pollInterval;
  final int minimumObservations;
  final double ambiguityMarginMeters;
  final double locationNoiseMeters;
  final Duration duplicateWindow;
  final int minimumDepartureObservations;
  final Duration minimumDepartureDwell;
  final Future<void> Function(DateTime at)? onObservation;
  final Future<void> Function(Coordinates coordinates, DateTime at)? onLocation;

  Timer? _timer;
  StreamSubscription<Coordinates>? _locationSubscription;
  StreamSubscription<LocationVisit>? _visitSubscription;
  String? _candidateId;
  DateTime? _candidateSince;
  bool _recordedCandidate = false;
  int _candidateObservations = 0;
  Coordinates? _unknownCenter;
  int? _activeSessionId;
  int? _activePendingGroupId;
  String? _activePoiId;
  String? _departureCandidateId;
  DateTime? _departureCandidateSince;
  int _departureObservations = 0;
  Coordinates? _lastAcceptedCoordinates;
  DateTime? _lastAcceptedAt;
  Coordinates? _lastLoggedCoordinates;
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
              _enqueue(() async {
                await onLocation?.call(coordinates, now);
                await recordObservation(coordinates, now);
                await onObservation?.call(now);
              });
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
      final coordinates = await _locationService.currentLocation();
      final now = DateTime.now();
      await recordObservation(coordinates, now);
      await onObservation?.call(now);
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
    final lastCoordinates = _lastAcceptedCoordinates;
    final lastAt = _lastAcceptedAt;
    if (lastCoordinates != null &&
        lastAt != null &&
        distanceMeters(lastCoordinates, coordinates) <= locationNoiseMeters &&
        at.difference(lastAt).abs() < duplicateWindow) {
      return;
    }
    _lastAcceptedCoordinates = coordinates;
    _lastAcceptedAt = at;
    final lastLogged = _lastLoggedCoordinates;
    final locationChanged =
        lastLogged == null ||
        distanceMeters(lastLogged, coordinates) > locationNoiseMeters;
    if (locationChanged) {
      _lastLoggedCoordinates = coordinates;
      await _diagnostic('location_received', _coordinateDetail(coordinates));
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
      if (locationChanged) {
        await _diagnostic('no_poi_match', _coordinateDetail(coordinates));
      }
      await _recordUnknownObservation(coordinates, at);
      return;
    }
    if (_isAmbiguous(nearby)) {
      if (locationChanged) {
        await _diagnostic(
          'ambiguous_poi',
          '${nearby[0].name} ${_feet(nearby[0].distanceMeters!)}; '
              '${nearby[1].name} ${_feet(nearby[1].distanceMeters!)}',
        );
      }
      await _recordAmbiguousObservation(nearby, at);
      return;
    }
    final candidate = nearby.first;
    if (_activeSessionId != null || _activePendingGroupId != null) {
      if (candidate.id == _activePoiId) {
        _clearPendingDeparture();
        _candidateId = candidate.id;
        return;
      }
      if (!await _confirmDeparture(candidate.id, at)) return;
    }
    if (_candidateId != candidate.id) {
      _candidateId = candidate.id;
      _unknownCenter = null;
      _candidateSince = at;
      _candidateObservations = 1;
      _recordedCandidate = false;
      await _diagnostic(
        'candidate_started',
        '${candidate.name} ${_feet(candidate.distanceMeters!)} away',
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
    _activePoiId = candidate.id;
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
    if (nearby.isEmpty) {
      await _privateDataStore.recordUnknownStay(
        visit.coordinates,
        visit.departure,
      );
      await _diagnostic(
        'native_visit_unknown',
        'No POI within ${_feet(150)}',
        at: visit.departure,
      );
      return;
    }
    if (_isAmbiguous(nearby)) {
      final candidates = _ambiguousCandidates(nearby);
      final groupId = await _privateDataStore.beginPendingVisitGroup(
        candidates,
        visit.arrival,
      );
      await _privateDataStore.endPendingVisitGroup(groupId, visit.departure);
      await _diagnostic(
        'native_visit_group_recorded',
        candidates.map((place) => place.name).join('; '),
        at: visit.departure,
      );
      await onObservation?.call(visit.departure);
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
      '${place.name}; ${duration.inMinutes}m; ${_feet(place.distanceMeters!)} away',
      at: visit.departure,
    );
    await onObservation?.call(visit.departure);
  }

  Future<void> _recordUnknownObservation(
    Coordinates coordinates,
    DateTime at,
  ) async {
    if ((_activeSessionId != null || _activePendingGroupId != null) &&
        !await _confirmDeparture('unknown', at)) {
      return;
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

  Future<void> _recordAmbiguousObservation(
    List<PointOfInterest> nearby,
    DateTime at,
  ) async {
    final candidates = _ambiguousCandidates(nearby);
    final candidateKey =
        'group:${candidates.map((place) => place.id).join('|')}';
    if (_activeSessionId != null || _activePendingGroupId != null) {
      if (candidateKey == _activePoiId) {
        _clearPendingDeparture();
        _candidateId = candidateKey;
        return;
      }
      if (!await _confirmDeparture(candidateKey, at)) return;
    }
    if (_candidateId != candidateKey) {
      _candidateId = candidateKey;
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
    _activePendingGroupId = await _privateDataStore.beginPendingVisitGroup(
      candidates,
      _candidateSince!,
    );
    _activePoiId = candidateKey;
    _recordedCandidate = true;
    await _diagnostic(
      'visit_group_recorded',
      candidates.map((place) => place.name).join('; '),
    );
  }

  Future<void> _endActiveVisit(DateTime departure) async {
    final id = _activeSessionId;
    final groupId = _activePendingGroupId;
    if (id == null && groupId == null) return;
    _activeSessionId = null;
    _activePendingGroupId = null;
    _activePoiId = null;
    if (id != null) await _privateDataStore.endVisitSession(id, departure);
    if (groupId != null) {
      await _privateDataStore.endPendingVisitGroup(groupId, departure);
    }
  }

  Future<bool> _confirmDeparture(String newLocationId, DateTime at) async {
    if (_departureCandidateId != newLocationId) {
      _departureCandidateId = newLocationId;
      _departureCandidateSince = at;
      _departureObservations = 1;
      await _diagnostic('departure_pending', newLocationId);
      return false;
    }
    _departureObservations++;
    final since = _departureCandidateSince!;
    if (_departureObservations < minimumDepartureObservations ||
        at.difference(since) < minimumDepartureDwell) {
      return false;
    }
    await _endActiveVisit(since);
    await _diagnostic('departure_confirmed', newLocationId, at: at);
    _clearPendingDeparture();
    return true;
  }

  void _clearPendingDeparture() {
    _departureCandidateId = null;
    _departureCandidateSince = null;
    _departureObservations = 0;
  }

  String _feet(double meters) => '${(meters * 3.28084).round()} ft';

  void _resetCandidate() {
    _candidateId = null;
    _candidateSince = null;
    _candidateObservations = 0;
    _unknownCenter = null;
    _recordedCandidate = false;
    _clearPendingDeparture();
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

  List<PointOfInterest> _ambiguousCandidates(List<PointOfInterest> nearby) {
    return nearby
        .take(maximumAmbiguousCandidates)
        .toList(growable: false);
  }
}
