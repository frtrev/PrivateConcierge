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

## Run

```sh
flutter pub get
flutter run
```

Use mock Memphis GPS without device location:

```sh
flutter run --dart-define=USE_MOCK_LOCATION=true
```

Memphis, Nashville, and Dallas can also be selected from **Select development region** on the home screen. Each downloads named POIs from OpenStreetMap through Overpass using the region's fixed public bounding box. User coordinates are never included in that request. Downloaded JSON is SHA-256 fingerprinted, normalized, and transactionally installed in the public SQLite database.

For locations outside the bundled development regions, the app rounds the current coordinates locally to 0.1 degree, adds a coverage margin, and asks for consent before submitting that approximate bounding box to OpenStreetMap. The precise GPS point, location history, account data, and device identifiers are not included. Nearby queries then run locally with a default radius of 50 miles.

POI data is © OpenStreetMap contributors and available under the Open Database License: https://www.openstreetmap.org/copyright

On-device speech is enabled only when Android reports an on-device recognizer. The app never silently falls back to a cloud recognizer. Android Auto provides Car App Library screens for Assistant and Nearby; direct car microphone and the native-to-Flutter POI bridge remain explicit next milestones.

## Verify

```sh
flutter test
flutter analyze
flutter build apk --debug
```
