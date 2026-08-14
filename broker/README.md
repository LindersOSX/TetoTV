# TetoTV pairing and companion-services broker

This Node 20 service completes TV-friendly AniList and MyAnimeList pairing
without embedding provider secrets in the APK.

## Provider registration

Create an AniList developer application and register:

```text
https://tetotv-auth.onrender.com/oauth/anilist/callback
```

Create a MyAnimeList API client and register:

```text
https://tetotv-auth.onrender.com/oauth/myanimelist/callback
```

Copy `.env.example` to `.env`, supply both clients, and set
`PUBLIC_BASE_URL` to the externally reachable HTTPS origin. Start with:

```powershell
npm test
node --env-file=.env server.mjs
```

Confirm deployment health:

```powershell
Invoke-RestMethod https://tetotv-auth.onrender.com/health
```

Both `providers.anilist` and `providers.myanimelist` must be `true`. Then enter
the same origin in TetoTV's on-screen QR setup, or set it as
`AUTH_BROKER_BASE_URL` in the Flutter JSON configuration before building. Do
not copy either provider client secret into Flutter configuration.

The current production app deliberately uses two deployments of this broker:
`https://tetotv-auth.onrender.com` remains the AniList/MyAnimeList OAuth origin,
while `https://tetotv-updates-lindows.onrender.com` handles source pairing,
optional anonymous presence, and optional crash-report relay. App updates do
not pass through either deployment. Keep tracker callback registrations pointed
at the auth origin.

## Anonymous crash-report relay

The companion-services deployment can accept the app's optional, anonymous crash
reports and relay them to the separately hosted Discord bot. Configure these
server-only values on that deployment:

```text
CRASH_REPORT_BOT_URL=https://<bot-host>/crash-reports
CRASH_REPORT_SHARED_SECRET=<at-least-32-random-bytes>
```

Configure the same shared secret on the Discord bot. It is an internal
server-to-server credential and must never be placed in Flutter configuration,
an APK, a repository secret visible to clients, or a public URL. The broker
validates a fixed bounded schema, applies per-address rate limits, strips
credentials/URLs again, and signs the exact forwarded body with HMAC-SHA256.
It does not persist report bodies. Keep the bot endpoint HTTPS-only and verify
`crash_reporting: true` on the broker's `/health` before publishing an
APK that advertises this option.

Deploy behind HTTPS on a single Node instance. For horizontally scaled
production hosting, replace the in-memory pairing and rate-limit maps with a
shared TTL store such as Redis.

OAuth and source-pairing creation are separately rate-limited and each flow is
capped at 256 live in-memory sessions. MyAnimeList refresh requests also have a
separate upstream-protection limit and all OAuth upstream calls have a bounded
deadline. On Render, rate limits use the first `X-Forwarded-For` entry that
Render sets to the real client. For any other host, set `TRUST_PROXY=1` only
when a sanitizing reverse proxy is the sole network path to Node and appends
the real peer as the rightmost entry; otherwise the broker intentionally keys
limits from the socket address.

The human-readable code can never retrieve a token. Only the TV holding the
256-bit `device_code` can poll it, and successful delivery deletes the pairing.
The `/pair` page supports both QR deep links and manual TV-code entry.
MyAnimeList refresh tokens rotate through the broker and remain encrypted in
the Android Keystore between refreshes.

## Companion source entry

TetoTV can also create a ten-minute code for `/source-pair`, letting a user
paste long Marketplace repository and Torrent source manifest URLs on a phone or PC.
The browser receives only the human code. The 256-bit device code stays on the
TV, and the first valid browser submission wins. An authenticated device poll
leases the payload without deleting it, allowing safe redelivery after a
network interruption. Only after TetoTV processes every submitted item and
persists every accepted entry does it POST a count-only completion
acknowledgement; that acknowledgement deletes all URLs and retains a
short-lived sanitized receipt for the browser. Canceling an unclaimed dialog
sends an authenticated best-effort delete, and abandoned sessions expire
automatically.

