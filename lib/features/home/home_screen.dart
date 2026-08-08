import 'package:flutter/material.dart';
import '../../app/app_dependencies.dart';
import '../nearby/nearby_screen.dart';
import '../settings/privacy_screen.dart';
import '../voice_assistant/voice_assistant_screen.dart';
import '../../services/geography/region_resolver.dart';
import '../../core/models/region.dart';
import '../../services/downloads/region_package_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _downloadRegion(Region region, {bool activate = true}) async {
    Object? failure;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Downloading ${region.displayName}'),
          content: StreamBuilder<PackageProgress>(
            stream: widget.dependencies.packages.install(region),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                failure = snapshot.error;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                });
                return Text('Download failed: ${snapshot.error}');
              }
              final progress = snapshot.data;
              if (snapshot.connectionState == ConnectionState.done) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                });
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: progress?.fraction),
                  const SizedBox(height: 16),
                  Text(progress?.message ?? 'Connecting to OpenStreetMap…'),
                  const SizedBox(height: 12),
                  const Text(
                    'Only this fixed region boundary is sent. Your location is not included.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not download POIs: $failure')),
      );
      return;
    }
    if (activate) {
      await widget.dependencies.bootstrap.activateDevelopmentRegion(region);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = widget.dependencies.bootstrap;
    final region = bootstrap.region;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Private Concierge'),
        actions: [
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
                        : 'Downloaded • version ${region.version}',
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
                        subtitle: FutureBuilder<int?>(
                          future: widget.dependencies.packages
                              .installedPoiCount(r),
                          builder: (context, countSnapshot) => Text(
                            countSnapshot.data == null
                                ? 'OpenStreetMap data • version ${r.installedVersion}'
                                : '${countSnapshot.data} real POIs • OpenStreetMap',
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Refresh real POIs',
                          icon: const Icon(Icons.refresh),
                          onPressed: () => _downloadRegion(r, activate: false),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.map_outlined),
            label: const Text('Select development region'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (sheetContext) => ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(
                    title: Text('Download a real POI region'),
                    subtitle: Text(
                      'Downloads current OpenStreetMap places, then uses the region center as mock GPS.',
                    ),
                  ),
                  for (final candidate in bundledRegions)
                    ListTile(
                      leading: const Icon(Icons.location_city),
                      title: Text(candidate.displayName),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await _downloadRegion(candidate);
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'POI data © OpenStreetMap contributors • ODbL\nhttps://www.openstreetmap.org/copyright',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
