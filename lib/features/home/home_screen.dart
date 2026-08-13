import 'package:flutter/material.dart';
import '../../app/app_dependencies.dart';
import '../nearby/nearby_screen.dart';
import '../settings/privacy_screen.dart';
import '../voice_assistant/voice_assistant_screen.dart';
import '../visits/most_visited_screen.dart';
import '../visits/my_places_screen.dart';
import '../../services/storage/private_data_store.dart';
import '../../core/models/unknown_place_candidate.dart';
import '../../core/models/region.dart';
import '../routines/routines_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int? _promptedUnknownId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.dependencies.visitTracker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _suggestUnknownPlace());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.dependencies.visitTracker.start();
      _suggestUnknownPlace();
    }
  }

  Future<void> _suggestUnknownPlace() async {
    if (!mounted) return;
    final candidate = await widget.dependencies.privateData
        .pendingUnknownSuggestion();
    if (!mounted || candidate == null || candidate.id == _promptedUnknownId) {
      return;
    }
    _promptedUnknownId = candidate.id;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.add_location_alt_outlined),
        title: const Text('A place you visit often'),
        content: Text(
          'You have stayed at the same unknown place ${candidate.visitCount} times. Would you like to add it to your private places?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'dismiss'),
            child: const Text('Don’t ask again'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'later'),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'add'),
            child: const Text('Add place'),
          ),
        ],
      ),
    );
    if (result == 'dismiss') {
      await widget.dependencies.privateData.dismissUnknownSuggestion(
        candidate.id,
      );
    } else if (result == 'add' && mounted) {
      await _nameUnknownPlace(candidate);
    }
  }

  Future<void> _nameUnknownPlace(UnknownPlaceCandidate candidate) async {
    final controller = TextEditingController();
    var category = 'other';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add private place'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Place name',
                  hintText: 'For example, Tony’s Trophy Room',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const [
                  DropdownMenuItem(
                    value: 'restaurant',
                    child: Text('Restaurant'),
                  ),
                  DropdownMenuItem(value: 'work', child: Text('Work')),
                  DropdownMenuItem(value: 'home', child: Text('Home')),
                  DropdownMenuItem(value: 'shop', child: Text('Shop')),
                  DropdownMenuItem(
                    value: 'recreation',
                    child: Text('Recreation'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) =>
                    setDialogState(() => category = value ?? 'other'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (saved != true || name.isEmpty) return;
    try {
      await widget.dependencies.privateData.saveCustomPlace(
        name: name,
        tag: category,
        coordinates: candidate.coordinates,
      );
      await widget.dependencies.privateData.resolveUnknownSuggestion(
        candidate.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name added to your private places.')),
        );
      }
    } on CustomPlaceConflictException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'That private place already exists. Use another name.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _showHomeAreaDialog({Region? initial}) async {
    final coordinates = widget.dependencies.bootstrap.coordinates;
    if (coordinates == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Current location is unavailable, so a home area cannot be identified.',
            ),
          ),
        );
      }
      return;
    }
    final options = await widget.dependencies.bootstrap.regionResolver.options(
      coordinates,
    );
    if (options.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The current location could not be prepared for offline use.',
            ),
          ),
        );
      }
      return;
    }
    final installed = <String, bool>{};
    for (final option in options) {
      installed[option.id] = await widget.dependencies.packages.isCurrent(
        option,
      );
    }
    if (!mounted) return;
    Region? installedSelection;
    for (final option in options) {
      if (installed[option.id] == true) {
        installedSelection = option;
        break;
      }
    }
    var selected =
        initial ??
        installedSelection ??
        options.firstWhere(
          (option) => option.coverageMiles == 50,
          orElse: () => options.first,
        );
    var installing = false;
    var progress = 0.0;
    String? progressText;
    String? errorText;
    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final alreadyInstalled = installed[selected.id] == true;
          return AlertDialog(
            icon: const Icon(Icons.home_work_outlined, size: 40),
            title: Text('${selected.displayName} home area'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'This area is centered on your device’s current location. The city name is only a label. Choose how far offline place search should extend.',
                ),
                const SizedBox(height: 18),
                SegmentedButton<int>(
                  segments: [
                    for (final option in options)
                      ButtonSegment(
                        value: option.coverageMiles,
                        label: Text('${option.coverageMiles} mi'),
                      ),
                  ],
                  selected: {selected.coverageMiles},
                  onSelectionChanged: installing
                      ? null
                      : (values) => setDialogState(() {
                          selected = options.firstWhere(
                            (option) => option.coverageMiles == values.single,
                          );
                          errorText = null;
                        }),
                ),
                const SizedBox(height: 14),
                Text(
                  '${_formatBytes(selected.approximateBytes)} estimated download${selected.approximatePoiCount == null ? '' : ' • approximately ${selected.approximatePoiCount} places'}',
                ),
                const SizedBox(height: 10),
                Text(
                  alreadyInstalled
                      ? 'This home area is already installed. Update will force a fresh verified package download and replace its local POIs.'
                      : installed.values.any((value) => value)
                      ? 'Changing coverage replaces the currently installed home-area package.'
                      : selected.coverageMiles == 50
                      ? 'Recommended default: broad local coverage with a small download.'
                      : 'Larger coverage takes more storage and installation time.',
                ),
                if (installing) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text(progressText ?? 'Preparing offline places…'),
                ],
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: installing
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: installing
                    ? null
                    : () async {
                        setDialogState(() {
                          installing = true;
                          errorText = null;
                        });
                        try {
                          await for (final update
                              in widget.dependencies.packages.install(
                                selected,
                              )) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              progress = update.fraction;
                              progressText = update.message;
                            });
                          }
                          widget.dependencies.bootstrap.selectInstalledRegion(
                            selected,
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (error) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            installing = false;
                            errorText = '$error';
                          });
                        }
                      },
                icon: Icon(
                  alreadyInstalled ? Icons.refresh : Icons.download_outlined,
                ),
                label: Text(alreadyInstalled ? 'Update' : 'Install'),
              ),
            ],
          );
        },
      ),
    );
    if (completed == true && mounted) setState(() {});
  }

  Future<void> _confirmRemoveRegion(Region region) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove offline home area?'),
        content: Text(
          '${region.displayName} ${region.coverageMiles}-mile offline POIs will be removed. Private visits and custom places are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.dependencies.packages.delete(region);
    if (mounted) setState(() {});
  }

  String _formatBytes(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).ceil()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

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
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PrivacyScreen(
                  privateData: widget.dependencies.privateData,
                  profileService: widget.dependencies.profileService,
                  speechVoices: widget.dependencies.speechVoices,
                ),
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
                  if (region == null)
                    const Text(
                      'No supported home area was detected at this location.',
                    )
                  else
                    FutureBuilder<bool>(
                      future: widget.dependencies.packages.isCurrent(region),
                      builder: (context, snapshot) => Text(
                        snapshot.data == true
                            ? 'Home area installed • ${region.coverageMiles}-mile coverage'
                            : 'Home area detected • Offline places not installed',
                      ),
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
            icon: const Icon(Icons.auto_graph),
            label: const Text('Learned routines'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RoutinesScreen(engine: widget.dependencies.routineEngine),
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
                  visitTracker: widget.dependencies.visitTracker,
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
                        leading: Icon(
                          region?.id == r.id
                              ? Icons.radio_button_checked
                              : Icons.download_done,
                        ),
                        title: Text(r.displayName),
                        subtitle: Text(
                          'Overture Maps • ${r.coverageMiles} miles • version ${r.installedVersion}',
                        ),
                        onTap: () => setState(
                          () => widget.dependencies.bootstrap
                              .selectInstalledRegion(r),
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Region actions',
                          onSelected: (action) async {
                            if (action == 'select') {
                              setState(
                                () => widget.dependencies.bootstrap
                                    .selectInstalledRegion(r),
                              );
                            } else if (action == 'update') {
                              await _showHomeAreaDialog(initial: r);
                            } else if (action == 'remove') {
                              await _confirmRemoveRegion(r);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'select',
                              child: Text('Use this coverage'),
                            ),
                            PopupMenuItem(
                              value: 'update',
                              child: Text('Update / reinstall'),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove offline data'),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.map_outlined),
            label: const Text('Install or update home area'),
            onPressed: _showHomeAreaDialog,
          ),
        ],
      ),
    );
  }
}
