# TetoTV privacy disclosure

Effective date: August 21, 2026

The stable public copy is available without an account or authentication at
<https://tetotv-bot.wisp.uno/privacy>.

TetoTV is an independent Android application. It has no advertising SDK or
third-party analytics SDK. It has no TetoTV account system and does not sell personal data.
This disclosure describes the data handled by the app, the optional TetoTV
pairing services, and the optional crash-report receiver.

## Data kept on the device

TetoTV stores the following data locally:

- account and debrid credentials in Android Keystore-backed secure storage;
- an optional Jellyfin server address, username, access token, and random app
  device ID in Keystore-backed secure storage; the Jellyfin password is used
  only for sign-in and is not saved;
- an optional Plex server address, X-Plex-Token, and random client identifier
  in Keystore-backed secure storage;
- playback history, resume positions, per-series preferences, tracker-sync
  outbox entries, installed source definitions, and app preferences;
- short-lived catalog/artwork caches and bounded performance or error
  diagnostics; and
- device playback capabilities such as Android version, ABI, decoder, HDR,
  memory class, and display/audio support.

This data remains until it is removed in TetoTV, Android app storage is
cleared, or the app is uninstalled. Disconnecting a service deletes that
service's saved credentials. Removing local history does not modify AniList or
MAL. TetoTV's **Settings > System > Reset TetoTV** action and Android's
**Settings > Apps > TetoTV > Storage > Clear storage** both remove all TetoTV
local data. The separate **Clear cache** action removes only temporary files
and retains accounts, preferences, sources, and history.

## Data sent to services selected by the user

TetoTV makes network requests only for app features the user uses:

- AniList, MAL, and Kitsu receive catalog, search, list, and progress requests;
- the selected debrid provider receives account validation, torrent/magnet,
  file-selection, and streaming requests;
- During eligible playback, AniSkip may receive a MAL title identifier,
  episode number, and episode duration to look up community intro/outro times.
  This lookup also supports the manual Skip button when automatic skipping is
  disabled;
- when filler labels are enabled or a user enables **Skip filler** for
  a series, Jikan may receive the public MAL title identifier and paginated
  episode-list requests needed to read its filler flags. If AniList does not
  provide a MAL mapping, TetoTV can send one public anime title as a bounded
  exact-match search; the expected episode count and season year are used only
  on the device to reject ambiguous results. TetoTV does not send Jikan an
  account identifier, tracker list, selected stream, or playback history.
  Public lookup metadata (MAL identifier, lookup route, fetch time, known
  episode count, and confirmed filler episode numbers) is treated as valid for
  24 hours; expired records are ignored and can remain in application cache
  storage until they are overwritten or application data is cleared;
- enabled source repositories and Web-stream extensions installed by the user
  receive the title, episode, and related request data needed to find sources.
  To reduce TV loading delays, this discovery can begin after encrypted source
  preferences finish loading when an episode is selected on its details page;
  changing the selected episode or leaving the page cancels that observer.
  TetoTV does not ask a debrid provider to resolve a torrent merely from
  opening details. If next-episode autoplay is enabled, the selected debrid
  provider or Web extension can be contacted again during the final ten
  minutes of playback to prepare the next episode;
- voice search uses Android's selected speech-recognition service. If a
  device cannot open its system voice prompt, TetoTV requests microphone
  permission and sends the spoken query to that recognition service only
  while the user has opened voice search;
- when a user-added Stremio source cannot use the available Kitsu identifier,
  Cinemeta may receive the anime title and year to resolve the corresponding
  IMDb series and episode identifier; and
- image hosts receive ordinary artwork requests.

When the user opens local media, Android's system file picker grants TetoTV
read access only to the selected video. TetoTV does not request broad storage
access. A durable provider grant and a hashed resume key can be retained for a
recent file; providers that do not grant durable access work only for the
current app session. USB and internal-storage video contents are not uploaded
by this feature.

When the user connects Jellyfin, TetoTV sends the entered username and password
directly to that server for authentication, stores the returned access token,
and sends the token back to that same server for library, artwork, playback,
and logout requests. HTTPS is recommended. The app permits HTTP only after a
warning and only for an explicit numeric private-network address or localhost;
HTTP credentials and video traffic are not encrypted. Jellyfin traffic does
not pass through the TetoTV broker.

When the user connects Plex, TetoTV sends the saved X-Plex-Token directly to
that server in an HTTP request header for library, artwork, and playback
requests. The token is never placed in a media or artwork URL. Redirects are
not followed for authenticated metadata or artwork requests. HTTPS is
recommended; private-network HTTP requires the same explicit warning and has
the same lack of transport encryption described for Jellyfin. Plex traffic
does not pass through the TetoTV broker.

When the user explicitly links Discord and enables **Discord Rich Presence**,
TetoTV sends Discord the current anime title, episode number, playing or paused
state, playback timing, and the public show-artwork URL so Discord can display
that activity with the show's thumbnail. Discord OAuth
access and refresh tokens are stored in Android Keystore-backed secure storage.
Disabling Rich Presence stops sharing playback activity; unlinking Discord also
revokes the connection when possible and deletes the saved tokens from TetoTV.
TetoTV never asks for or stores the user's Discord password. Playback opened
from USB, internal storage, Jellyfin, or Plex is excluded from Rich Presence so
private filenames and media-library titles are not shared.

