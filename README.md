# TetoTV

A Flutter Android TV application under active product development. It
currently includes:

- TetoTV launcher icon and TV banner artwork featuring Kasane Teto;
- a lightweight black-and-Teto-red 10-foot home screen with a full-width hero,
  compact TV navigation, poster shelves, and explicit D-pad focus treatment;
- a compact black/red D-pad/gamepad keyboard that does not invoke Android's
  covering system IME, now bottom-aligned and reduced to 710 logical pixels so
  the active field remains visible, with secure clipboard autofill;
- denser responsive layouts for 1440p and 4K televisions;
- QR/code pairing for Real-Debrid, TorBox, AniList, and MyAnimeList;
- optional manual Real-Debrid token entry with pre-save validation;
- TorBox device-code pairing plus optional API-token validation and encrypted
  account storage;
- encrypted token and OAuth refresh-credential storage;
- Real-Debrid and TorBox magnet, cache/download progress, exact file selection,
  and secure direct-stream clients;
- concrete AniList GraphQL and MyAnimeList v2 list/progress repositories;
- live AniList trending, seasonal, search, and details screens with cached art
  plus navigable sequel, prequel, spin-off, and related-title cards;
- advanced AniList discovery filters, a weekly airing calendar with local TV
  reminders, franchise-order pages, and navigable studio/staff/cast credits;
- tracker-backed Watching, Planning, Completed, Dropped, and On Hold My List
  tabs, with remote-friendly status management for AniList and MyAnimeList;
- thumbnail-free episode controls that keep details pages compact and fast;
- episode-to-debrid resolution with a configurable provider or manual magnet
  fallback;
- a Torrentio/Stremio-compatible master stream list with TV filters for Sub,
  Dub/Dual Audio, quality, codec, HDR, size, provider, and seeders;
- exact Stremio `fileIdx` preservation for correct episode selection inside
  batch torrents;
- a monotonic 90%-completion tracking outbox for both trackers;
- a feature-rich MPV/libass player using `media_kit`, with D-pad controls for
  audio, subtitles, picture fit, playback speed, subtitle size/position,
  audio/subtitle delay, contrast, stream failover, and decoder;
- exact SQLite-backed resume points and watch history, per-series playback
  preferences, configurable home shelves, and a short-lived AniList cache;
- ranked automatic debrid-stream failover, next-episode prewarming, trickplay
  screenshot previews, and a cancelable next-episode countdown;
- Android MediaSession controls, launcher Watch Next publishing, deep links,
  content frame-rate matching, HDMI-aware audio selection, and local device
  codec/HDR capability profiles;
- slow-frame/startup instrumentation plus an on-device redacted diagnostics
  export for physical-TV troubleshooting;
- copy-back MediaCodec rendering to avoid corrupt zero-copy surfaces, plus an
  automatic and remote-triggered software-video fallback;
- TV-safe stream ordering that prioritizes H.264/1080p SDR while preserving
  selectable HEVC, AV1, 4K, and HDR releases;
- automatic English/Dub audio-track preference with remote track switching;
- a debrid-only player gate that rejects unresolved or direct demo URLs;
- Android TV launcher declarations and a TV banner;
- domain boundaries for catalog and pluggable release sources.

AniList supplies the live discovery catalog. Local fallback content keeps the
shell usable while offline. The player diagnostics use media_kit's public
example stream and a bundled styled ASS subtitle only as a playback smoke test.

## Start here

1. Follow [Windows build setup](docs/BUILD_WINDOWS.md).
2. Read [the architecture](docs/ARCHITECTURE.md).
3. Read [the tracker pairing guide](docs/AUTH_BROKER.md) and the
   [deployable broker instructions](broker/README.md).
4. Read [the Real-Debrid flow](docs/REAL_DEBRID.md).
5. Read [the TorBox flow](docs/TORBOX.md).

Then run:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release --split-per-abi
```

The sideloadable debug APK is written to:

```text
build\app\outputs\flutter-apk\app-debug.apk
```

## Configuration

Copy the non-secret example:

```powershell
Copy-Item .\config\dev.example.json .\config\dev.json
```

Pass it to Flutter:

```powershell
flutter run --dart-define-from-file=.\config\dev.json
```

Never put an AniList/MAL client secret, a Real-Debrid token, a TorBox token, or
an OAuth access token in this JSON file. Tracker client secrets belong only in
the pairing broker; user credentials are stored with
`flutter_secure_storage`.

Release builds do not assume a broker hostname. The first AniList or MAL QR
attempt opens a compact broker-address setup panel unless a real HTTPS origin
was supplied with `AUTH_BROKER_BASE_URL`. The origin must resolve to the
deployed `broker/` service and report both providers as ready from `/health`.

## Current scope

The installed APK validates TV launch and focus, live AniList discovery and
search, Real-Debrid and TorBox device authorization, MPV/libass
playback, and the client-side tracking/streaming flow. Production deployment
still requires:

- registered AniList and MyAnimeList OAuth applications and an HTTPS deployment
  of the included `broker/`;
- review/configuration of the selected Stremio add-on for content the user is
  legally authorized to access;
- a private Android release signing key;
- codec, audio passthrough, and remote QA on the target physical TV boxes.

Local release APKs are placed in `build\fire-tv`. Builds fall back to the
machine's debug key when `android\key.properties` is absent; configure a
private release key before distributing updates to other users.
