import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

class DownloadChunk {
  const DownloadChunk(this.bytes, this.receivedBytes, this.totalBytes);
  final List<int> bytes;
  final int receivedBytes;
  final int? totalBytes;
}

abstract interface class DownloadClient {
  Stream<DownloadChunk> downloadPublicResource(Uri uri);
}

class StaticPackageDownloadClient implements DownloadClient {
  StaticPackageDownloadClient({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  static const allowedHosts = {'raw.githubusercontent.com'};

  @override
  Stream<DownloadChunk> downloadPublicResource(Uri uri) async* {
    if (uri.scheme != 'https' || !allowedHosts.contains(uri.host)) {
      throw ArgumentError('Static package host is not allowed.');
    }
    final request = http.Request('GET', uri)
      ..headers['User-Agent'] = 'PrivateConcierge/1.0 Overture package client';
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw const PackageNetworkException();
    }
    var received = 0;
    await for (final bytes in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      received += bytes.length;
      yield DownloadChunk(bytes, received, response.contentLength);
    }
  }
}

class PackageNetworkException implements Exception {
  const PackageNetworkException();
  @override
  String toString() => 'The geographic data package could not be downloaded.';
}

class BundledFallbackDownloadClient implements DownloadClient {
  const BundledFallbackDownloadClient(this._primary);
  final DownloadClient _primary;
  @override
  Stream<DownloadChunk> downloadPublicResource(Uri uri) async* {
    try {
      await for (final chunk in _primary.downloadPublicResource(uri)) {
        yield chunk;
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Remote Overture package unavailable; using asset: $error');
      }
      try {
        final data = await rootBundle.load(
          'assets/overture/${uri.pathSegments.last}',
        );
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        yield DownloadChunk(bytes, bytes.length, bytes.length);
      } catch (assetError, stackTrace) {
        if (kDebugMode) {
          debugPrint('Bundled Overture package failed: $assetError');
          debugPrintStack(stackTrace: stackTrace);
        }
        rethrow;
      }
    }
  }
}
