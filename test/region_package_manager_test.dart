import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:private_concierge/services/downloads/region_package_manager.dart';
import 'package:private_concierge/services/geography/region_resolver.dart';
import 'nearby_service_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('installs a verified package and records its version', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = LocalRegionPackageManager(
      await SharedPreferences.getInstance(),
      MemoryPoiRepository(),
    );
    final updates = await manager.install(bundledRegions.first).toList();
    expect(updates.last.fraction, 1);
    expect(await manager.isCurrent(bundledRegions.first), isTrue);
    expect(
      (await manager.installedRegions()).single.id,
      bundledRegions.first.id,
    );
  });
}
