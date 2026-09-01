import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/services/local_ai/local_ai_coordinator.dart';
import 'package:private_concierge/services/local_ai/local_ai_models.dart';

class FakeLocalAi implements LocalAiService {
  FakeLocalAi({this.ready = false, this.fail = false});
  bool ready, fail;
  int calls = 0;
  @override
  Future<LocalAiStatus> getStatus() async => LocalAiStatus(
    state: ready ? LocalAiModelState.ready : LocalAiModelState.notInstalled,
    enabled: ready,
    runtimeReady: ready,
  );
  @override
  Future<LocalAiResult> processRequest(LocalAiRequest request) async {
    calls++;
    if (fail) throw StateError('failed');
    return LocalAiResult(
      requestId: request.requestId,
      intent: 'searchNearby',
      arguments: const {'category': 'restaurant'},
      confidence: .9,
      requiresConfirmation: false,
    );
  }

  @override
  Future<String> answerGeneral(LocalAiRequest request) async {
    calls++;
    if (fail) throw StateError('failed');
    return '4';
  }

  @override
  Future<ModelCompatibilityResult> checkCompatibility() async =>
      const ModelCompatibilityResult(compatible: true, message: 'ok');
  @override
  Future<void> cancelDownload() async {}
  @override
  Future<void> deleteModel() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> downloadModel({
    required void Function(ModelDownloadProgress progress) onProgress,
  }) async {}
  @override
  Future<void> pauseDownload() async {}
  @override
  Future<void> resumeDownload() async {}
}

void main() {
  test('never-installed model falls back without inference', () async {
    final fake = FakeLocalAi();
    expect(await LocalAiCoordinator(fake).interpret('find food'), isNull);
    expect(fake.calls, 0);
  });
  test('inference failure falls back', () async {
    final fake = FakeLocalAi(ready: true, fail: true);
    expect(await LocalAiCoordinator(fake).interpret('find food'), isNull);
  });
  test('ready model returns validated result', () async {
    final fake = FakeLocalAi(ready: true);
    expect(
      (await LocalAiCoordinator(fake).interpret('find food'))?.intent,
      'searchNearby',
    );
  });
  test('ready model can answer a general question', () async {
    final fake = FakeLocalAi(ready: true);
    expect(await LocalAiCoordinator(fake).answerGeneral('2 times 2'), '4');
  });
}
