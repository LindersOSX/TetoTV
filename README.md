# TetoTV

> **Development disclosure:** TetoTV includes code created and reviewed with
> AI-assisted development tools. Releases are tested and maintained by the
> project owner.

A Flutter Android TV application under active product development. It
currently includes:

- TetoTV launcher icon and TV banner artwork featuring Kasane Teto;
- a lightweight black-and-Teto-red 10-foot home screen with a full-width hero,
  compact TV navigation, poster shelves, and explicit D-pad focus treatment;
- a compact black/red D-pad/gamepad keyboard that does not invoke Android's
  covering system IME, now bottom-aligned and reduced to 710 logical pixels so
  the active field remains visible, with secure clipboard autofill;
- denser responsive layouts for 1440p and 4K televisions;
- QR/code pairing for Real-Debrid, TorBox, AniList, and MAL;
- TorBox device-code pairing plus optional API-token validation and encrypted
  account storage;
- AllDebrid phone PIN pairing and Premiumize personal-key validation;
- encrypted token and OAuth refresh-credential storage;
- Real-Debrid, TorBox, AllDebrid, and Premiumize magnet, cache/download
  progress, exact file selection, and secure direct-stream clients;
- concrete AniList GraphQL and MAL v2 list/progress repositories;
- live AniList trending, seasonal, search, and details screens with cached art,
  a mapping-backed Kitsu search/details fallback for AniList outages, plus
  navigable sequel, prequel, spin-off, and related-title cards;
- advanced AniList discovery filters, a weekly airing calendar with local TV
  reminders, franchise-order pages, and navigable studio/staff/cast credits;
- tracker-backed Watching, Planning, Completed, Dropped, and On Hold My List
  tabs, with remote-friendly status management for AniList and MAL;
- thumbnail-free episode controls that keep details pages compact and fast;
- episode-to-debrid resolution with a configurable provider or manual magnet
  fallback;
- user-configured Stremio-compatible torrent source manifests with TV filters
  for Sub, Dub/Dual Audio, quality, codec, HDR, size, provider, and seeders;
- no bundled torrent index, source repository, or automatically installed
  streaming extension; users explicitly add and install sources they trust;
- exact Stremio `fileIdx` preservation for correct episode selection inside
  batch torrents;
- a monotonic 90%-completion tracking outbox for both trackers;
- a device-agnostic three-tier player: native Android Media3 1.11.0 is the
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
entries that contain real AniList and MAL mappings, preserving tracker
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
6. Read [the AllDebrid flow](docs/ALL_DEBRID.md) and
   [Premiumize flow](docs/PREMIUMIZE.md).
7. Retain the [third-party playback notices](docs/THIRD_PARTY_NOTICES.md) when
   redistributing builds.
8. Review the [privacy disclosure](docs/PRIVACY.md) and the
   [public-release checklist](docs/PUBLIC_RELEASE_CHECKLIST.md) before sharing
   an APK outside a private test group.

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

Release builds include the trusted HTTPS broker origin declared in
`lib/core/config/app_config.dart`. Phone-assisted source entry and
private-release update metadata are pinned to that origin. Tracker OAuth uses
it by default and supports an explicitly saved self-hosted broker for advanced
deployments. Client secrets and the read-only GitHub release credential are
server-side environment variables only; they must never be compiled into an
APK.

## Current scope

The installed APK validates TV launch and focus, live AniList discovery and
search, supported debrid authorization, native Media3 playback
with MPV/libass and VLC fallbacks, and the client-side tracking/streaming flow.
Production deployment still requires:

- registered AniList and MAL OAuth applications and an HTTPS deployment
  of the included `broker/`;
- explicit user configuration of any source repository or Stremio-compatible
  manifest, for content the user is legally authorized to access;
- a unique protected Android release signing key with encrypted offline
  backups;
- codec, audio passthrough, and remote QA on the target physical TV boxes.

Local release APKs are placed in `build\fire-tv`. Release builds fail when
`android\key.properties` is absent so an APK can never be distributed with a
different accidental signature. Back up both that ignored properties file and
its keystore: Android will reject every future in-place update if the signing
identity is lost or changed.

Use `adb shell getprop ro.product.cpu.abilist` before choosing a split APK.
Many Fire TV devices, including Fire TV Stick 4K Max models, expose the
32-bit `armeabi-v7a` application ABI even when their CPU is 64-bit. Use the
universal release APK when the target ABI is unknown.

## Distribution and source policy

Public builds contain no torrent index, default marketplace repository,
preconfigured Stremio manifest, or GitHub credential. Source
repositories and compatible manifests must be entered and installed explicitly
by the user. The app checks the fixed TetoTV update broker; the broker uses a
fine-grained, repository-scoped, Contents-read-only credential from its server
environment to read a private release and streams only the signed universal
APK. No update-token field or shared update secret exists on the device.

Any token previously compiled into an APK, committed, or shared outside the
device must be treated as exposed and revoked. Moving a token into encrypted
device storage does not retroactively make an exposed credential safe.

Removing bundled source configuration reduces distribution risk but does not
guarantee that an app cannot receive a copyright or platform complaint.
Distributors remain responsible for the media sources, branding, policies, and
legal requirements that apply to their release. Retain
[the third-party notices](docs/THIRD_PARTY_NOTICES.md), the in-app legal notice,
and the Kasane Teto attribution when redistributing the app.

The sideload build requests Android's package-installer permission for its
signed self-updater. That permission is not suitable for a normal Google Play
listing. A Play-distributed variant must remove the in-app installer and
`REQUEST_INSTALL_PACKAGES`, then use Play's update mechanism instead.
