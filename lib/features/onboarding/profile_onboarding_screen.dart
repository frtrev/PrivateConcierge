import 'package:flutter/material.dart';

import '../../core/models/user_profile.dart';

class ProfileOnboardingScreen extends StatefulWidget {
  const ProfileOnboardingScreen({super.key, required this.onComplete});

  final Future<void> Function(UserProfile profile) onComplete;

  @override
  State<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState extends State<ProfileOnboardingScreen> {
  final nameController = TextEditingController();
  String address = 'name';
  String personality = 'warm';
  bool saving = false;

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const SizedBox(height: 30),
          Icon(
            Icons.auto_awesome,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Make your concierge yours',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'This profile stays on your device and controls how your assistant speaks to you.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: nameController,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name or preferred form of address',
              hintText: 'Francisco',
            ),
          ),
          const SizedBox(height: 20),
          const Text('How should I address you?'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'mr', label: Text('Mr.')),
              ButtonSegment(value: 'maam', label: Text('Ma’am')),
              ButtonSegment(value: 'name', label: Text('By name')),
              ButtonSegment(value: 'other', label: Text('Other')),
            ],
            selected: {address},
            onSelectionChanged: (value) =>
                setState(() => address = value.single),
          ),
          const SizedBox(height: 24),
          const Text('Assistant personality'),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: personality,
            onChanged: (value) => setState(() => personality = value!),
            child: const Column(
              children: [
                RadioListTile(
                  value: 'warm',
                  title: Text('Warm and thoughtful'),
                ),
                RadioListTile(
                  value: 'professional',
                  title: Text('Polished and concise'),
                ),
                RadioListTile(
                  value: 'playful',
                  title: Text('Friendly and playful'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: saving || nameController.text.trim().isEmpty
                ? null
                : () async {
                    setState(() => saving = true);
                    await widget.onComplete(
                      UserProfile(
                        addressStyle: address,
                        name: nameController.text.trim(),
                        personality: personality,
                      ),
                    );
                  },
            icon: const Icon(Icons.check),
            label: Text(saving ? 'Saving…' : 'Continue'),
          ),
        ],
      ),
    ),
  );
}
