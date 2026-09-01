import 'dart:io';
import 'local_ai_models.dart';
import 'model_manifest.dart';

/// Delivers data assets only. Implementations must reject executable content.
abstract interface class ModelDeliveryService {
  Future<int> availableStorageBytes();
  Future<bool> isOnUnmeteredNetwork();
  Future<File> download(
    ModelManifest manifest, {
    required File partialFile,
    required int resumeFrom,
    required void Function(ModelDownloadProgress progress) onProgress,
  });
  Future<void> pause();
  Future<void> cancel();
}

abstract interface class ModelManifestVerifier {
  Future<bool> verifySignature(ModelManifest manifest);
  Future<String> sha256(File file);
}

abstract interface class LocalAiRuntime {
  Future<void> load(String modelPath);
  Future<LocalAiResult> infer(LocalAiRequest request);
  Future<bool> smokeTest();
  Future<void> cancel();
  Future<void> unload();
}
