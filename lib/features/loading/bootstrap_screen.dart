import 'dart:async';
import 'package:flutter/material.dart';
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
      (option) => option.coverageMiles == 25,
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
                selected.coverageMiles == 25
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
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.shield_outlined, size: 76),
            const SizedBox(height: 18),
            Text(
              'Private Concierge',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'The phone is the assistant.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 42),
            LinearProgressIndicator(value: update.progress),
            const SizedBox(height: 16),
            Text(update.status, textAlign: TextAlign.center),
            if (update.requiresLocationExplanation) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _start(requestLocation: true),
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Continue with location'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) =>
                        HomeScreen(dependencies: widget.dependencies),
                  ),
                ),
                child: const Text('Not now'),
              ),
            ],
            if (update.error != null) ...[
              const SizedBox(height: 16),
              Text(
                '${update.error}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _start, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    ),
  );
}
