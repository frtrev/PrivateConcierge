import 'package:flutter_test/flutter_test.dart';
import 'package:private_concierge/services/local_ai/model_manifest.dart';

void main() {
  Map<String, dynamic> manifest() => {
    'schemaVersion': 1,
    'modelId': 'charon-functiongemma-270m',
    'modelVersion': '1.0.0',
    'displayName': 'Charon Local AI',
    'format': 'litertlm',
    'quantization': 'int8',
    'downloadUrl': 'https://models.example/model.litertlm',
    'downloadSizeBytes': 10,
    'installedSizeBytes': 10,
    'minimumMemoryBytes': 100,
    'minimumAndroidSdk': 26,
    'minimumIosVersion': '17.0',
    'sha256': 'a' * 64,
    'signature': 'signed-value',
    'licenseUrl': 'https://example/license',
    'privacyPolicyUrl': 'https://example/privacy',
    'developmentOnly': false,
  };

  test('enables downloads only for complete production artifacts', () {
    expect(ModelManifest.fromJson(manifest()).hasProductionArtifact, isTrue);
    expect(
      ModelManifest.fromJson({
        ...manifest(),
        'developmentOnly': true,
      }).hasProductionArtifact,
      isFalse,
    );
    expect(
      ModelManifest.fromJson({
        ...manifest(),
        'sha256': '',
      }).hasProductionArtifact,
      isFalse,
    );
    expect(
      ModelManifest.fromJson({
        ...manifest(),
        'downloadUrl': 'http://unsafe',
      }).hasProductionArtifact,
      isFalse,
    );
  });

  test('accepts a checksum-pinned bundled GGUF manifest', () {
    expect(
      ModelManifest.fromJson({
        ...manifest(),
        'format': 'gguf',
        'signature': '',
      }).hasProductionArtifact,
      isTrue,
    );
  });
}
