import 'dart:async';
import 'package:flutter/foundation.dart';
import 'local_ai_models.dart';
import 'local_ai_validator.dart';

class LocalAiCoordinator {
  LocalAiCoordinator(
    this.service, {
    this.validator = const LocalAiResultValidator(),
  });
  final LocalAiService service;
  final LocalAiResultValidator validator;
  Future<void> _queue = Future.value();
  int _request = 0;
  String? lastFallbackReason;
  Duration? lastInferenceDuration;

  Future<LocalAiResult?> interpret(String normalizedText) {
    final completer = Completer<LocalAiResult?>();
    _queue = _queue.then((_) async {
      final watch = Stopwatch()..start();
      try {
        final status = await service.getStatus();
        if (!status.canProcess) {
          lastFallbackReason = 'not_ready_or_disabled';
          completer.complete(null);
          return;
        }
        final result = validator.validate(
          await service
              .processRequest(
                LocalAiRequest(
                  requestId: 'local-${++_request}',
                  normalizedText: normalizedText,
                ),
              )
              .timeout(const Duration(seconds: 45)),
        );
        if (result.confidence < .45) {
          lastFallbackReason = 'low_confidence';
          completer.complete(null);
        } else {
          completer.complete(result);
        }
      } catch (error) {
        lastFallbackReason = error is TimeoutException
            ? 'timeout'
            : 'inference_or_validation_failure';
        debugPrint('local_ai fallback=$lastFallbackReason');
        completer.complete(null);
      } finally {
        watch.stop();
        lastInferenceDuration = watch.elapsed;
      }
    });
    return completer.future;
  }

  Future<String?> answerGeneral(String normalizedText) async {
    final watch = Stopwatch()..start();
    try {
      final status = await service.getStatus();
      if (!status.canProcess) {
        lastFallbackReason = 'not_ready_or_disabled';
        return null;
      }
      final answer = await service
          .answerGeneral(
            LocalAiRequest(
              requestId: 'local-${++_request}',
              normalizedText: normalizedText,
            ),
          )
          .timeout(const Duration(seconds: 45));
      lastFallbackReason = null;
      return answer;
    } catch (error) {
      lastFallbackReason = error is TimeoutException
          ? 'timeout'
          : 'inference_failure';
      debugPrint('local_ai general fallback=$lastFallbackReason');
      return null;
    } finally {
      watch.stop();
      lastInferenceDuration = watch.elapsed;
    }
  }
}
