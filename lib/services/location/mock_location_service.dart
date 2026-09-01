import '../../core/models/geo.dart';
import 'location_service.dart';

class MockLocationService implements LocationService {
  MockLocationService([this.coordinates = const Coordinates(35.1, -89.6)]);
  Coordinates coordinates;
  @override
  Future<Coordinates> currentLocation() async => coordinates;
  @override
  Future<LocationPermissionState> permissionState() async =>
      LocationPermissionState.granted;
  @override
  Future<LocationPermissionState> requestWhenInUsePermission() async =>
      LocationPermissionState.granted;
  @override
  Future<bool> hasBackgroundPermission() async => true;
  @override
  Future<bool> requestBackgroundPermission() async => true;
  @override
  Stream<Coordinates> locationUpdates({required bool background}) =>
      Stream.value(coordinates);
  @override
  Stream<LocationVisit> visitEvents() => const Stream.empty();
}
