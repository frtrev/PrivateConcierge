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
}