After submission, the phone receives a random high-entropy receipt URL rather
than using the short human code as a status credential. The confirmation page
refreshes until the app reports either saved or rejected counts. It never
contains submitted URLs, device codes, account tokens, or rejection details.
The device completion contract is:

```text
POST /v1/source-pairings/:pairing_id/complete
Authorization: Pairing <device_code>

{
  "repositories_saved": 1,
  "manifests_saved": 1,
  "rejected_count": 0
}
```

Clients require `source_pairing_version: 2` from `/health`, so deploy this
broker protocol before publishing an APK that depends on saved receipts. A
valid browser submission starts a fresh bounded ten-minute processing window;
completion starts a fresh ten-minute window for the sanitized receipt.

Saved TetoTV account, tracker, and debrid tokens are never uploaded by
this flow. A source URL pasted by the user may itself contain provider
configuration, so it is kept only in the broker's in-memory session until the
TV acknowledges persistence or the session expires. Authenticated redelivery
is allowed after a network interruption. The TV independently repeats HTTPS,
DNS, private-address, type, and capacity validation before persisting anything.

Source pairings and rate limits are process-local memory. Keep a Render deploy
at one instance, or move these maps to an atomic shared TTL store before
horizontal scaling; otherwise a create, browser submit, and device poll may
reach different instances. Request sizes, URL lengths, live sessions, and
per-address create/submit/poll rates are bounded in `server.mjs`.

## Public deployment and privacy

Every response from an HTTPS-configured deployment includes HSTS, no-referrer,
no-sniff, frame-denial, cross-origin resource, and permissions headers. HTML
pairing pages additionally use a restrictive Content Security Policy. Set
`PUBLIC_BASE_URL` to one bare HTTPS origin; paths, credentials, query strings,
fragments, and HTTP origins are rejected.

The application process deliberately logs no request URLs, bodies, submitted
source URLs, OAuth codes, tokens, or provider response details.
It logs only startup and bounded error classes. Hosting-platform access logs
are outside this process and may still contain request metadata, opaque pairing
IDs, receipt IDs, and OAuth callback query parameters; configure and disclose
their retention separately.

The process keeps the following transient data only in memory:

- OAuth state, PKCE verifier, device-code hash, and delivered provider tokens
  for at most ten minutes; a successful authenticated device poll deletes the
  entire pairing immediately.
- Source URLs for at most ten minutes after browser submission; an
  authenticated persistence acknowledgement deletes the URLs immediately and
  retains count-only status for at most another ten minutes.
- Namespace-and-address SHA-256 rate-limit keys for roughly one minute. The
  raw address is not retained in the application map, though the hosting
  provider may process it independently.

A public, unauthenticated disclosure is served at `/privacy`; `/health`
advertises its canonical HTTPS URL. The page uses the same no-store, CSP,
referrer, framing, MIME-sniffing, permissions, and HSTS protections as the
broker's other public HTML. Keep its human-reviewed content synchronized with
`docs/PRIVACY.md`, including Discord Rich Presence and local cache/reset
choices. Re-review the public community contact and hosting-provider retention
before broad public or app-store distribution.

## App updates bypass this broker

TetoTV reads both update channels anonymously from their public GitHub
repositories:

```text
Public: https://api.github.com/repos/LindersOSX/TetoTV-Releases/releases/latest
Beta:   https://api.github.com/repos/LindersOSX/TetoTV/releases/latest
```

The app sends no GitHub token or shared Beta credential, prefers the release
asset ending in `-universal.apk`, and downloads it directly from the asset's
`browser_download_url`. This source tree contains no update-specific GitHub
credentials, Beta access hashes, or `/v1/app-updates/*` routes. An older live
deployment may remain temporarily as a one-release migration bridge for app
versions that predate the direct-GitHub updater; deploy this cleanup after that
migration window closes. See
[`docs/UPDATE_CHANNELS.md`](../docs/UPDATE_CHANNELS.md) for the client and
publishing contract.
