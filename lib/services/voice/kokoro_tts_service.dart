import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

enum KokoroInstallState { notInstalled, downloading, installing, ready, failed }

class KokoroStatus {
  const KokoroStatus({
    required this.state,
    this.downloadedBytes = 0,
    this.totalBytes = KokoroTtsService.downloadBytes,
    this.error,
  });

  final KokoroInstallState state;
  final int downloadedBytes;
  final int totalBytes;
  final String? error;
  bool get installed => state == KokoroInstallState.ready;
}

class KokoroVoice {
  const KokoroVoice(this.id, this.name, this.sid);
  final String id;
  final String name;
  final int sid;
}

class KokoroTtsService {
  KokoroTtsService();

  static const modelVersion = 'kokoro-int8-multi-lang-v1_1';
  static const downloadBytes = 147031220;
  static const installedBytes = 215000000;
  static const downloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      '$modelVersion.tar.bz2';
  static const sha256Digest =
      'a1e94694776049035c4f2c6529f003aaece993c76aae9a78995831c3c4dcafc6';
  static const voices = [
    KokoroVoice('kokoro:af_maple', 'Kokoro Maple', 0),
    KokoroVoice('kokoro:af_sol', 'Kokoro Sol', 1),
    KokoroVoice('kokoro:bf_vale', 'Kokoro Vale', 2),
  ];

  final status = ValueNotifier<KokoroStatus>(
    const KokoroStatus(state: KokoroInstallState.notInstalled),
  );
  final AudioPlayer _player = AudioPlayer();
  Future<void> _queue = Future.value();
  HttpClient? _client;

  Future<void> initialize() async {
    status.value = KokoroStatus(
      state: await _hasRequiredFiles()
          ? KokoroInstallState.ready
          : KokoroInstallState.notInstalled,
    );
  }

  Future<Directory> _baseDirectory() async => Directory(
    path.join((await getApplicationSupportDirectory()).path, 'kokoro_tts'),
  );

  Future<Directory> _modelDirectory() async =>
      Directory(path.join((await _baseDirectory()).path, modelVersion));

  Future<bool> _hasRequiredFiles() async {
    final root = await _modelDirectory();
    return File(path.join(root.path, 'model.int8.onnx')).existsSync() &&
        File(path.join(root.path, 'voices.bin')).existsSync() &&
        File(path.join(root.path, 'tokens.txt')).existsSync() &&
        Directory(path.join(root.path, 'espeak-ng-data')).existsSync();
  }

  Future<void> download() async {
    if (status.value.state == KokoroInstallState.downloading ||
        status.value.state == KokoroInstallState.installing) {
      return;
    }
    final base = await _baseDirectory()
      ..createSync(recursive: true);
    final archiveFile = File(
      path.join(base.path, '$modelVersion.tar.bz2.part'),
    );
    final staging = Directory(
      path.join(base.path, '.installing-$modelVersion'),
    );
    try {
      status.value = const KokoroStatus(state: KokoroInstallState.downloading);
      _client = HttpClient();
      final request = await _client!.getUrl(Uri.parse(downloadUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Download failed with HTTP ${response.statusCode}.',
        );
      }
      final total = response.contentLength > 0
          ? response.contentLength
          : downloadBytes;
      final sink = archiveFile.openWrite();
      var received = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        status.value = KokoroStatus(
          state: KokoroInstallState.downloading,
          downloadedBytes: received,
          totalBytes: total,
        );
      }
      await sink.close();
      final actual = (await sha256.bind(archiveFile.openRead()).first)
          .toString();
      if (actual != sha256Digest) {
        throw const FormatException(
          'Downloaded Kokoro package checksum failed.',
        );
      }

      status.value = KokoroStatus(
        state: KokoroInstallState.installing,
        downloadedBytes: received,
        totalBytes: total,
      );
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      staging.createSync(recursive: true);
      await Isolate.run(
        () => extractFileToDisk(archiveFile.path, staging.path),
      );
      final extracted = Directory(path.join(staging.path, modelVersion));
      if (!extracted.existsSync()) {
        throw const FormatException('Kokoro package contents were incomplete.');
      }
      final destination = await _modelDirectory();
      if (destination.existsSync()) destination.deleteSync(recursive: true);
      extracted.renameSync(destination.path);
      staging.deleteSync(recursive: true);
      archiveFile.deleteSync();
      if (!await _hasRequiredFiles()) {
        throw const FormatException('Kokoro installation verification failed.');
      }
      status.value = const KokoroStatus(state: KokoroInstallState.ready);
    } catch (error) {
      status.value = KokoroStatus(
        state: KokoroInstallState.failed,
        error: _friendlyError(error),
      );
      rethrow;
    } finally {
      _client?.close(force: true);
      _client = null;
    }
  }

  Future<void> speak(String text, KokoroVoice voice, {bool wait = true}) {
    final completer = Completer<void>();
    _queue = _queue.then((_) async {
      try {
        if (!await _hasRequiredFiles()) {
          throw StateError('Download Kokoro before selecting this voice.');
        }
        final root = await _modelDirectory();
        final bytes = await Isolate.run(
          () => _synthesizeWav(root.path, text, voice.sid),
        );
        await _player.stop();
        final finished = _player.onPlayerComplete.first;
        await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
        if (wait) await finished;
        completer.complete();
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  static Uint8List _synthesizeWav(String root, String text, int sid) {
    sherpa.initBindings();
    final tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: path.join(root, 'model.int8.onnx'),
            voices: path.join(root, 'voices.bin'),
            tokens: path.join(root, 'tokens.txt'),
            dataDir: path.join(root, 'espeak-ng-data'),
            lexicon:
                '${path.join(root, 'lexicon-us-en.txt')},${path.join(root, 'lexicon-zh.txt')}',
            lang: 'en-us',
          ),
          numThreads: 2,
          debug: false,
        ),
        ruleFsts:
            '${path.join(root, 'phone-zh.fst')},${path.join(root, 'date-zh.fst')},${path.join(root, 'number-zh.fst')}',
      ),
    );
    try {
      final audio = tts.generate(text: text, sid: sid, speed: 1.0);
      if (audio.samples.isEmpty || audio.sampleRate <= 0) {
        throw StateError('Kokoro did not generate audio.');
      }
      return _wav(audio.samples, audio.sampleRate);
    } finally {
      tts.free();
    }
  }

  static Uint8List _wav(Float32List samples, int sampleRate) {
    final dataLength = samples.length * 2;
    final bytes = ByteData(44 + dataLength);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataLength, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i].clamp(-1.0, 1.0);
      bytes.setInt16(44 + i * 2, (sample * 32767).round(), Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  String _friendlyError(Object error) {
    if (error is SocketException) return 'Could not connect to the model host.';
    if (error is HttpException || error is FormatException) return '$error';
    return 'Kokoro installation failed. Please try again.';
  }

  Future<void> dispose() async {
    _client?.close(force: true);
    await _player.dispose();
    status.dispose();
  }
}
