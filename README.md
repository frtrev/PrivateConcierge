# Private Concierge

A privacy-first Flutter foundation for Android and Android Auto. Personal location, speech text, preferences, and behavior remain on the device. There is no account, analytics SDK, advertising SDK, or personal-data backend.

## Architecture

- `lib/app`: composition root and application shell
- `lib/core/models`: platform-independent domain models and geographic math
- `lib/services`: small contracts for location, geography, downloads, voice, commands, nearby search, notifications, private storage, and public-only networking
- `lib/database` and `lib/repositories`: SQLite-backed public POI boundary
- `lib/features`: bootstrap, home, nearby, voice assistant, and privacy presentation
- `android/.../car`: Android for Cars template service isolated from Flutter UI

Public geographic data uses `public_geography.db`. Private user data uses `private_user_data.db`; clearing private data does not remove downloaded regions.

Offline POIs come from the Overture Maps Places theme. The repository contains compact, checksum-verified regional packages generated from the official GeoParquet distribution. Downloads are static files, so the phone never submits its current coordinates to a geographic query service. If a package host is temporarily unavailable, the app uses the matching copy bundled in the APK.

## Run

```sh
flutter pub get
flutter run
```

Use mock Memphis GPS without device location:

```sh
flutter run --dart-define=USE_MOCK_LOCATION=true
```

Memphis, Nashville, and Dallas can also be selected from **Download an offline region** on the home screen. Each installs thousands of real Overture places into the local SQLite database.

## Refresh Overture packages

Install the official `overturemaps` Python client, export the `place` type for a region's bounding box as GeoJSONSeq, then normalize it:

```sh
overturemaps download --bbox=-90.35,34.95,-89.65,35.38 -f geojson --type=place -o memphis.geojsonseq
python3 tool/normalize_overture_places.py memphis.geojsonseq assets/overture/us-tn-memphis.jsonl.gz us-tn-memphis
shasum -a 256 assets/overture/us-tn-memphis.jsonl.gz
```

Update the matching checksum and version in the app after regeneration. The normalizer intentionally excludes Foursquare-sourced features, leaving the compact packages under Overture's CDLA Permissive/CC0 sources. Data attribution: Overture Maps Foundation, [overturemaps.org](https://overturemaps.org/).

On-device speech is enabled only when Android reports an on-device recognizer. The app never silently falls back to a cloud recognizer. Android Auto provides Car App Library screens for Assistant and Nearby; direct car microphone and the native-to-Flutter POI bridge remain explicit next milestones.

## Verify

```sh
flutter test
flutter analyze
flutter build apk --debug
```
