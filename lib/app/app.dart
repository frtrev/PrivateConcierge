import 'package:flutter/material.dart';
import '../features/loading/bootstrap_screen.dart';
import '../features/onboarding/profile_onboarding_screen.dart';
import 'app_dependencies.dart';
import 'app_theme_controller.dart';

class PrivateConciergeApp extends StatefulWidget {
  const PrivateConciergeApp({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<PrivateConciergeApp> createState() => _PrivateConciergeAppState();
}

class _PrivateConciergeAppState extends State<PrivateConciergeApp> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.dependencies.themeController,
    builder: (context, _) => MaterialApp(
      title: 'Private Concierge',
      debugShowCheckedModeBanner: false,
      theme: PrivateConciergeThemes.light,
      darkTheme: PrivateConciergeThemes.dark,
      themeMode: widget.dependencies.themeController.mode,
      home: widget.dependencies.profileService.load() == null
          ? ProfileOnboardingScreen(
              onComplete: (profile) async {
                await widget.dependencies.profileService.save(profile);
                if (mounted) setState(() {});
              },
            )
          : BootstrapScreen(dependencies: widget.dependencies),
    ),
  );
}
