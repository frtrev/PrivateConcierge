import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/core/models/geo.dart';
import 'package:private_concierge/core/models/poi.dart';
import 'package:private_concierge/core/models/region.dart';
import 'package:private_concierge/features/loading/bootstrap_service.dart';
import 'package:private_concierge/repositories/poi_repository.dart';
import 'package:private_concierge/services/downloads/region_package_manager.dart';
import 'package:private_concierge/services/geography/region_resolver.dart';
import 'package:private_concierge/services/location/location_service.dart';
import 'package:private_concierge/services/notifications/notification_service.dart';
import 'package:private_concierge/services/storage/private_data_store.dart';
import 'package:private_concierge/services/voice/voice_recognition_service.dart';

class _FailingLocation implements LocationService {
  @override
  Future<Coordinates> currentLocation() => throw StateError('No fix');
  @override
  Future<LocationPermissionState> permissionState() async =>
      LocationPermissionState.granted;
  @override
  Future<LocationPermissionState> requestWhenInUsePermission() async =>
      LocationPermissionState.granted;
}

class _Poi implements PoiRepository {
  @override
  Future<void> open() async {}
  @override
  Future<void> deleteRegion(String regionId) async {}
  @override
  Future<List<PointOfInterest>> nearby(
    Coordinates origin, {
    String? category,
    double radiusMeters = 15000,
  }) async => [];
  @override
  Future<void> replaceRegion(
    String regionId,
    List<PointOfInterest> points,
  ) async {}
}

class _Private implements PrivateDataStore {
  @override
  Future<void> open() async {}
  @override
  Future<void> deleteEverything() async {}
}

class _Resolver implements RegionResolver {
  @override
  Future<Region?> resolve(Coordinates coordinates) async => null;
}

class _Location implements LocationService {
  @override
  Future<Coordinates> currentLocation() async => const Coordinates(1, 1);
  @override
  Future<LocationPermissionState> permissionState() async =>
      LocationPermissionState.granted;
  @override
  Future<LocationPermissionState> requestWhenInUsePermission() async =>
      LocationPermissionState.granted;
}

class _Packages implements RegionPackageManager {
  @override
  Future<void> delete(Region region) async {}
  @override
  Stream<PackageProgress> install(Region region) => const Stream.empty();
  @override
  Future<List<Region>> installedRegions() async => [];
  @override
  Future<int?> installedPoiCount(Region region) async => null;
  @override
  Future<bool> isCurrent(Region region) async => false;
}

class _Voice implements VoiceRecognitionService {
  @override
  Future<bool> isOnDeviceAvailable() async => false;
  @override
  Stream<VoiceRecognitionResult> listenOnce() => const Stream.empty();
}

void main() {
  test('location failure becomes a retryable bootstrap error', () async {
    final service = BootstrapService(
      poiRepository: _Poi(),
      privateDataStore: _Private(),
      locationService: _FailingLocation(),
      regionResolver: _Resolver(),
      packageManager: _Packages(),
      voiceService: _Voice(),
      notificationService: PlaceholderNotificationService(),
    );
    final updates = await service.run().toList();
    expect(updates.last.error, isA<StateError>());
    expect(updates.last.status, 'Initialization stopped');
  });

  test(
    'unsupported bundled location requests approximate-area consent',
    () async {
      final service = BootstrapService(
        poiRepository: _Poi(),
        privateDataStore: _Private(),
        locationService: _Location(),
        regionResolver: _Resolver(),
        packageManager: _Packages(),
        voiceService: _Voice(),
        notificationService: PlaceholderNotificationService(),
      );
      final updates = await service.run().toList();
      expect(updates.last.requiresAreaDownloadConsent, isTrue);
      expect(updates.last.error, isNull);
    },
  );
}
