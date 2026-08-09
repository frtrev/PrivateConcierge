import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_concierge/services/downloads/overture_package_source.dart';
import 'package:private_concierge/services/downloads/region_package_manager.dart';
import 'package:private_concierge/services/geography/region_resolver.dart';
import 'package:private_concierge/services/network/download_client.dart';
import 'nearby_service_test.dart';

class MemoryDownloadClient implements DownloadClient {
  const MemoryDownloadClient(this.bytes);
  final List<int> bytes;

  @override
  Stream<DownloadChunk> downloadPublicResource(Uri uri) async* {
    yield DownloadChunk(bytes, bytes.length, bytes.length);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('installs a verified package and records its version', () async {
    SharedPreferences.setMockInitialValues({});
    final data = await rootBundle.load(
      'assets/overture/us-tn-memphis-50mi.jsonl.gz',
    );
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final repository = MemoryPoiRepository();
    final manager = OvertureRegionPackageManager(
      await SharedPreferences.getInstance(),
      repository,
      OverturePackageSource(MemoryDownloadClient(bytes)),
    );
    final updates = await manager.install(bundledRegions.first).toList();
    expect(updates.last.fraction, 1);
    expect(await manager.isCurrent(bundledRegions.first), isTrue);
    expect(repository.points.length, 12448);
    expect(
      (await manager.installedRegions()).single.id,
      bundledRegions.first.id,
    );
  });
}
