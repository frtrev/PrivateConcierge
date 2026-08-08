import 'dart:async';

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
    Position? value;
    try {
      value = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on TimeoutException {
      // The cached fix is read only after a fresh fix times out. It remains local.
      value = await Geolocator.getLastKnownPosition();
    }
    if (value == null) {
      throw StateError(
        'Unable to determine your location. Move where GPS is available, '
        'retry, or continue and select a development region manually.',
      );
    }
    return Coordinates(value.latitude, value.longitude);
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
