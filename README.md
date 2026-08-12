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

Offline POIs come from the Overture Maps Places theme. During setup, the phone
uses its current coordinates to choose a radius and range-read the intersecting
tiles from Overture's public static PMTiles archive. The archive host therefore
sees the normal IP address and coarse tiles inherent in that one-time download;
it receives no account, device identity, or travel history. POI matching and
activity history remain local after installation.

Visited places are a separate private dataset in `private_user_data.db`. While the app is in the foreground, it checks the current location every 30 seconds. Remaining within 75 meters of the same downloaded POI for two minutes records one visit; another count requires at least four hours. Only the aggregate place, count, and first/last timestamps are stored—no raw route history. Visit history can be deleted independently from the Privacy screen.

The private database also contains a small user-managed custom POI layer. **My places → Set current location** saves Home, Work, or another named tag using the device's current coordinates. Custom POIs are matched before public Overture places, can accumulate visits in Most Visited, remain available independently of downloaded regions, and can be deleted separately.

## Run

```sh
flutter pub get
flutter run
```

Use deterministic mock GPS without device location:

```sh
flutter run --dart-define=USE_MOCK_LOCATION=true
```

Optional coordinates can be supplied with `MOCK_LATITUDE` and
`MOCK_LONGITUDE`. On a real phone, the operating-system geocoder supplies a
friendly municipality label while the coverage remains centered on the actual
coordinates. Setup defaults to 50 miles; 100 and 150 miles are available from
**Install or update home area**.

## Refresh Overture packages

The app now discovers Overture's current release through its STAC catalog and
range-reads the global Places PMTiles archive directly. It calculates the zoom
14 tiles intersecting a 50, 100, or 150-mile coordinate-centered area, decodes
the MVT features on-device, filters them to the requested radius, and writes a
compact local SQLite database. No Private Concierge location backend is used.

The older package-normalization helper remains useful for diagnostics:

```sh
overturemaps download --bbox=-90.042,34.738,-89.158,35.462 -f geojsonseq --type=place -o memphis.geojsonseq
python3 tool/normalize_overture_places.py memphis.geojsonseq assets/overture/us-tn-memphis.jsonl.gz us-tn-memphis --center=35.1,-89.6 --radius-miles=25
shasum -a 256 assets/overture/us-tn-memphis.jsonl.gz
```

The normalizer intentionally excludes Foursquare-sourced features. The live
PMTiles path reads the complete Overture Places theme, with the required notices
bundled under `assets/licenses`. Data attribution: Overture Maps Foundation,
[overturemaps.org](https://overturemaps.org/).

On-device speech is enabled only when Android reports an on-device recognizer. The app never silently falls back to a cloud recognizer. Android Auto provides Car App Library screens for Assistant and Nearby; direct car microphone and the native-to-Flutter POI bridge remain explicit next milestones.

## Verify

```sh
flutter test
flutter analyze
flutter build apk --debug
```
