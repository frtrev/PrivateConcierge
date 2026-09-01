enum LocalAiModelState {
  notInstalled,
  checkingCompatibility,
  incompatible,
  waitingForWifi,
  downloading,
  paused,
  verifying,
  installing,
  ready,
  updateAvailable,
  corrupted,
  insufficientStorage,
  failed,
}

class ModelDownloadProgress {
  const ModelDownloadProgress(
    this.downloadedBytes,
    this.totalBytes,
    this.state,
  );
  final int downloadedBytes;
  final int totalBytes;
  final LocalAiModelState state;
  double get fraction => totalBytes <= 0 ? 0 : downloadedBytes / totalBytes;
}

class LocalAiStatus {
  const LocalAiStatus({
    required this.state,
    required this.enabled,
    this.modelId,
    this.modelVersion,
    this.fileLocation,
    this.expectedSha256,
    this.actualSha256,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.lastVerified,
    this.wifiOnly = true,
    this.error,
    this.lastUpdateCheck,
    this.runtimeReady = false,
    this.mockMode = true,
    this.lastInferenceAt,
    this.lastInferenceIntent,
    this.lastInferenceError,
  });
  final LocalAiModelState state;
  final bool enabled;
  final String? modelId;
  final String? modelVersion;
  final String? fileLocation;
  final String? expectedSha256;
  final String? actualSha256;
  final int downloadedBytes;
  final int totalBytes;
  final DateTime? lastVerified;
  final bool wifiOnly;
  final String? error;
  final DateTime? lastUpdateCheck;
  final bool runtimeReady;
  final bool mockMode;
  final DateTime? lastInferenceAt;
  final String? lastInferenceIntent;
  final String? lastInferenceError;

  bool get canProcess =>
      state == LocalAiModelState.ready && enabled && runtimeReady;
}

class ModelCompatibilityResult {
  const ModelCompatibilityResult({
    required this.compatible,
    required this.message,
  });
  final bool compatible;
  final String message;
}

class LocalAiRequest {
  const LocalAiRequest({required this.requestId, required this.normalizedText});
  final String requestId;
  final String normalizedText;
}

class LocalAiResult {
  const LocalAiResult({
    required this.requestId,
    required this.intent,
    required this.arguments,
    required this.confidence,
    required this.requiresConfirmation,
    this.clarificationQuestion,
  });
  final String requestId;
  final String intent;
  final Map<String, dynamic> arguments;
  final double confidence;
  final bool requiresConfirmation;
  final String? clarificationQuestion;
}

abstract interface class LocalAiService {
  Future<LocalAiStatus> getStatus();
  Future<void> downloadModel({
    required void Function(ModelDownloadProgress progress) onProgress,
  });
  Future<void> pauseDownload();
  Future<void> resumeDownload();
  Future<void> cancelDownload();
  Future<void> deleteModel();
  Future<ModelCompatibilityResult> checkCompatibility();
  Future<LocalAiResult> processRequest(LocalAiRequest request);
  Future<String> answerGeneral(LocalAiRequest request);
  Future<void> dispose();
}
