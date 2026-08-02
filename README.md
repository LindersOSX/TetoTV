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
- live AniList trending, seasonal, search, and details screens with cached art,
  a mapping-backed Kitsu search/details fallback for AniList outages, plus
  navigable sequel, prequel, spin-off, and related-title cards;
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
- a device-agnostic three-tier player: native Android Media3 1.10.1 is the
  default, MPV/libass handles advanced ASS and unusual-codec compatibility,
  and VLC remains the final software fallback;
- direct native `PlayerView`/`SurfaceView` video output with an OkHttp data
  source, so normal playback bypasses Flutter's texture/compositor path while
  retaining debrid headers, redirects, and HTTP range requests;
- automatic H.264 Hi10P/High 10 detection and software-decoder preference
  routing instead of repeatedly sending unsupported profiles to hardware;
- D-pad controls for audio, subtitles, picture fit, playback speed, subtitle
  size/position, audio/subtitle delay, contrast, stream failover, and decoder;
- exact SQLite-backed resume points and watch history, per-series playback
  preferences, configurable home shelves, and a short-lived AniList cache;
- ranked automatic debrid-stream failover, next-episode prewarming, trickplay
  screenshot previews, and a cancelable next-episode countdown;
- Android MediaSession controls, launcher Watch Next publishing, deep links,
  content frame-rate matching, HDMI-aware audio selection, and local device
  codec/HDR capability profiles;
- slow-frame/startup instrumentation plus an on-device redacted diagnostics
  export for physical-TV troubleshooting;
- native first-frame and dropped-frame monitoring, compatible-stream retry,
  independent MPV compatibility playback, and VLC software recovery as the
  final fallback;
- TV-safe stream ordering that prioritizes H.264/1080p SDR while preserving
  selectable HEVC, AV1, 4K, and HDR releases;
- automatic English/Dub audio-track preference with remote track switching;
- a debrid-only player gate that rejects unresolved or direct demo URLs;
- Android TV launcher declarations and a TV banner;
- universal and split-per-ABI builds for `armeabi-v7a`, `arm64-v8a`, and
  emulator `x86_64` targets across Android TV and Fire TV hardware;
- domain boundaries for catalog and pluggable release sources.

AniList supplies the primary live discovery catalog. When AniList temporarily
suspends public API access, search and selected-title details fall back to Kitsu
entries that contain real AniList and MyAnimeList mappings, preserving tracker
and playback identifiers. Local fallback content keeps the shell usable while
offline. Player diagnostics use bundled H.264/AAC and styled ASS assets only as
offline playback smoke tests.

## Start here

1. Follow [Windows build setup](docs/BUILD_WINDOWS.md).
2. Read [the architecture](docs/ARCHITECTURE.md).
3. Read [the tracker pairing guide](docs/AUTH_BROKER.md) and the
   [deployable broker instructions](broker/README.md).
4. Read [the Real-Debrid flow](docs/REAL_DEBRID.md).
5. Read [the TorBox flow](docs/TORBOX.md).
6. Retain the [third-party playback notices](docs/THIRD_PARTY_NOTICES.md) when
   redistributing builds.

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
search, Real-Debrid and TorBox device authorization, native Media3 playback
with MPV/libass and VLC fallbacks, and the client-side tracking/streaming flow.
Production deployment still requires:

- registered AniList and MyAnimeList OAuth applications and an HTTPS deployment
  of the included `broker/`;
- review/configuration of the selected Stremio add-on for content the user is
  legally authorized to access;
- a private Android release signing key;
- codec, audio passthrough, and remote QA on the target physical TV boxes.

Local release APKs are placed in `build\fire-tv`. Builds fall back to the
machine's debug key when `android\key.properties` is absent; configure a
private release key before distributing updates to other users.

Use `adb shell getprop ro.product.cpu.abilist` before choosing a split APK.
Many Fire TV devices, including Fire TV Stick 4K Max models, expose the
32-bit `armeabi-v7a` application ABI even when their CPU is 64-bit. Use the
universal release APK when the target ABI is unknown.
