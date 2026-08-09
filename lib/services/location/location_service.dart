import '../../core/models/geo.dart';

enum LocationPermissionState {
  notDetermined,
  denied,
  deniedForever,
  granted,
  servicesDisabled,
}

class LocationVisit {
  const LocationVisit({
    required this.coordinates,
    required this.arrival,
    required this.departure,
  });
  final Coordinates coordinates;
  final DateTime arrival;
  final DateTime departure;
}

abstract interface class LocationService {
  Future<LocationPermissionState> permissionState();
  Future<LocationPermissionState> requestWhenInUsePermission();
  Future<Coordinates> currentLocation();
  Future<bool> hasBackgroundPermission();
  Future<bool> requestBackgroundPermission();
  Stream<Coordinates> locationUpdates({required bool background});
  Stream<LocationVisit> visitEvents();
}
