import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/local_ai/development_local_ai_service.dart';
import '../../services/local_ai/local_ai_models.dart';

class LocalAiSettingsSection extends StatefulWidget {
  const LocalAiSettingsSection({super.key, required this.service});
  final DevelopmentLocalAiService service;
  @override
  State<LocalAiSettingsSection> createState() => _LocalAiSettingsSectionState();
}

class _LocalAiSettingsSectionState extends State<LocalAiSettingsSection> {
  LocalAiStatus? status;
  ModelCompatibilityResult? compatibility;
  ModelDownloadProgress? progress;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      widget.service.getStatus(),
      widget.service.checkCompatibility(),
    ]);
    if (mounted) {
      setState(() {
        status = values[0] as LocalAiStatus;
        compatibility = values[1] as ModelCompatibilityResult;
      });
    }
  }

  String _bytes(int value) => value <= 0
      ? 'Not available'
      : '${(value / 1048576).toStringAsFixed(0)} MB';

  LocalAiModelState? get _effectiveState => progress?.state ?? status?.state;

  bool get _isTransfer =>
      _effectiveState == LocalAiModelState.downloading ||
      _effectiveState == LocalAiModelState.paused ||
      _effectiveState == LocalAiModelState.verifying ||
      _effectiveState == LocalAiModelState.installing ||
      _effectiveState == LocalAiModelState.waitingForWifi;

  @override
  Widget build(BuildContext context) {
    final current = status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.psychology_outlined),
              title: Text('Charon Local AI'),
              subtitle: Text(
                'Enhanced private, offline understanding for more natural requests.',
              ),
            ),
            const Text(
              'Requests are processed on this device. Existing online map and business providers retain their established behavior.',
            ),
            const SizedBox(height: 12),
            if (widget.service.manifest.developmentOnly)
              const Text(
                'Developer preview: no verified downloadable model is configured.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 8),
            Text(
              'Download size: ${_bytes(widget.service.manifest.downloadSizeBytes)}',
            ),
            Text(
              'Installed size: ${_bytes(widget.service.manifest.installedSizeBytes)}',
            ),
            Text(
              'Device compatibility: ${compatibility?.message ?? 'Checking…'}',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Download on Wi-Fi only'),
              value: current?.wifiOnly ?? true,
              onChanged: (value) async {
                await widget.service.setWifiOnly(value);
                await _load();
              },
            ),
            if (_isTransfer) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (progress?.totalBytes ?? current?.totalBytes ?? 0) <= 0
                    ? null
                    : (progress?.fraction ??
                          ((current?.downloadedBytes ?? 0) /
                              (current?.totalBytes ?? 1))),
              ),
              const SizedBox(height: 8),
              Text(
                '${_stateLabel(_effectiveState)} • ${_bytes(progress?.downloadedBytes ?? current?.downloadedBytes ?? 0)} of ${_bytes(progress?.totalBytes ?? current?.totalBytes ?? 0)}',
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _effectiveState == LocalAiModelState.verifying ||
                              _effectiveState == LocalAiModelState.installing
                          ? null
                          : () async {
                              if (_effectiveState == LocalAiModelState.paused) {
                                await _resume();
                              } else {
                                await widget.service.pauseDownload();
                                await _load();
                              }
                            },
                      child: Text(
                        _effectiveState == LocalAiModelState.paused
                            ? 'Resume'
                            : 'Pause',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        await widget.service.cancelDownload();
                        await _load();
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ] else if (current?.state == LocalAiModelState.ready) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Local AI enabled'),
                value: current!.enabled,
                onChanged: (v) async {
                  await widget.service.setEnabled(v);
                  await _load();
                },
              ),
              Text('Model version: ${current.modelVersion ?? 'Unknown'}'),
              Text(
                current.lastInferenceAt == null
                    ? 'Last used: not yet'
                    : 'Last used: ${_time(current.lastInferenceAt!)} • ${current.lastInferenceIntent ?? 'unknown'}',
              ),
              if (current.lastInferenceError?.isNotEmpty == true)
                Text(
                  current.lastInferenceError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              OutlinedButton(
                onPressed: () async {
                  await widget.service.deleteModel();
                  await _load();
                },
                child: const Text('Remove Local AI'),
              ),
            ] else
              FilledButton.icon(
                onPressed:
                    widget.service.manifest.hasProductionArtifact && !busy
                    ? () => _confirmDownload(context)
                    : null,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download Local AI'),
              ),
            if (current?.error?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                current!.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (kDebugMode) ...[
              const Divider(),
              Text(
                'Diagnostics • state=${current?.state.name ?? 'loading'} • manifest=${widget.service.manifest.modelVersion} • runtime=GGUF • path=${_redact(current?.fileLocation)}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _redact(String? path) =>
      path == null ? 'none' : '…/${path.split('/').last}';

  String _stateLabel(LocalAiModelState? state) => switch (state) {
    LocalAiModelState.downloading => 'Downloading',
    LocalAiModelState.paused => 'Paused',
    LocalAiModelState.verifying => 'Verifying download',
    LocalAiModelState.installing => 'Testing and installing',
    LocalAiModelState.waitingForWifi => 'Waiting for Wi-Fi',
    _ => 'Preparing',
  };

  String _time(DateTime value) {
    final local = value.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${local.hour}:$minute';
  }

  Future<void> _confirmDownload(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Download Charon Local AI?'),
            content: Text(
              '${_bytes(widget.service.manifest.downloadSizeBytes)} download. Model data is stored privately on this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Download'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => busy = true);
    try {
      await widget.service.downloadModel(
        onProgress: (value) {
          if (mounted) {
            setState(() => progress = value);
            if (value.state == LocalAiModelState.ready ||
                value.state == LocalAiModelState.failed ||
                value.state == LocalAiModelState.corrupted ||
                value.state == LocalAiModelState.insufficientStorage ||
                value.state == LocalAiModelState.incompatible) {
              _load();
            }
          }
        },
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          this.context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
    if (mounted) setState(() => busy = false);
    await _load();
  }

  Future<void> _resume() async {
    setState(() => busy = true);
    try {
      await widget.service.resumeDownload();
    } finally {
      if (mounted) setState(() => busy = false);
      await _load();
    }
  }
}
