import 'package:shared_preferences/shared_preferences.dart';
import '../database/sqlite_poi_repository.dart';
import '../features/loading/bootstrap_service.dart';
import '../services/commands/command_interpreter.dart';
import '../services/downloads/region_package_manager.dart';
import '../services/downloads/overture_package_source.dart';
import '../services/geography/region_resolver.dart';
import '../services/location/geolocator_location_service.dart';
import '../services/location/mock_location_service.dart';
import '../services/location/location_service.dart';
import '../services/nearby/nearby_service.dart';
import '../services/network/download_client.dart';
import '../services/notifications/notification_service.dart';
import '../services/profile/user_profile_service.dart';
import '../services/routines/routine_engine.dart';
import '../services/storage/private_data_store.dart';
import '../services/voice/voice_recognition_service.dart';
import '../services/visits/visit_tracker.dart';
import 'app_theme_controller.dart';

class AppDependencies {
  AppDependencies._({
    required this.bootstrap,
    required this.packages,
    required this.nearby,
    required this.commands,
    required this.voice,
    required this.privateData,
    required this.visitTracker,
    required this.themeController,
    required this.profileService,
    required this.routineEngine,
  });
  final BootstrapService bootstrap;
  final RegionPackageManager packages;
  final NearbyService nearby;
  final CommandInterpreter commands;
  final VoiceRecognitionService voice;
  final PrivateDataStore privateData;
  final VisitTracker visitTracker;
  final AppThemeController themeController;
  final UserProfileService profileService;
  final RoutineEngine routineEngine;
  static Future<AppDependencies> create() async {
    final preferences = await SharedPreferences.getInstance();
    final poi = SqlitePoiRepository();
    final privateData = SqlitePrivateDataStore();
    const useMockLocation = bool.fromEnvironment('USE_MOCK_LOCATION');
    final LocationService location = useMockLocation
        ? MockLocationService()
        : GeolocatorLocationService();
    final resolver = BundledRegionResolver();
    final packages = OvertureRegionPackageManager(
      preferences,
      poi,
      OverturePackageSource(
        BundledFallbackDownloadClient(StaticPackageDownloadClient()),
      ),
    );
    final voice = AndroidOnDeviceVoiceRecognitionService();
    final notifications = LocalNotificationService();
    final profiles = UserProfileService(preferences);
    final routines = RoutineEngine(
      privateData,
      notifications,
      profiles,
      preferences,
    );
    return AppDependencies._(
      packages: packages,
      nearby: NearbyService(poi),
      commands: DeterministicCommandInterpreter(),
      voice: voice,
      privateData: privateData,
      visitTracker: VisitTracker(
        location,
        poi,
        privateData,
        onObservation: routines.evaluate,
      ),
      themeController: AppThemeController(preferences),
      profileService: profiles,
      routineEngine: routines,
      bootstrap: BootstrapService(
        poiRepository: poi,
        privateDataStore: privateData,
        locationService: location,
        regionResolver: resolver,
        packageManager: packages,
        voiceService: voice,
        notificationService: notifications,
      ),
    );
  }
}
