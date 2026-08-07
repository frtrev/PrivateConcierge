import 'package:flutter/material.dart';
import '../features/loading/bootstrap_screen.dart';
import 'app_dependencies.dart';

class PrivateConciergeApp extends StatelessWidget {
  const PrivateConciergeApp({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Private Concierge',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff245b55),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff6f7f2),
    ),
    home: BootstrapScreen(dependencies: dependencies),
  );
}
