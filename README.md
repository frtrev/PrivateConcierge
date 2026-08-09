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

Visited places are a separate private dataset in `private_user_data.db`. While the app is in the foreground, it checks the current location every 30 seconds. Remaining within 75 meters of the same downloaded POI for two minutes records one visit; another count requires at least four hours. Only the aggregate place, count, and first/last timestamps are stored—no raw route history. Visit history can be deleted independently from the Privacy screen.

The private database also contains a small user-managed custom POI layer. **My places → Set current location** saves Home, Work, or another named tag using the device's current coordinates. Custom POIs are matched before public Overture places, can accumulate visits in Most Visited, remain available independently of downloaded regions, and can be deleted separately.

## Run

```sh
flutter pub get
flutter run
```

Use mock Memphis GPS without device location:

```sh
flutter run --dart-define=USE_MOCK_LOCATION=true
```

The phone identifies the supported home city from its location. Memphis setup defaults to 50-mile coverage, with genuine 100- and 150-mile Overture packages available from **Install or update home area**. One verified home-area package is installed in the local SQLite database at a time.

## Refresh Overture packages

Install the official `overturemaps` Python client, export the `place` type for a region's bounding box as GeoJSONSeq, then normalize it:

```sh
overturemaps download --bbox=-90.042,34.738,-89.158,35.462 -f geojsonseq --type=place -o memphis.geojsonseq
python3 tool/normalize_overture_places.py memphis.geojsonseq assets/overture/us-tn-memphis.jsonl.gz us-tn-memphis --center=35.1,-89.6 --radius-miles=25
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
