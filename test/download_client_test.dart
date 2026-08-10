import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/services/network/download_client.dart';

class FailingDownloadClient implements DownloadClient {
  @override
  Stream<DownloadChunk> downloadPublicResource(Uri uri) async* {
    throw const PackageNetworkException();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the bundled package when the remote stream fails', () async {
    final client = BundledFallbackDownloadClient(FailingDownloadClient());
    final chunks = await client
        .downloadPublicResource(
          Uri.parse(
            'https://raw.githubusercontent.com/frtrev/PrivateConcierge/main/assets/overture/us-tn-memphis-50mi.jsonl.gz',
          ),
        )
        .toList();

    expect(chunks, hasLength(1));
    expect(chunks.single.bytes, hasLength(3420539));
    expect(chunks.single.receivedBytes, 3420539);
    expect(chunks.single.totalBytes, 3420539);
  });
}
