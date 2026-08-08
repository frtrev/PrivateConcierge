import 'dart:async';
import '../../core/models/geo.dart';
import '../../core/models/region.dart';
import '../../repositories/poi_repository.dart';
import '../../services/downloads/region_package_manager.dart';
import '../../services/geography/region_resolver.dart';
import '../../services/location/location_service.dart';
import '../../services/notifications/notification_service.dart';
import '../../services/storage/private_data_store.dart';
import '../../services/voice/voice_recognition_service.dart';

class BootstrapUpdate {
  const BootstrapUpdate({
    required this.progress,
    required this.status,
    this.requiresLocationExplanation = false,
    this.error,
    this.ready = false,
  });
  final double progress;
  final String status;
  final bool requiresLocationExplanation;
  final Object? error;
  final bool ready;
}

class BootstrapService {
  BootstrapService({
    required this.poiRepository,
    required this.privateDataStore,
    required this.locationService,
    required this.regionResolver,
    required this.packageManager,
    required this.voiceService,
    required this.notificationService,
  });
  final PoiRepository poiRepository;
  final PrivateDataStore privateDataStore;
  final LocationService locationService;
  final RegionResolver regionResolver;
  final RegionPackageManager packageManager;
  final VoiceRecognitionService voiceService;
  final NotificationService notificationService;
  Coordinates? coordinates;
  Region? region;

  Future<void> selectDevelopmentRegion(Region selected) async {
    region = selected;
    coordinates = Coordinates(
      (selected.bounds.south + selected.bounds.north) / 2,
      (selected.bounds.west + selected.bounds.east) / 2,
    );
    if (!await packageManager.isCurrent(selected)) {
      await packageManager.install(selected).drain<void>();
    }
  }

  Stream<BootstrapUpdate> run({bool requestLocation = false}) async* {
    try {
      yield const BootstrapUpdate(
        progress: .05,
        status: 'Initializing application',
      );
      yield const BootstrapUpdate(
        progress: .12,
        status: 'Opening public geographic database',
      );
      await poiRepository.open();
      yield const BootstrapUpdate(
        progress: .20,
        status: 'Opening private on-device storage',
      );
      await privateDataStore.open();
      yield const BootstrapUpdate(
        progress: .28,
        status: 'Checking location permission',
      );
      var permission = await locationService.permissionState();
      if (permission != LocationPermissionState.granted && !requestLocation) {
        yield const BootstrapUpdate(
          progress: .28,
          status:
              'Location helps select your offline city data. Your coordinates stay on this device.',
          requiresLocationExplanation: true,
        );
        return;
      }
      if (permission != LocationPermissionState.granted && requestLocation) {
        permission = await locationService.requestWhenInUsePermission();
      }
      if (permission == LocationPermissionState.granted) {
        yield const BootstrapUpdate(
          progress: .40,
          status: 'Determining current location',
        );
        coordinates = await locationService.currentLocation();
        yield const BootstrapUpdate(
          progress: .52,
          status: 'Determining current region',
        );
        region = await regionResolver.resolve(coordinates!);
        if (region == null) {
          yield const BootstrapUpdate(
            progress: .60,
            status:
                'No offline package covers this location yet. Continuing with manual region selection.',
          );
        } else {
          yield BootstrapUpdate(
            progress: .60,
            status: 'Checking ${region!.displayName} geographic data',
          );
          if (!await packageManager.isCurrent(region!)) {
            await for (final progress in packageManager.install(region!)) {
              yield BootstrapUpdate(
                progress: .60 + progress.fraction * .22,
                status: progress.message,
              );
            }
          }
        }
      } else {
        yield const BootstrapUpdate(
          progress: .60,
          status:
              'Location unavailable. Continuing with manual region selection.',
        );
      }
      yield const BootstrapUpdate(
        progress: .86,
        status: 'Checking on-device voice recognition',
      );
      await voiceService.isOnDeviceAvailable();
      yield const BootstrapUpdate(
        progress: .94,
        status: 'Initializing notification services',
      );
      await notificationService.initialize();
      yield const BootstrapUpdate(progress: 1, status: 'Ready', ready: true);
    } catch (error) {
      yield BootstrapUpdate(
        progress: 0,
        status: 'Initialization stopped',
        error: error,
      );
    }
  }
}
