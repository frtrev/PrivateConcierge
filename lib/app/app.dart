import 'package:flutter/material.dart';
import '../features/loading/bootstrap_screen.dart';
import 'app_dependencies.dart';
import 'app_theme_controller.dart';

class PrivateConciergeApp extends StatelessWidget {
  const PrivateConciergeApp({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: dependencies.themeController,
    builder: (context, _) => MaterialApp(
      title: 'Private Concierge',
      debugShowCheckedModeBanner: false,
      theme: PrivateConciergeThemes.light,
      darkTheme: PrivateConciergeThemes.dark,
      themeMode: dependencies.themeController.mode,
      home: BootstrapScreen(dependencies: dependencies),
    ),
  );
}
