import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/app_dependencies.dart';
import '../../core/models/region.dart';
import '../home/home_screen.dart';
import 'bootstrap_service.dart';

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  BootstrapUpdate update = const BootstrapUpdate(
    progress: 0,
    status: 'Starting…',
  );
  StreamSubscription<BootstrapUpdate>? subscription;
  bool dialogOpen = false;
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start({bool requestLocation = false, Region? confirmedRegion}) {
    subscription?.cancel();
    subscription = widget.dependencies.bootstrap
        .run(requestLocation: requestLocation, confirmedRegion: confirmedRegion)
        .listen((value) {
          if (!mounted) return;
          setState(() => update = value);
          if (value.downloadOptions.isNotEmpty && !dialogOpen) {
            unawaited(_showRegionDownload(value.downloadOptions));
          }
          if (value.ready) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => HomeScreen(dependencies: widget.dependencies),
              ),
            );
          }
        });
  }

  Future<void> _showRegionDownload(List<Region> options) async {
    dialogOpen = true;
    var selected = options.firstWhere(
      (option) => option.coverageMiles == 50,
      orElse: () => options.first,
    );
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.download_for_offline_outlined, size: 40),
          title: const Text('Set up offline places'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Private Concierge will make a one-time download for ${selected.displayName}. Your location is not included in the request.',
              ),
              const SizedBox(height: 20),
              const Text('Choose coverage'),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: [
                  for (final option in options)
                    ButtonSegment<int>(
                      value: option.coverageMiles,
                      label: Text('${option.coverageMiles} miles'),
                    ),
                ],
                selected: {selected.coverageMiles},
                onSelectionChanged: (selection) => setDialogState(() {
                  selected = options.firstWhere(
                    (option) => option.coverageMiles == selection.single,
                  );
                }),
              ),
              const SizedBox(height: 16),
              Text(
                'About ${_formatBytes(selected.approximateBytes)} • approximately ${selected.approximatePoiCount ?? 0} places',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                selected.coverageMiles == 50
                    ? 'Recommended for a faster first setup.'
                    : 'Broader coverage takes more storage and longer to install.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.of(this.context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) =>
                        HomeScreen(dependencies: widget.dependencies),
                  ),
                );
              },
              child: const Text('Not now'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _start(requestLocation: true, confirmedRegion: selected);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download once'),
            ),
          ],
        ),
      ),
    );
    dialogOpen = false;
  }

  String _formatBytes(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).ceil()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
    ),
    child: Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/splashscreen.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
              Positioned(
                left: constraints.maxWidth * .14,
                right: constraints.maxWidth * .14,
                bottom: height * .025,
                height: height * .125,
                child: Container(
                  color: const Color(0xff050505),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'L O A D I N G',
                        style: TextStyle(
                          color: Color(0xffe5b956),
                          fontSize: 16,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: update.progress,
                          minHeight: 6,
                          backgroundColor: const Color(0xff272727),
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xffe5b956),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        update.status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xffe5b956),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (update.requiresLocationExplanation || update.error != null)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: height * .17,
                  child: Card(
                    color: const Color(0xf2141414),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            update.error == null
                                ? 'Use your location to select private offline coverage. Coordinates stay on this device.'
                                : '${update.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: update.error == null
                                  ? Colors.white
                                  : const Color(0xffff8a80),
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (update.requiresLocationExplanation) ...[
                            FilledButton.icon(
                              onPressed: () => _start(requestLocation: true),
                              icon: const Icon(Icons.location_on_outlined),
                              label: const Text('Continue with location'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => HomeScreen(
                                        dependencies: widget.dependencies,
                                      ),
                                    ),
                                  ),
                              child: const Text('Not now'),
                            ),
                          ] else
                            FilledButton(
                              onPressed: _start,
                              child: const Text('Retry'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
