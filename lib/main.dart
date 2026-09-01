import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_dependencies.dart';
import 'core/models/user_profile.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppDependencies.create();
  const e2eProfile = bool.fromEnvironment('E2E_TEST_PROFILE');
  if (e2eProfile) {
    await dependencies.profileService.save(
      const UserProfile(
        addressStyle: 'name',
        name: 'Tester',
        personality: 'warm',
      ),
    );
  }
  runApp(PrivateConciergeApp(dependencies: dependencies));
}
