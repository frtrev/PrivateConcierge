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
  Future<bool> hasBackgroundPermission();
  Future<bool> requestBackgroundPermission();
  Stream<Coordinates> locationUpdates({required bool background});
}
