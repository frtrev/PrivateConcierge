import 'dart:async';
import 'dart:convert';
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
  const KokoroVoice(this.id, this.name, this.sid, this.locale, this.language);
  final String id;
  final String name;
  final int sid;
  final String locale;
  final String language;
}

class KokoroTtsService {
  KokoroTtsService();

  static const modelVersion = 'kokoro-multi-lang-v1_0';
  static const downloadBytes = 349418188;
  static const installedBytes = 736000000;
  static const downloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      '$modelVersion.tar.bz2';
  static const sha256Digest =
      'c133d26353d776da730870dac7da07dbfc9a5e3bc80cc5e8e83ab6e823be7046';
  static const voices = [
    KokoroVoice('kokoro:v1_0:af_alloy', 'Alloy', 0, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:af_aoede', 'Aoede', 1, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:af_bella', 'Bella', 2, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:af_heart', 'Heart', 3, 'English (US)', 'en-us'),
    KokoroVoice(
      'kokoro:v1_0:af_jessica',
      'Jessica',
      4,
      'English (US)',
      'en-us',
    ),
    KokoroVoice('kokoro:v1_0:af_kore', 'Kore', 5, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:af_nicole', 'Nicole', 6, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:af_nova', 'Nova', 7, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:af_river', 'River', 8, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:af_sarah', 'Sarah', 9, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:af_sky', 'Sky', 10, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:am_adam', 'Adam', 11, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:am_echo', 'Echo', 12, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:am_eric', 'Eric', 13, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:am_fenrir', 'Fenrir', 14, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:am_liam', 'Liam', 15, 'English (US)', 'en-us'),
    KokoroVoice(
      'kokoro:v1_0:am_michael',
      'Michael',
      16,
      'English (US)',
      'en-us',
    ),
    KokoroVoice('kokoro:v1_0:am_onyx', 'Onyx', 17, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:am_puck', 'Puck', 18, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:am_santa', 'Santa', 19, 'English (US)', 'en-us'),
    KokoroVoice('kokoro:v1_0:bf_alice', 'Alice', 20, 'English (UK)', 'en-gb'),
    KokoroVoice('kokoro:v1_0:bf_emma', 'Emma', 21, 'English (UK)', 'en-gb'),
    KokoroVoice(
      'kokoro:v1_0:bf_isabella',
      'Isabella',
      22,
      'English (UK)',
      'en-gb',
    ),
    KokoroVoice('kokoro:v1_0:bf_lily', 'Lily', 23, 'English (UK)', 'en-gb'),
    KokoroVoice('kokoro:v1_0:bm_daniel', 'Daniel', 24, 'English (UK)', 'en-gb'),
    KokoroVoice('kokoro:v1_0:bm_fable', 'Fable', 25, 'English (UK)', 'en-gb'),
    KokoroVoice('kokoro:v1_0:bm_george', 'George', 26, 'English (UK)', 'en-gb'),
    KokoroVoice('kokoro:v1_0:bm_lewis', 'Lewis', 27, 'English (UK)', 'en-gb'),
    KokoroVoice('kokoro:v1_0:ef_dora', 'Dora', 28, 'Spanish', 'es'),
    KokoroVoice('kokoro:v1_0:em_alex', 'Alex', 29, 'Spanish', 'es'),
  ];

  final status = ValueNotifier<KokoroStatus>(
    const KokoroStatus(state: KokoroInstallState.notInstalled),
  );
  final AudioPlayer _player = AudioPlayer();
  Future<void> _queue = Future.value();
  Completer<void>? _activePlaybackStopped;
  int _stopGeneration = 0;
  HttpClient? _client;

  Future<void> initialize() async {
    final installed = await _hasRequiredFiles();
    if (installed) await _removeLegacyModel();
    status.value = KokoroStatus(
      state: installed
          ? KokoroInstallState.ready
          : KokoroInstallState.notInstalled,
    );
  }

  Future<Directory> _baseDirectory() async => Directory(
    path.join((await getApplicationSupportDirectory()).path, 'kokoro_tts'),
  );

  Future<Directory> _modelDirectory() async =>
      Directory(path.join((await _baseDirectory()).path, modelVersion));

  Future<Directory> _prayerAudioDirectory() async =>
      Directory(path.join((await _baseDirectory()).path, 'prayer_audio'));

  Future<void> _removeLegacyModel() async {
    final legacy = Directory(
      path.join((await _baseDirectory()).path, 'kokoro-int8-multi-lang-v1_1'),
    );
    if (legacy.existsSync()) legacy.deleteSync(recursive: true);
  }

  Future<bool> _hasRequiredFiles() async {
    final root = await _modelDirectory();
    return File(path.join(root.path, 'model.onnx')).existsSync() &&
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
    final partialFile = File(
      path.join(base.path, '$modelVersion.tar.bz2.part'),
    );
    final archiveFile = File(path.join(base.path, '$modelVersion.tar.bz2'));
    final staging = Directory(
      path.join(base.path, '.installing-$modelVersion'),
    );
    var phase = 'download';
    try {
      status.value = const KokoroStatus(state: KokoroInstallState.downloading);
      var downloadFile = archiveFile.existsSync() ? archiveFile : partialFile;
      var received = downloadFile.existsSync() ? downloadFile.lengthSync() : 0;
      var total = downloadBytes;
      var actual = received == downloadBytes
          ? (await sha256.bind(downloadFile.openRead()).first).toString()
          : '';
      if (actual != sha256Digest) {
        downloadFile = partialFile;
        _client = HttpClient();
        final request = await _client!.getUrl(Uri.parse(downloadUrl));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'Download failed with HTTP ${response.statusCode}.',
          );
        }
        total = response.contentLength > 0
            ? response.contentLength
            : downloadBytes;
        final sink = partialFile.openWrite();
        received = 0;
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
        actual = (await sha256.bind(partialFile.openRead()).first).toString();
      }
      if (actual != sha256Digest) {
        throw const FormatException(
          'Downloaded Kokoro package checksum failed.',
        );
      }

      // archive selects the decoder from the filename. Keep `.part` only while
      // downloading, then expose the verified package with its real extension.
      if (downloadFile.path != archiveFile.path) {
        if (archiveFile.existsSync()) archiveFile.deleteSync();
        partialFile.renameSync(archiveFile.path);
      }

      status.value = KokoroStatus(
        state: KokoroInstallState.installing,
        downloadedBytes: received,
        totalBytes: total,
      );
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      staging.createSync(recursive: true);
      phase = 'extraction';
      final archivePath = archiveFile.path;
      final stagingPath = staging.path;
      await Isolate.run(() async {
        await extractFileToDisk(archivePath, stagingPath);
      });
      phase = 'verification';
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
      await _removeLegacyModel();
      status.value = const KokoroStatus(state: KokoroInstallState.ready);
    } catch (error, stack) {
      debugPrint('Kokoro $phase failed: $error\n$stack');
      status.value = KokoroStatus(
        state: KokoroInstallState.failed,
        error: _friendlyError(error, phase),
      );
      rethrow;
    } finally {
      _client?.close(force: true);
      _client = null;
    }
  }

  Future<void> speak(
    String text,
    KokoroVoice voice, {
    double speed = 1.0,
    bool wait = true,
  }) => _enqueueSpeech(text, voice, speed: speed, wait: wait);

  Future<void> speakCachedPrayer(
    String text,
    KokoroVoice voice, {
    required int prayerId,
    required DateTime updatedAt,
    double speed = 1.0,
  }) async {
    final file = await _prayerAudioFile(
      text,
      voice,
      prayerId: prayerId,
      updatedAt: updatedAt,
      speed: speed,
    );
    await _enqueueSpeech(text, voice, speed: speed, persistentFile: file);
  }

  Future<void> cachePrayer(
    String text,
    KokoroVoice voice, {
    required int prayerId,
    required DateTime updatedAt,
    double speed = 1.0,
  }) async {
    final file = await _prayerAudioFile(
      text,
      voice,
      prayerId: prayerId,
      updatedAt: updatedAt,
      speed: speed,
    );
    await _enqueueSpeech(
      text,
      voice,
      speed: speed,
      persistentFile: file,
      play: false,
    );
  }

  Future<void> clearPrayerAudioCache() async {
    final directory = await _prayerAudioDirectory();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  Future<File> _prayerAudioFile(
    String text,
    KokoroVoice voice, {
    required int prayerId,
    required DateTime updatedAt,
    required double speed,
  }) async {
    final directory = await _prayerAudioDirectory()
      ..createSync(recursive: true);
    final signature = sha256
        .convert(
          utf8.encode(
            '$prayerId|${updatedAt.microsecondsSinceEpoch}|${voice.id}|'
            '${speed.toStringAsFixed(3)}|$text',
          ),
        )
        .toString();
    return File(path.join(directory.path, 'prayer-$prayerId-$signature.wav'));
  }

  Future<void> _enqueueSpeech(
    String text,
    KokoroVoice voice, {
    required double speed,
    bool wait = true,
    File? persistentFile,
    bool play = true,
  }) {
    final completer = Completer<void>();
    final generation = _stopGeneration;
    _queue = _queue.catchError((Object _) {}).then((_) async {
      File? wavFile;
      final shouldDelete = persistentFile == null;
      try {
        if (!await _hasRequiredFiles()) {
          throw StateError('Download Kokoro before selecting this voice.');
        }
        wavFile = persistentFile;
        if (wavFile == null || !wavFile.existsSync()) {
          final root = await _modelDirectory();
          final bytes = await _synthesizeInBackground(
            root.path,
            text,
            voice.sid,
            voice.language,
            speed,
          );
          if (wavFile == null) {
            final temporary = await getTemporaryDirectory();
            wavFile = File(
              path.join(
                temporary.path,
                'kokoro-${DateTime.now().microsecondsSinceEpoch}.wav',
              ),
            );
          } else {
            wavFile.parent.createSync(recursive: true);
          }
          await wavFile.writeAsBytes(bytes, flush: true);
        }
        if (generation != _stopGeneration) {
          if (shouldDelete && wavFile.existsSync()) wavFile.deleteSync();
          completer.complete();
          return;
        }
        if (!play) {
          completer.complete();
          return;
        }
        await _player.stop();
        await _player.setAudioContext(
          AudioContextConfig(
            route: AudioContextConfigRoute.speaker,
            focus: AudioContextConfigFocus.gain,
          ).build(),
        );
        final finished = _player.onPlayerComplete.first;
        final stopped = Completer<void>();
        _activePlaybackStopped = stopped;
        await _player.play(DeviceFileSource(wavFile.path));
        final playbackEnded = Future.any<void>([finished, stopped.future]);
        if (wait) {
          await playbackEnded;
          if (shouldDelete && wavFile.existsSync()) wavFile.deleteSync();
        } else {
          unawaited(
            playbackEnded.whenComplete(() {
              if (shouldDelete && (wavFile?.existsSync() ?? false)) {
                wavFile!.deleteSync();
              }
            }),
          );
        }
        if (identical(_activePlaybackStopped, stopped)) {
          _activePlaybackStopped = null;
        }
        completer.complete();
      } catch (error, stack) {
        debugPrint('Kokoro speech failed: $error\n$stack');
        if (shouldDelete && (wavFile?.existsSync() ?? false)) {
          wavFile!.deleteSync();
        }
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> pause() => _player.pause();

  Future<void> resume() => _player.resume();

  Future<void> stop() async {
    _stopGeneration++;
    final stopped = _activePlaybackStopped;
    if (stopped != null && !stopped.isCompleted) stopped.complete();
    await _player.stop();
  }

  static Future<Uint8List> _synthesizeInBackground(
    String root,
    String text,
    int sid,
    String language,
    double speed,
  ) => Isolate.run(() => _synthesizeWav(root, text, sid, language, speed));

  static Uint8List _synthesizeWav(
    String root,
    String text,
    int sid,
    String language,
    double speed,
  ) {
    sherpa.initBindings();
    final tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: path.join(root, 'model.onnx'),
            voices: path.join(root, 'voices.bin'),
            tokens: path.join(root, 'tokens.txt'),
            dataDir: path.join(root, 'espeak-ng-data'),
            lexicon:
                '${path.join(root, 'lexicon-us-en.txt')},${path.join(root, 'lexicon-zh.txt')}',
            lang: language,
          ),
          numThreads: 2,
          debug: false,
        ),
        ruleFsts:
            '${path.join(root, 'phone-zh.fst')},${path.join(root, 'date-zh.fst')},${path.join(root, 'number-zh.fst')}',
      ),
    );
    try {
      final audio = tts.generate(text: text, sid: sid, speed: speed);
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

  String _friendlyError(Object error, String phase) {
    if (error is SocketException) return 'Could not connect to the model host.';
    if (error is HttpException || error is FormatException) return '$error';
    return 'Kokoro $phase failed: $error';
  }

  Future<void> dispose() async {
    _client?.close(force: true);
    await stop();
    await _player.dispose();
    status.dispose();
  }
}
