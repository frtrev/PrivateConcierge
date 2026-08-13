import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/storage/private_data_store.dart';
import '../../services/profile/user_profile_service.dart';
import '../../services/voice/speech_voice_service.dart';
import '../onboarding/profile_onboarding_screen.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({
    super.key,
    required this.privateData,
    required this.profileService,
    required this.speechVoices,
  });
  final PrivateDataStore privateData;
  final UserProfileService profileService;
  final SpeechVoiceService speechVoices;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ListTile(
          leading: const Icon(Icons.record_voice_over_outlined),
          title: const Text('Assistant profile and voice'),
          subtitle: const Text('Address, personality, and spoken voice'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ProfileOnboardingScreen(
                initialProfile: profileService.load(),
                editing: true,
                speechVoices: speechVoices,
                onComplete: (profile) async {
                  await profileService.save(profile);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
          ),
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.location_on_outlined),
          title: Text('Location processing'),
          subtitle: Text('On device'),
        ),
        const ListTile(
          leading: Icon(Icons.mic_none),
          title: Text('Voice processing'),
          subtitle: Text('On device when supported'),
        ),
        const ListTile(
          leading: Icon(Icons.phone_android),
          title: Text('Personal data storage'),
          subtitle: Text('This device only'),
        ),
        const ListTile(
          leading: Icon(Icons.person_off_outlined),
          title: Text('Account'),
          subtitle: Text('None'),
        ),
        const ListTile(
          leading: Icon(Icons.cloud_off_outlined),
          title: Text('Location uploaded to our servers'),
          subtitle: Text('Never'),
        ),
        const ListTile(
          leading: Icon(Icons.public_outlined),
          title: Text('Offline places data'),
          subtitle: Text(
            'Static Overture Maps region packages are downloaded without sending your coordinates.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Public data attribution'),
          subtitle: const Text(
            'Overture Maps Foundation • includes Apache-2.0 Foursquare places',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showAttribution(context),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.history_outlined),
          title: const Text('Delete location history'),
          subtitle: const Text('Removes locally recorded visited places'),
          onTap: () async {
            await privateData.deleteVisitHistory();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Visit history deleted.')),
              );
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.home_work_outlined),
          title: const Text('Delete custom places'),
          subtitle: const Text('Removes Home, Work, and other private POIs'),
          onTap: () async {
            await privateData.deleteCustomPlaces();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Custom places deleted.')),
              );
            }
          },
        ),
        const ListTile(enabled: false, title: Text('Delete reminders')),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete everything I know'),
          onPressed: () async {
            await privateData.deleteEverything();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'All private local data deleted. Downloaded public regions were kept.',
                  ),
                ),
              );
            }
          },
        ),
      ],
    ),
  );

  Future<void> _showAttribution(BuildContext context) async {
    final notice = await rootBundle.loadString(
      'assets/licenses/Foursquare-NOTICE.txt',
    );
    final license = await rootBundle.loadString(
      'assets/licenses/APACHE-2.0.txt',
    );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Offline places attribution'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Text(
              'Overture Maps Foundation\nhttps://overturemaps.org\n\n$notice\n\n$license',
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
