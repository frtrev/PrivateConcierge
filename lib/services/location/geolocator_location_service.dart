import 'dart:io';

import 'package:geolocator/geolocator.dart';
import '../../core/models/geo.dart';
import 'location_service.dart';

class GeolocatorLocationService implements LocationService {
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
    return Coordinates(value.latitude, value.longitude);
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
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: background,
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
    ).map((position) => Coordinates(position.latitude, position.longitude));
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
