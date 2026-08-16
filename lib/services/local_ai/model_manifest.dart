import 'dart:convert';

class ModelManifest {
  const ModelManifest({
    required this.schemaVersion,
    required this.modelId,
    required this.modelVersion,
    required this.displayName,
    required this.format,
    required this.quantization,
    required this.downloadUrl,
    required this.downloadSizeBytes,
    required this.installedSizeBytes,
    required this.minimumMemoryBytes,
    required this.minimumAndroidSdk,
    required this.minimumIosVersion,
    required this.sha256,
    required this.signature,
    required this.licenseUrl,
    required this.privacyPolicyUrl,
    required this.developmentOnly,
  });
  final int schemaVersion;
  final String modelId, modelVersion, displayName, format, quantization;
  final String downloadUrl, minimumIosVersion, sha256, signature;
  final String licenseUrl, privacyPolicyUrl;
  final int downloadSizeBytes,
      installedSizeBytes,
      minimumMemoryBytes,
      minimumAndroidSdk;
  final bool developmentOnly;

  factory ModelManifest.fromJson(Map<String, dynamic> json) => ModelManifest(
    schemaVersion: json['schemaVersion'] as int,
    modelId: json['modelId'] as String,
    modelVersion: json['modelVersion'] as String,
    displayName: json['displayName'] as String,
    format: json['format'] as String,
    quantization: json['quantization'] as String,
    downloadUrl: json['downloadUrl'] as String,
    downloadSizeBytes: json['downloadSizeBytes'] as int,
    installedSizeBytes: json['installedSizeBytes'] as int,
    minimumMemoryBytes: json['minimumMemoryBytes'] as int,
    minimumAndroidSdk: json['minimumAndroidSdk'] as int,
    minimumIosVersion: json['minimumIosVersion'] as String,
    sha256: json['sha256'] as String,
    signature: json['signature'] as String,
    licenseUrl: json['licenseUrl'] as String,
    privacyPolicyUrl: json['privacyPolicyUrl'] as String,
    developmentOnly: json['developmentOnly'] as bool? ?? false,
  );
  static ModelManifest decode(String value) =>
      ModelManifest.fromJson(jsonDecode(value) as Map<String, dynamic>);

  bool get hasProductionArtifact =>
      !developmentOnly &&
      downloadUrl.startsWith('https://') &&
      downloadSizeBytes > 0 &&
      RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256) &&
      (signature.isNotEmpty || format == 'gguf');
}
