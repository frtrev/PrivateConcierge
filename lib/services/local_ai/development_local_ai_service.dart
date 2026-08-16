import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:lib_llama_cpp/lib_llama_cpp.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_ai_models.dart';
import 'local_ai_response_cleaner.dart';
import 'model_manifest.dart';

class DevelopmentLocalAiService implements LocalAiService {
  DevelopmentLocalAiService(this._preferences, this.manifest);
  final SharedPreferences _preferences;
  final ModelManifest manifest;
  static const _channel = MethodChannel('charon/local_ai');
  static const _prefix = 'charon.local_ai.';
  HttpClient? _client;
  bool _paused = false;
  bool _cancelled = false;
  void Function(ModelDownloadProgress progress)? _onProgress;
  LlamaOpenAIClient? _chat;
  String? _loadedModelPath;

  @override
  Future<LocalAiStatus> getStatus() async {
    final stateName = _preferences.getString('${_prefix}state');
    var state =
        LocalAiModelState.values
            .where((v) => v.name == stateName)
            .firstOrNull ??
        LocalAiModelState.notInstalled;
    if (state == LocalAiModelState.downloading) {
      state = LocalAiModelState.paused;
      await _preferences.setString('${_prefix}state', state.name);
    }
    return LocalAiStatus(
      state: state,
      enabled: _preferences.getBool('${_prefix}enabled') ?? false,
      modelId: _preferences.getString('${_prefix}modelId'),
      modelVersion: _preferences.getString('${_prefix}modelVersion'),
      fileLocation: _preferences.getString('${_prefix}fileLocation'),
      expectedSha256: _preferences.getString('${_prefix}expectedSha256'),
      actualSha256: _preferences.getString('${_prefix}actualSha256'),
      downloadedBytes: _preferences.getInt('${_prefix}downloadedBytes') ?? 0,
      totalBytes: _preferences.getInt('${_prefix}totalBytes') ?? 0,
      lastVerified: _date('${_prefix}lastVerified'),
      wifiOnly: _preferences.getBool('${_prefix}wifiOnly') ?? true,
      error: _preferences.getString('${_prefix}error'),
      lastUpdateCheck: _date('${_prefix}lastUpdateCheck'),
      runtimeReady: state == LocalAiModelState.ready,
      mockMode: manifest.developmentOnly,
      lastInferenceAt: _date('${_prefix}lastInferenceAt'),
      lastInferenceIntent: _preferences.getString(
        '${_prefix}lastInferenceIntent',
      ),
      lastInferenceError: _preferences.getString(
        '${_prefix}lastInferenceError',
      ),
    );
  }

  DateTime? _date(String key) {
    final value = _preferences.getString(key);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> setEnabled(bool value) =>
      _preferences.setBool('${_prefix}enabled', value);
  Future<void> setWifiOnly(bool value) =>
      _preferences.setBool('${_prefix}wifiOnly', value);

  @override
  Future<ModelCompatibilityResult> checkCompatibility() async {
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('checkCompatibility', {
            'minimumAndroidSdk': manifest.minimumAndroidSdk,
            'minimumIosVersion': manifest.minimumIosVersion,
            'minimumMemoryBytes': manifest.minimumMemoryBytes,
            'requiredStorageBytes': manifest.installedSizeBytes,
          });
      return ModelCompatibilityResult(
        compatible: result?['compatible'] == true,
        message:
            result?['message'] as String? ??
            'Runtime compatibility is unknown.',
      );
    } on MissingPluginException {
      return const ModelCompatibilityResult(
        compatible: false,
        message:
            'Native Local AI runtime is not installed. Basic Charon remains available.',
      );
    }
  }

  @override
  Future<void> downloadModel({
    required void Function(ModelDownloadProgress progress) onProgress,
  }) async {
    _onProgress = onProgress;
    if (!manifest.hasProductionArtifact) {
      await _fail(
        'Development manifest has no verified model artifact.',
        LocalAiModelState.failed,
      );
      throw StateError('No verified production model artifact is configured.');
    }
    final compatibility = await checkCompatibility();
    if (!compatibility.compatible) {
      await _fail(compatibility.message, LocalAiModelState.incompatible);
      throw StateError(compatibility.message);
    }
    final environment = await _channel.invokeMapMethod<String, dynamic>(
      'downloadEnvironment',
    );
    if ((_preferences.getBool('${_prefix}wifiOnly') ?? true) &&
        environment?['unmetered'] != true) {
      await _setState(LocalAiModelState.waitingForWifi);
      return;
    }
    final available = environment?['availableStorageBytes'] as int?;
    if (available != null &&
        available < manifest.installedSizeBytes + 64 * 1024 * 1024) {
      await _fail(
        'Not enough storage for Local AI.',
        LocalAiModelState.insufficientStorage,
      );
      return;
    }
    await _downloadAndInstall();
  }

