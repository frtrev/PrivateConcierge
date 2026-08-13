import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/loading/bootstrap_screen.dart';
import '../features/onboarding/profile_onboarding_screen.dart';
import '../features/voice_assistant/voice_assistant_screen.dart';
import 'app_dependencies.dart';
import 'app_theme_controller.dart';

class PrivateConciergeApp extends StatefulWidget {
  const PrivateConciergeApp({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<PrivateConciergeApp> createState() => _PrivateConciergeAppState();
}

class _PrivateConciergeAppState extends State<PrivateConciergeApp> {
  static const _carChannel = MethodChannel('charon/car');
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _voiceController = VoiceAssistantController();
  bool _openingAssistant = false;

  @override
  void initState() {
    super.initState();
    _carChannel.setMethodCallHandler((call) async {
      if (call.method == 'talkRequested') {
        _openAssistant();
        return true;
      }
      if (call.method == 'submitRecognizedText') {
        final text = call.arguments as String? ?? '';
        final result = await widget.dependencies.assistant.answer(text);
        return result.toMap();
      }
      if (call.method == 'submitText') {
        final text = call.arguments as String? ?? '';
        final result = await widget.dependencies.assistant.answer(text);
        return result.toMap();
      }
      return null;
    });
    _consumePendingCarAction();
  }

  Future<void> _consumePendingCarAction() async {
    final pending = await _carChannel.invokeMethod<bool>('consumeTalkRequest');
    if (pending == true) _openAssistant();
  }

  void _openAssistant() {
    if (_openingAssistant) {
      _voiceController.requestListening();
      return;
    }
    _openingAssistant = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navigator = _navigatorKey.currentState;
      if (navigator != null) {
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => VoiceAssistantScreen(
              dependencies: widget.dependencies,
              autoStart: true,
              controller: _voiceController,
            ),
          ),
        );
      }
      _openingAssistant = false;
    });
  }

  @override
  void dispose() {
    _carChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.dependencies.themeController,
    builder: (context, _) => MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Private Concierge',
      debugShowCheckedModeBanner: false,
      theme: PrivateConciergeThemes.light,
      darkTheme: PrivateConciergeThemes.dark,
      themeMode: widget.dependencies.themeController.mode,
      home: widget.dependencies.profileService.load() == null
          ? ProfileOnboardingScreen(
              speechVoices: widget.dependencies.speechVoices,
              onComplete: (profile) async {
                await widget.dependencies.profileService.save(profile);
                if (mounted) setState(() {});
              },
            )
          : BootstrapScreen(dependencies: widget.dependencies),
    ),
  );
}
