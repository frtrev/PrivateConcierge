# Charon Local AI

## Current status

The app ships a pinned manifest for the public `bartowski/Qwen_Qwen3-0.6B-GGUF` Q4_K_M artifact and uses the federated `lib_llama_cpp` CPU runtime on Android and iOS. The model remains optional: it is downloaded only after consent, and Basic Charon is always the fallback.

The downloader uses application-private storage, a `.partial` file, HTTP range resume, persisted byte progress, Wi-Fi-only policy, available-space checks, SHA-256 verification, staged atomic activation, pause/resume/cancel, restart recovery, and a required native inference smoke test. A failed update is staged separately and cannot replace the current model.

No executable code is downloaded. The GGUF is data-only and remains in application-private storage. The native llama.cpp runtime is included in the reviewed app binary.

## Production artifact and licensing

The configured file is `Qwen_Qwen3-0.6B-Q4_K_M.gguf`, pinned to Hugging Face repository commit `60b85c0e3d8fe0f6474f406922a26d12aca4550d`. Its exact size is 484,220,320 bytes and SHA-256 is `9acfc1e001311f34b4252001b626f2e466d592a42065f66571bff3790d4e1b14`. Qwen3 is Apache-2.0; the Q4_K_M conversion is community-published and public, not an official Qwen-hosted quantization.

Canonicalize the manifest excluding `signature`, sign it with the release manifest private key, and embed only the public verification key in the app. Signature verification must precede download; SHA-256 verification and an inference smoke test must precede the atomic move to the active version. Rotate keys through an app update.

For an internal production build, inject the complete reviewed manifest into the app binary:

```sh
flutter build apk --release --dart-define=CHARON_LOCAL_AI_MANIFEST_JSON='{"schemaVersion":1,...}'
```

The bundled GGUF manifest is trusted through normal app signing and pins an immutable repository revision plus SHA-256. Remote manifests must additionally carry a verified signature. Do not put credentials or gated-model tokens in either mechanism.

## Runtime notes and remaining hardening

- The current downloader supports range resume while the app is alive and restart recovery from `.partial`; moving transfer ownership to WorkManager/background `URLSession` remains future hardening.
- The published runtime prebuilts are CPU-only. Android requires API 28 or newer; iOS requires version 13 or newer.
- Add a signed remote-manifest path before allowing model updates without an app release.
- Validate CPU architecture, OS, available memory/storage, runtime feature support, thermal/memory failures, and the exact tested device matrix centrally.

Store review notes should describe the download as data consumed by functionality already in the reviewed binary. The pack must never include Dart/JavaScript, DEX/JAR, `.so`, frameworks, dynamic libraries, executables, or scripts.

## Command safety and privacy

The model may only propose registered structured functions. The validator rejects unknown functions, malformed arguments, invalid confidence, and sensitive actions lacking confirmation. Existing services supply factual place/location data and execute actions. The model cannot access files/network/permissions or execute actions directly. Production logs contain state, duration, intent/confidence band, and fallback reason only—never transcripts, prompts, model output, contacts, or coordinates.

Local inference does not upload requests and does not enable analytics. Model downloads expose ordinary network metadata. Map and business providers remain subject to their existing online behavior. Removing Local AI must delete model files but retain the Wi-Fi preference.

## Testing

Run:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --debug --no-codesign
```

For delivery testing, serve a signed fixture supporting HTTP ranges. Interrupt during download, kill/relaunch, and verify byte-accurate resume. Repeat with insufficient space, cellular-only connectivity, a wrong checksum, a modified signature, truncated content, and a failed update; the prior verified version must remain active. Queue simultaneous requests and confirm serialization. Exercise phone, Android Auto, and CarPlay requests and confirm all use the same `AssistantEngine` and silently fall back.

On real Android/iPhone devices: confirm the 462 MB displayed download size, cellular policy, pause/resume/cancel, restart recovery, ready only after smoke test, the On-device indicator, toggle/fallback, removal warning, and private file protection. Confirm no model management appears in automotive UI.

The model can later be replaced by changing the manifest; UI and assistant routing depend only on `LocalAiService` and typed results.