  Future<void> _downloadAndInstall() async {
    _paused = false;
    _cancelled = false;
    final directory = await _modelDirectory();
    final partial = File(
      '${directory.path}/${manifest.modelId}-${manifest.modelVersion}.partial',
    );
    var offset = await partial.exists() ? await partial.length() : 0;
    await _persistDownload(offset);
    await _setState(LocalAiModelState.downloading);
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await _client!.getUrl(Uri.parse(manifest.downloadUrl));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'PrivateConcierge/1.0 model-data-client',
      );
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'Model server returned HTTP ${response.statusCode}.',
        );
      }
      if (offset > 0 && response.statusCode == HttpStatus.ok) {
        await partial.writeAsBytes(const [], flush: true);
        offset = 0;
      }
      final sink = partial.openWrite(mode: FileMode.append);
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 45),
        )) {
          if (_paused || _cancelled) break;
          sink.add(chunk);
          offset += chunk.length;
          await _persistDownload(offset);
          _onProgress?.call(
            ModelDownloadProgress(
              offset,
              manifest.downloadSizeBytes,
              LocalAiModelState.downloading,
            ),
          );
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (_cancelled) return;
      if (_paused) {
        await _setState(LocalAiModelState.paused);
        return;
      }
      if (offset != manifest.downloadSizeBytes) {
        throw const FileSystemException(
          'Downloaded model size does not match the manifest.',
        );
      }
      await _setState(LocalAiModelState.verifying);
      final actual = (await sha256.bind(partial.openRead()).first).toString();
      await _preferences.setString('${_prefix}actualSha256', actual);
      if (actual.toLowerCase() != manifest.sha256.toLowerCase()) {
        await partial.delete();
        await _fail(
          'Model checksum verification failed.',
          LocalAiModelState.corrupted,
        );
        return;
      }
      await _setState(LocalAiModelState.installing);
      final finalFile = File(
        '${directory.path}/${manifest.modelId}-${manifest.modelVersion}.${manifest.format}',
      );
      final staged = File('${finalFile.path}.new');
      if (await staged.exists()) await staged.delete();
      await partial.rename(staged.path);
      final smokePassed = await _smokeTest(staged.path);
      if (!smokePassed) {
        await staged.delete();
        await _fail(
          'The model failed its on-device inference test.',
          LocalAiModelState.failed,
        );
        return;
      }
      if (await finalFile.exists()) await finalFile.delete();
      await staged.rename(finalFile.path);
      await _preferences.setString('${_prefix}modelId', manifest.modelId);
      await _preferences.setString(
        '${_prefix}modelVersion',
        manifest.modelVersion,
      );
      await _preferences.setString('${_prefix}fileLocation', finalFile.path);
      await _preferences.setString('${_prefix}expectedSha256', manifest.sha256);
      await _preferences.setString(
        '${_prefix}lastVerified',
        DateTime.now().toIso8601String(),
      );
      await _preferences.setBool('${_prefix}enabled', true);
      await _preferences.remove('${_prefix}error');
      await _setState(LocalAiModelState.ready);
    } catch (error) {
      if (!_paused && !_cancelled) {
        await _fail('Download interrupted: $error', LocalAiModelState.failed);
        rethrow;
      }
    } finally {
      _client?.close(force: true);
      _client = null;
    }
  }

  Future<Directory> _modelDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/charon_local_ai');
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _persistDownload(int bytes) async {
    await _preferences.setInt('${_prefix}downloadedBytes', bytes);
    await _preferences.setInt(
      '${_prefix}totalBytes',
      manifest.downloadSizeBytes,
    );
  }

  Future<void> _setState(LocalAiModelState state) async {
    await _preferences.setString('${_prefix}state', state.name);
    _onProgress?.call(
      ModelDownloadProgress(
        _preferences.getInt('${_prefix}downloadedBytes') ?? 0,
        manifest.downloadSizeBytes,
        state,
      ),
    );
  }

  Future<void> _fail(String message, LocalAiModelState state) async {
    await _preferences.setString('${_prefix}error', message);
    await _setState(state);
  }

  @override
  Future<void> pauseDownload() async {
    _paused = true;
    _client?.close(force: true);
    await _setState(LocalAiModelState.paused);
  }

  @override
  Future<void> resumeDownload() async {
    final callback = _onProgress;
    if (callback == null) throw StateError('No paused download to resume.');
    await downloadModel(onProgress: callback);
  }

  @override
  Future<void> cancelDownload() async {
    _cancelled = true;
    _client?.close(force: true);
    final directory = await _modelDirectory();
    final partial = File(
      '${directory.path}/${manifest.modelId}-${manifest.modelVersion}.partial',
    );
    if (await partial.exists()) await partial.delete();
    await _preferences.setInt('${_prefix}downloadedBytes', 0);
    await _setState(LocalAiModelState.notInstalled);
  }

  @override
  Future<void> deleteModel() async {
    final location = _preferences.getString('${_prefix}fileLocation');
    if (location != null) {
      final file = File(location);
      if (await file.exists()) await file.delete();
    }
    for (final key
        in _preferences
            .getKeys()
            .where((k) => k.startsWith(_prefix) && !k.endsWith('wifiOnly'))
            .toList()) {
      await _preferences.remove(key);
    }
  }

  @override
  Future<LocalAiResult> processRequest(LocalAiRequest request) async {
    final status = await getStatus();
    final modelPath = status.fileLocation;
    if (!status.canProcess || modelPath == null) {
      throw StateError('Local AI is not ready.');
    }
    await _loadModel(modelPath);
    final raw = await _complete(
      '''Convert this request to exactly one JSON object. Do not add markdown or explanation.
Allowed intents: searchNearby, findClosest, filterCategory, filterOpen, businessDetails, openDestination, startNavigation, answerGeneral, clarify.
Schema: {"intent":"...","arguments":{},"confidence":0.0,"requiresConfirmation":false,"clarificationQuestion":null}
For answerGeneral put the concise answer in arguments.answer. Set requiresConfirmation=true for startNavigation. Use clarify if essential details are missing.
Request: ${request.normalizedText} /no_think''',
    );
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('Local model did not return JSON.');
    }
    final json = jsonDecode(raw.substring(start, end + 1));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Local model returned an invalid result.');
    }
    final result = LocalAiResult(
      requestId: request.requestId,
      intent: json['intent'] as String,
      arguments:
          (json['arguments'] as Map?)?.cast<String, dynamic>() ?? const {},
      confidence: (json['confidence'] as num).toDouble(),
      requiresConfirmation: json['requiresConfirmation'] as bool? ?? false,
      clarificationQuestion: json['clarificationQuestion'] as String?,
    );
    await _preferences.setString(
      '${_prefix}lastInferenceAt',
      DateTime.now().toIso8601String(),
    );
    await _preferences.setString(
      '${_prefix}lastInferenceIntent',
      result.intent,
    );
    await _preferences.remove('${_prefix}lastInferenceError');
    return result;
  }

  @override
  Future<String> answerGeneral(LocalAiRequest request) async {
    final status = await getStatus();
    final modelPath = status.fileLocation;
    if (!status.canProcess || modelPath == null) {
      throw StateError('Local AI is not ready.');
    }
    try {
      await _loadModel(modelPath);
      final result = await _chat!.chat.completions.create(
        model: manifest.modelId,
        messages: [
          const LlamaChatMessage(
            role: 'system',
            content:
                'You are a private on-device assistant. Give one direct answer in no more than three sentences. Never repeat the question, invent a dialogue, or write role labels such as User or Assistant. Your knowledge is not live; clearly say when a question requires current information.',
          ),
          LlamaChatMessage(
            role: 'user',
            content: '${request.normalizedText} /no_think',
            // lib_llama_cpp otherwise flattens text-only messages into raw
            // "system:/user:" lines instead of applying the GGUF chat template.
            name: 'charon_user',
          ),
        ],
        maxTokens: 96,
        temperature: 0.4,
        topP: 0.8,
        stop: const [
          '<|im_end|>',
          '<|endoftext|>',
          '\nUser:',
          '\nuser:',
          '\nAssistant:',
          '\nassistant:',
        ],
      );
      final answer = cleanLocalAiAnswer(
        result.choices.first.message.content.toString(),
      );
      if (answer.isEmpty) {
        throw const FormatException('Local model returned an empty answer.');
      }
      await _preferences.setString(
        '${_prefix}lastInferenceAt',
        DateTime.now().toIso8601String(),
      );
      await _preferences.setString(
        '${_prefix}lastInferenceIntent',
        'answerGeneral',
      );
      await _preferences.remove('${_prefix}lastInferenceError');
      return answer;
    } catch (error) {
      await _preferences.setString(
        '${_prefix}lastInferenceError',
        'Local inference failed: $error',
      );
      rethrow;
    }
  }

  Future<void> _loadModel(String path) async {
    if (_chat != null && _loadedModelPath == path) return;
    _chat = LlamaOpenAIClient(
      models: {
        manifest.modelId: LlamaModelConfig(
          modelPath: path,
          contextSize: 2048,
          gpuLayerCount: 0,
        ),
      },
    );
    _loadedModelPath = path;
  }

  Future<String> _complete(String prompt) async {
    final result = await _chat!.chat.completions.create(
      model: manifest.modelId,
      messages: [
        const LlamaChatMessage(
          role: 'system',
          content:
              'You are Charon Local AI. Return only the requested JSON function-routing object.',
        ),
        LlamaChatMessage(
          role: 'user',
          content: prompt,
          // Force message generation so Qwen's embedded chat template and
          // end-of-turn handling are used.
          name: 'charon_user',
        ),
      ],
      maxTokens: 256,
      temperature: 0.2,
      topP: 0.8,
    );
    return result.choices.first.message.content.toString();
  }

  Future<bool> _smokeTest(String path) async {
    try {
      await _loadModel(path);
      final response = await _complete(
        'Reply with exactly: READY /no_think',
      ).timeout(const Duration(seconds: 90));
      return response.toUpperCase().contains('READY');
    } catch (_) {
      _chat = null;
      _loadedModelPath = null;
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    _client?.close(force: true);
    _chat = null;
    _loadedModelPath = null;
  }
}