On Android TV and Fire TV, Discord linking uses Discord's limited-input device
authorization directly. TetoTV sends a one-time authorization request to
Discord and polls Discord only until the link succeeds, expires, or is
canceled. The private device code is kept only in app memory during that
attempt; completed access and refresh tokens use the same Android
Keystore-backed secure storage described above. The TetoTV broker is not
involved in Discord linking.

Those independent services can see normal connection metadata such as the
device's IP address and user agent, and their own privacy policies and terms
apply. TetoTV does not bundle or recommend a streaming-source repository.

## Pairing broker

TetoTV uses separate HTTPS services for TV-friendly tracker OAuth and
phone-assisted source entry:

- OAuth pairing holds the minimum one-time state and token material needed to
  deliver a completed login to the requesting device.
- Phone-assisted source entry holds submitted URLs in volatile memory for up
  to ten minutes. They are deleted after the authenticated device confirms
  local processing or when the session expires. This flow is hosted in the
  Wispbyte TetoTV bot service at <https://tetotv-bot.wisp.uno>; the service does
  not fetch submitted source URLs, and the app independently validates a public
  HTTPS destination before saving or fetching it.
- App updates do not pass through this broker. Public and Beta release metadata
  are requested anonymously from their respective public GitHub repositories,
  and the signed universal APK is downloaded directly from GitHub's release
  asset URL. TetoTV sends no GitHub token or shared Beta credential.
- The host may process ordinary connection metadata for security, rate
  limiting, and operational logs. TetoTV does not use it for advertising or
  cross-service tracking.

Pairing records are held in process memory, not a user-profile database. A
broker restart can end an active pairing session.

## Watch Together

Watch Together is optional. Creating or joining a room sends the Wispbyte
TetoTV service an eight-character room code, a high-entropy room capability,
public catalog identity such as AniList title ID and episode number, an
optional opaque release-timeline fingerprint, playback position and
play/pause state, readiness counts, and request timing. It does not send a
stream URL, HTTP header, Plex or Jellyfin address/token, debrid credential,
magnet link, local filename/path, or video/audio bytes.

Room state and hashed capabilities are held only in the bot process, are
bounded, and expire automatically within six hours or sooner after inactivity.
The service uses ordinary connection metadata for rate limiting and abuse
prevention. There is no room history or TetoTV user profile database.

The public <https://tetotv-bot.wisp.uno/watch> page can join a room and play a
video selected through the browser's local file picker. The selected file is
represented by a browser-local `blob:` URL and is never uploaded to TetoTV.
Every participant must independently choose a lawful source or local copy.
Because different releases can have different cuts, the app can display a
timeline warning and use coarse synchronization when fingerprints differ.

## Diagnostics and sharing

Anonymous crash reporting is disabled by default. First-time setup and Settings
both let the user explicitly enable or disable it. When enabled, an unexpected
handled app error or unhandled Flutter error can be sent immediately; a JVM
crash is kept locally and sent after the next launch because a terminated
process cannot use the network. On
Android versions that expose historical process-exit details, native crashes
and ANRs can also be recovered on the next launch. TetoTV sends only the app
version/build, crash category, Android
version, CPU architecture, TV-or-phone class, time, and a bounded redacted
technical error/stack trace. It does not intentionally include the show,
episode, account, device or installation identifier, source/provider, URL,
credential, playback history, or full diagnostics database.

The app sends reports over HTTPS to the dedicated TetoTV crash-report receiver
at <https://tetotv-bot.wisp.uno>. That receiver validates and rate-limits each
report, adds a random per-incident reference, and posts it through the TetoTV
Discord bot to the designated crash report channel. Reports remain in Discord
according to that channel's access and retention settings until a moderator
deletes them. The receiver does not store report bodies, though Wispbyte and
Discord process ordinary connection/request metadata under their own policies.
Disabling reporting deletes any queued unsent report and prevents later crashes
from being sent.

Other bounded diagnostics stay on the device unless the user explicitly
copies, exports, or chooses **Send to support** and confirms the disclosure.
That explicit send posts a maximum 480,000-character redacted JSON report over HTTPS to
<https://tetotv-bot.wisp.uno>. The receiver validates and redacts it again,
posts it through the bot to the private diagnostic support channel, and returns
an opaque per-report reference only after Discord accepts the message. A retry
of the same button press is acknowledged without creating a duplicate post.
The app does not contain the Discord bot token, incident secret, or destination
channel configuration.

Manually sent or exported reports contain app/build and
playback-capability information, bounded performance/failure events, Android
version, manufacturer/model, and provider identifiers. TetoTV redacts
account identity, credentials, signed URLs, magnets, hashes, file paths,
network addresses, and common token formats before storage and again before
sending or export. Users should still review a
manually exported report before sharing it through another app.

## Security and user choices

Network integrations require HTTPS except an explicitly approved Jellyfin or Plex
connection to a numeric private-network address or localhost. User-added
endpoints are checked against their expected network boundary and are fetched
through constrained clients. No
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

Privacy questions, support requests, and deletion requests can be sent to the
TetoTV maintainer through the public TetoTV Discord community:
<https://discord.gg/juC6k7d4WY>. Before any broad public or store release, the
distributor must ensure this contact and a public HTTPS copy of this disclosure
remain accessible.
