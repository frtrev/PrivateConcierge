abstract interface class DownloadClient {
  /// This client is intentionally restricted to public, static region resources.
  Stream<List<int>> downloadPublicResource(Uri uri);
}

class DisabledDownloadClient implements DownloadClient {
  @override
  Stream<List<int>> downloadPublicResource(Uri uri) => Stream.error(
    UnsupportedError(
      'Remote downloads are not configured. Use the bundled development package.',
    ),
  );
}
