import 'dart:io';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/models/geo.dart';
import 'location_service.dart';

class GeolocatorLocationService implements LocationService {
  static const _visitChannel = EventChannel('charon/location_visits');
  @override
  Future<LocationPermissionState> permissionState() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionState.servicesDisabled;
    }
    return _map(await Geolocator.checkPermission());
  }

  @override
  Future<LocationPermissionState> requestWhenInUsePermission() async =>
      _map(await Geolocator.requestPermission());

  @override
  Future<Coordinates> currentLocation() async {
    final value = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
    return _coordinates(value);
  }

  @override
  Future<bool> hasBackgroundPermission() async =>
      await Geolocator.checkPermission() == LocationPermission.always;

  @override
  Future<bool> requestBackgroundPermission() async =>
      await Geolocator.requestPermission() == LocationPermission.always;

  @override
  Stream<Coordinates> locationUpdates({required bool background}) {
    final LocationSettings settings;
    if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.medium,
        activityType: ActivityType.other,
        distanceFilter: 25,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
        allowBackgroundLocationUpdates: background,
      );
    } else if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 25,
        intervalDuration: const Duration(seconds: 30),
        foregroundNotificationConfig: background
            ? const ForegroundNotificationConfig(
                notificationTitle: 'Private visit tracking',
                notificationText: 'Recognizing visits privately on this device',
                enableWakeLock: true,
              )
            : null,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 25,
      );
    }
    return Geolocator.getPositionStream(
      locationSettings: settings,
    ).map(_coordinates);
  }

  Coordinates _coordinates(Position position) => Coordinates(
    position.latitude,
    position.longitude,
    horizontalAccuracyMeters: position.accuracy,
    reportedSpeedMetersPerSecond: position.speed >= 0 ? position.speed : null,
  );

  @override
  Stream<LocationVisit> visitEvents() {
    if (!Platform.isIOS) return const Stream.empty();
    return _visitChannel.receiveBroadcastStream().map((value) {
      final event = Map<Object?, Object?>.from(value as Map);
      return LocationVisit(
        coordinates: Coordinates(
          (event['latitude']! as num).toDouble(),
          (event['longitude']! as num).toDouble(),
        ),
        arrival: DateTime.fromMillisecondsSinceEpoch(
          event['arrivalMs']! as int,
        ),
        departure: DateTime.fromMillisecondsSinceEpoch(
          event['departureMs']! as int,
        ),
      );
    });
  }

  LocationPermissionState _map(LocationPermission value) => switch (value) {
    LocationPermission.always ||
    LocationPermission.whileInUse => LocationPermissionState.granted,
    LocationPermission.deniedForever => LocationPermissionState.deniedForever,
    LocationPermission.denied => LocationPermissionState.denied,
    LocationPermission.unableToDetermine =>
      LocationPermissionState.notDetermined,
  };
}
