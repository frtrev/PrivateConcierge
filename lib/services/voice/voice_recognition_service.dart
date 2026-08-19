import 'package:flutter/services.dart';

enum VoiceRecognitionState {
  idle,
  listening,
  processing,
  completed,
  error,
  unsupported,
}

class VoiceRecognitionResult {
  const VoiceRecognitionResult(this.state, {this.text, this.message});
  final VoiceRecognitionState state;
  final String? text;
  final String? message;
}

abstract interface class VoiceRecognitionService {
  Future<bool> isOnDeviceAvailable();
  Stream<VoiceRecognitionResult> listenOnce({bool punctuatePauses = false});
}

class AndroidOnDeviceVoiceRecognitionService
    implements VoiceRecognitionService {
  static const _channel = MethodChannel('private_concierge/on_device_speech');
  @override
  Future<bool> isOnDeviceAvailable() async =>
      await _channel.invokeMethod<bool>('isAvailable') ?? false;
  @override
  Stream<VoiceRecognitionResult> listenOnce({
    bool punctuatePauses = false,
  }) async* {
    if (!await isOnDeviceAvailable()) {
      yield const VoiceRecognitionResult(
        VoiceRecognitionState.unsupported,
        message: 'On-device voice recognition is unavailable on this device.',
      );
      return;
    }
    yield const VoiceRecognitionResult(
      VoiceRecognitionState.listening,
      message: 'Listening…',
    );
    try {
      final text = await _channel.invokeMethod<String>('listenOnce', {
        'punctuatePauses': punctuatePauses,
      });
      if (text == null || text.trim().isEmpty) {
        yield const VoiceRecognitionResult(
          VoiceRecognitionState.error,
          message: 'No speech was recognized.',
        );
      } else {
        yield VoiceRecognitionResult(
          VoiceRecognitionState.completed,
          text: text,
        );
      }
    } on PlatformException catch (error) {
      yield VoiceRecognitionResult(
        VoiceRecognitionState.error,
        message: error.message ?? 'Voice recognition failed.',
      );
    }
  }
}
