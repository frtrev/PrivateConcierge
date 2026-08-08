import 'package:flutter/material.dart';
import '../../app/app_dependencies.dart';
import '../nearby/nearby_screen.dart';
import '../settings/privacy_screen.dart';
import '../voice_assistant/voice_assistant_screen.dart';
import '../visits/most_visited_screen.dart';
import '../visits/my_places_screen.dart';
import '../../services/geography/region_resolver.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.dependencies.visitTracker.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.dependencies.visitTracker.start();
    } else {
      widget.dependencies.visitTracker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.dependencies.visitTracker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = widget.dependencies.bootstrap;
    final region = bootstrap.region;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Private Concierge'),
        actions: [
          ListenableBuilder(
            listenable: widget.dependencies.themeController,
            builder: (context, _) => Tooltip(
              message: widget.dependencies.themeController.isDark
                  ? 'Use light theme'
                  : 'Use dark theme',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.dependencies.themeController.isDark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    size: 20,
                  ),
                  Switch(
                    value: widget.dependencies.themeController.isDark,
                    onChanged: widget.dependencies.themeController.setDark,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Privacy settings',
            icon: const Icon(Icons.privacy_tip_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PrivacyScreen(privateData: widget.dependencies.privateData),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CURRENT REGION'),
                  const SizedBox(height: 8),
                  Text(
                    region?.displayName ?? 'Not selected',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    region == null
                        ? 'Choose a downloaded region to use nearby search.'
                        : 'Downloaded • ${region.coverageMiles}-mile coverage',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
            ),
            icon: const Icon(Icons.mic),
            label: const Text('Talk to your assistant'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    VoiceAssistantScreen(dependencies: widget.dependencies),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.home_work_outlined),
            label: const Text('My places'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MyPlacesScreen(
                  privateData: widget.dependencies.privateData,
                  getCurrentLocation:
                      widget.dependencies.bootstrap.refreshCurrentLocation,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.insights_outlined),
            label: const Text('Most visited places'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MostVisitedScreen(
                  privateData: widget.dependencies.privateData,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.near_me_outlined),
            label: const Text('Explore nearby'),
            onPressed: bootstrap.coordinates == null
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          NearbyScreen(dependencies: widget.dependencies),
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          Text(
            'Installed regions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          FutureBuilder(
            future: widget.dependencies.packages.installedRegions(),
            builder: (context, snapshot) {
              final regions = snapshot.data ?? [];
              if (regions.isEmpty) {
                return const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('No regions downloaded'),
                );
              }
              return Column(
                children: regions
                    .map(
                      (r) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.download_done),
                        title: Text(r.displayName),
                        subtitle: Text(
                          'Overture Maps • ${r.coverageMiles} miles • version ${r.installedVersion}',
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.map_outlined),
            label: const Text('Download an offline region'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (sheetContext) => ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    title: Text('Overture Maps regions'),
                    subtitle: Text(
                      'Downloads a verified static Places package. Choosing a region also uses its center as the development location.',
                    ),
                  ),
                  for (final candidate in bundledRegions)
                    ListTile(
                      leading: const Icon(Icons.location_city),
                      title: Text(
                        '${candidate.displayName} • ${candidate.coverageMiles} miles',
                      ),
                      onTap: () async {
                        await widget.dependencies.bootstrap
                            .selectDevelopmentRegion(candidate);
                        if (!sheetContext.mounted) return;
                        Navigator.pop(sheetContext);
                        setState(() {});
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
