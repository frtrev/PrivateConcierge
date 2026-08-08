import 'package:flutter/material.dart';
import '../../services/storage/private_data_store.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, required this.privateData});
  final PrivateDataStore privateData;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
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
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Public data attribution'),
          subtitle: Text('Overture Maps Foundation • overturemaps.org'),
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
}
