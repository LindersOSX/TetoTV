# TetoTV privacy disclosure

Effective date: August 10, 2026

TetoTV is an independent Android application. It has no advertising SDK or
third-party analytics SDK. It has no TetoTV account system and does not sell personal data.
This disclosure describes the data handled by the app and by the optional
TetoTV pairing/update broker.

## Data kept on the device

TetoTV stores the following data locally:

- account and debrid credentials in Android Keystore-backed secure storage;
- playback history, resume positions, per-series preferences, tracker-sync
  outbox entries, installed source definitions, and app preferences;
- short-lived catalog/artwork caches and bounded performance or error
  diagnostics; and
- device playback capabilities such as Android version, ABI, decoder, HDR,
  memory class, and display/audio support.

This data remains until it is removed in TetoTV, Android app storage is
cleared, or the app is uninstalled. Disconnecting a service deletes that
service's saved credentials. Removing local history does not modify AniList or
MAL. Android's **Settings > Apps > TetoTV > Storage > Clear storage** removes
all TetoTV local data.

## Data sent to services selected by the user

TetoTV makes network requests only for app features the user uses:

- AniList, MAL, and Kitsu receive catalog, search, list, and progress requests;
- the selected debrid provider receives account validation, torrent/magnet,
  file-selection, and streaming requests;
- During eligible playback, AniSkip may receive a MAL title identifier,
  episode number, and episode duration to look up community intro/outro times.
  This lookup also supports the manual Skip button when automatic skipping is
  disabled;
- source repositories and extensions installed by the user receive the title,
  episode, and related request data needed to find sources;
- voice search uses Android's selected speech-recognition service. If a
  device cannot open its system voice prompt, TetoTV requests microphone
  permission and sends the spoken query to that recognition service only
  while the user has opened voice search;
- when a user-added Stremio source cannot use the available Kitsu identifier,
  Cinemeta may receive the anime title and year to resolve the corresponding
  IMDb series and episode identifier; and
- image hosts receive ordinary artwork requests.

Those independent services can see normal connection metadata such as the
device's IP address and user agent, and their own privacy policies and terms
apply. TetoTV does not bundle or recommend a streaming-source repository.

## Pairing and update broker

The TetoTV HTTPS broker adapts TV-friendly OAuth, phone-assisted source entry,
and signed APK update delivery:

- OAuth pairing holds the minimum one-time state and token material needed to
  deliver a completed login to the requesting device.
- Phone-assisted source entry holds submitted URLs in volatile memory for up
  to ten minutes. They are deleted after the authenticated device confirms
  local processing or when the session expires.
- The update proxy reads release metadata with a server-only credential and
  streams the signed universal APK. The credential is never sent to the app.
- The host may process ordinary connection metadata for security, rate
  limiting, and operational logs. TetoTV does not use it for advertising or
  cross-service tracking.

Pairing records are held in process memory, not a user-profile database. A
broker restart can end an active pairing session.

## Anonymous live activity count

When **Anonymous live count** is enabled in Settings, the app creates a random
per-launch session token. The token is kept only in app and broker memory and
is not a persistent device or user identifier. TetoTV reports only whether
that app session is active or currently playing video. It does not send the
show, episode, account, device identifier, stream provider, or URL.

The broker deletes an active session when the app opts out or closes normally,
and automatically expires it after about three minutes without a heartbeat.
Only aggregate active and streaming counts are publicly available. The host
may process IP addresses for short-lived rate limiting and normal operational
access logs. Users can disable this feature at any time in Settings.

## Diagnostics and sharing

Diagnostics stay on the device unless the user explicitly copies or shares a
report. Reports contain app/build and playback-capability information, bounded
performance/failure events, Android version, manufacturer/model, and provider
identifiers. TetoTV redacts credentials, signed URLs, magnets, hashes, and
common token formats before storage and again before export. Users should
still review a report before sharing it.

## Security and user choices

Network integrations require HTTPS. User-added endpoints are checked against
private/local addresses and are fetched through a constrained client. No
software can promise absolute security; users should revoke a service token if
they believe a device or account has been compromised.

All account connections, source installation, tracking sync, reminders,
automatic updates, and diagnostics sharing are optional. The app can be used
without connecting an anime-list account.

## Children and changes

TetoTV is not directed to children and does not knowingly collect a child's
personal information. This disclosure may change when features or hosting
change. The effective date will be updated for material changes.

## Contact

Privacy questions and deletion requests can be sent to the TetoTV maintainer
through the official project page: <https://github.com/LindersOSX/TetoTV>.
Before any broad public or store release, the distributor must ensure this
contact and a public HTTPS copy of this disclosure are accessible without an
account.
