import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/app_dependencies.dart';
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
  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start({bool requestLocation = false}) {
    subscription?.cancel();
    subscription = widget.dependencies.bootstrap
        .run(requestLocation: requestLocation)
        .listen((value) {
          if (!mounted) return;
          setState(() => update = value);
          if (value.ready) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => HomeScreen(dependencies: widget.dependencies),
              ),
            );
          }
        });
  }

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
