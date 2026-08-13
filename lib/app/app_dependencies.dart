import 'package:shared_preferences/shared_preferences.dart';
import '../database/sqlite_poi_repository.dart';
import '../features/loading/bootstrap_service.dart';
import '../services/commands/command_interpreter.dart';
import '../services/assistant/assistant_engine.dart';
import '../services/downloads/region_package_manager.dart';
import '../services/downloads/overture_package_source.dart';
import '../services/driving/driving_mode_engine.dart';
import '../services/geography/region_resolver.dart';
import '../services/location/geolocator_location_service.dart';
import '../services/location/mock_location_service.dart';
import '../services/location/location_service.dart';
import '../services/nearby/nearby_service.dart';
import '../services/navigation/navigation_service.dart';
import '../services/notifications/notification_service.dart';
import '../services/profile/user_profile_service.dart';
import '../services/query/conversation_context.dart';
import '../services/query/local_query_engine.dart';
import '../services/query/poi_capabilities.dart';
import '../services/query/query_capability.dart';
import '../services/query/query_interpreter.dart';
import '../services/query/response_generator.dart';
import '../services/routines/routine_engine.dart';
import '../services/storage/private_data_store.dart';
import '../services/voice/voice_recognition_service.dart';
import '../services/voice/speech_voice_service.dart';
import '../services/visits/visit_tracker.dart';
import '../services/tracking/tracking_query_engine.dart';
import '../core/models/geo.dart';
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
    required this.queryEngine,
    required this.navigation,
    required this.assistant,
    required this.speechVoices,
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
  final LocalQueryEngine queryEngine;
  final NavigationService navigation;
  final AssistantEngine assistant;
  final SpeechVoiceService speechVoices;
  static Future<AppDependencies> create() async {
    final preferences = await SharedPreferences.getInstance();
    final poi = SqlitePoiRepository();
    final privateData = SqlitePrivateDataStore();
    const useMockLocation = bool.fromEnvironment('USE_MOCK_LOCATION');
    final mockLatitude = double.parse(
      const String.fromEnvironment('MOCK_LATITUDE', defaultValue: '35.1'),
    );
    final mockLongitude = double.parse(
      const String.fromEnvironment('MOCK_LONGITUDE', defaultValue: '-89.6'),
    );
    final LocationService location = useMockLocation
        ? MockLocationService(Coordinates(mockLatitude, mockLongitude))
        : GeolocatorLocationService();
    final resolver = LocationRegionResolver();
    final packages = OvertureRegionPackageManager(
      preferences,
      poi,
      const OverturePackageSource(),
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
    final nearby = NearbyService(poi);
    final driving = DrivingContextEngine(
      privateData: privateData,
      routines: routines,
      nearby: nearby,
      notifications: notifications,
      profiles: profiles,
      preferences: preferences,
    );
    final queryContext = BoundedConversationContext();
    final queryEngine = LocalQueryEngine(
      interpreter: RuleBasedQueryInterpreter(),
      contextResolver: QueryContextResolver(queryContext),
      registry: CapabilityRegistry([
        FindPoiCapability(nearby),
        DistanceCapability(nearby),
        ComparisonCapability(nearby),
        NavigationCapability(nearby),
      ]),
      responseGenerator: const TemplateQueryResponseGenerator(),
      context: queryContext,
    );
    final bootstrap = BootstrapService(
      poiRepository: poi,
      privateDataStore: privateData,
      locationService: location,
      regionResolver: resolver,
      packageManager: packages,
      voiceService: voice,
      notificationService: notifications,
    );
    final commands = DeterministicCommandInterpreter();
    final assistant = AssistantEngine(
      queries: queryEngine,
      commands: commands,
      bootstrap: bootstrap,
      packages: packages,
      nearby: nearby,
      profiles: profiles,
      tracking: TrackingQueryEngine(privateData),
    );
    return AppDependencies._(
      packages: packages,
      nearby: nearby,
      commands: commands,
      voice: voice,
      privateData: privateData,
      visitTracker: VisitTracker(
        location,
        poi,
        privateData,
        onObservation: routines.evaluate,
        onLocation: driving.observe,
      ),
      themeController: AppThemeController(preferences),
      profileService: profiles,
      routineEngine: routines,
      queryEngine: queryEngine,
      navigation: const PlatformNavigationService(),
      assistant: assistant,
      speechVoices: const SpeechVoiceService(),
      bootstrap: bootstrap,
    );
  }
}
