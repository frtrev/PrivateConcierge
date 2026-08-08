import 'dart:async';
import 'package:http/http.dart' as http;

class PublicDownloadRequest {
  const PublicDownloadRequest({required this.uri, required this.formFields});
  final Uri uri;
  final Map<String, String> formFields;
}

class DownloadChunk {
  const DownloadChunk({
    required this.bytes,
    required this.receivedBytes,
    this.totalBytes,
  });
  final List<int> bytes;
  final int receivedBytes;
  final int? totalBytes;
}

abstract interface class DownloadClient {
  /// Downloads only allow-listed, public, non-user-specific geographic data.
  Stream<DownloadChunk> downloadPublicResource(PublicDownloadRequest request);
}

class HttpPublicDownloadClient implements DownloadClient {
  HttpPublicDownloadClient({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;

  static const allowedHosts = {'overpass-api.de', 'overpass.kumi.systems'};

  @override
  Stream<DownloadChunk> downloadPublicResource(
    PublicDownloadRequest request,
  ) async* {
    if (request.uri.scheme != 'https' ||
        !allowedHosts.contains(request.uri.host)) {
      throw ArgumentError(
        'Public download host is not allow-listed: ${request.uri.host}',
      );
    }
    final httpRequest = http.Request('POST', request.uri)
      ..headers['User-Agent'] =
          'PrivateConcierge/1.0 (public OSM region downloader)'
      ..headers['Accept'] = 'application/json'
      ..headers['Content-Type'] =
          'application/x-www-form-urlencoded; charset=utf-8'
      ..bodyFields = request.formFields;
    late http.StreamedResponse response;
    try {
      response = await _client
          .send(httpRequest)
          .timeout(const Duration(seconds: 75));
    } on TimeoutException {
      throw const PublicDownloadException(
        kind: PublicDownloadFailure.timeout,
        retryable: true,
      );
    } on http.ClientException {
      throw const PublicDownloadException(
        kind: PublicDownloadFailure.connection,
        retryable: true,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Drain the response, but never expose a server's HTML error body to UI.
      await response.stream.drain<void>();
      throw PublicDownloadException(
        kind: PublicDownloadFailure.server,
        retryable:
            response.statusCode == 429 ||
            (response.statusCode >= 502 && response.statusCode <= 504),
        statusCode: response.statusCode,
      );
    }
    var received = 0;
    try {
      await for (final bytes in response.stream.timeout(
        const Duration(seconds: 75),
      )) {
        received += bytes.length;
        yield DownloadChunk(
          bytes: bytes,
          receivedBytes: received,
          totalBytes: response.contentLength,
        );
      }
    } on TimeoutException {
      throw const PublicDownloadException(
        kind: PublicDownloadFailure.timeout,
        retryable: true,
      );
    } on http.ClientException {
      throw const PublicDownloadException(
        kind: PublicDownloadFailure.connection,
        retryable: true,
      );
    }
  }
}

enum PublicDownloadFailure { timeout, connection, server }

class PublicDownloadException implements Exception {
  const PublicDownloadException({
    required this.kind,
    required this.retryable,
    this.statusCode,
  });
  final PublicDownloadFailure kind;
  final bool retryable;
  final int? statusCode;
}
