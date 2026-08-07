import '../../core/models/geo.dart';

enum LocationPermissionState {
  notDetermined,
  denied,
  deniedForever,
  granted,
  servicesDisabled,
}

abstract interface class LocationService {
  Future<LocationPermissionState> permissionState();
  Future<LocationPermissionState> requestWhenInUsePermission();
  Future<Coordinates> currentLocation();
}
