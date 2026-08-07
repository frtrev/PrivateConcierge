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

  LocationPermissionState _map(LocationPermission value) => switch (value) {
    LocationPermission.always ||
    LocationPermission.whileInUse => LocationPermissionState.granted,
    LocationPermission.deniedForever => LocationPermissionState.deniedForever,
    LocationPermission.denied => LocationPermissionState.denied,
    LocationPermission.unableToDetermine =>
      LocationPermissionState.notDetermined,
  };
}
