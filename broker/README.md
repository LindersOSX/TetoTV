# TetoTV OAuth broker

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

Deploy behind HTTPS on a single Node instance. For horizontally scaled
production hosting, replace the in-memory pairing and rate-limit maps with a
shared TTL store such as Redis.

The human-readable code can never retrieve a token. Only the TV holding the
256-bit `device_code` can poll it, and successful delivery deletes the pairing.
The `/pair` page supports both QR deep links and manual TV-code entry.
MyAnimeList refresh tokens rotate through the broker and remain encrypted in
the Android Keystore between refreshes.

## Companion source entry

TetoTV can also create a ten-minute code for `/source-pair`, letting a user
paste long Marketplace repository and Stremio manifest URLs on a phone or PC.
The browser receives only the human code. The 256-bit device code stays on the
TV, the first valid browser submission wins, and a successful device poll
deletes the payload before responding. Canceling the dialog sends an
authenticated best-effort delete; abandoned sessions expire automatically.

Saved TetoTV account, tracker, debrid, and updater tokens are never uploaded by
this flow. A source URL pasted by the user may itself contain provider
configuration, so it is kept only in the broker's in-memory session until the
TV retrieves it once. The TV independently repeats HTTPS, DNS, private-address,
type, and capacity validation before persisting anything.

Source pairings and rate limits are process-local memory. Keep a Render deploy
at one instance, or move these maps to an atomic shared TTL store before
horizontal scaling; otherwise a create, browser submit, and device poll may
reach different instances. Request sizes, URL lengths, live sessions, and
per-address create/submit/poll rates are bounded in `server.mjs`.

## Private GitHub release updates

The broker can publish a deliberately narrow view of the latest private
TetoTV release without putting a GitHub credential in the APK. Add these
server-side environment variables in Render:

```text
GITHUB_RELEASE_TOKEN=<fine-grained token>
GITHUB_RELEASE_REPOSITORY=LindersOSX/TetoTV
```

Restrict the fine-grained token to only the TetoTV repository, grant only
`Contents: Read-only`, and set an expiration date. Never pass this value as a
Flutter build define, commit it to `.env`, or expose it in a client settings
field. The broker health response reports only `app_updates: true` or `false`.

The Android app uses the following public broker contract and sends no GitHub
credential:

```text
GET /v1/app-updates/latest
GET /v1/app-updates/releases/vX.Y.Z/assets/ASSET_ID/universal.apk
HEAD /v1/app-updates/releases/vX.Y.Z/assets/ASSET_ID/universal.apk
```

The metadata endpoint returns only the version, tag, title, release notes,
publication time, and a single sanitized universal-APK descriptor. The
descriptor's `download_url` points back to an immutable tag-and-asset-ID path
on the broker. The APK endpoint accepts one standard `Range`, returns `206`
when requested, and emits an asset-specific `ETag`, allowing interrupted
downloads to resume without combining bytes from different releases.

The proxy will serve only a non-draft, non-prerelease `vX.Y.Z` release and the
exact `TetoTV-vX.Y.Z-universal.apk` asset from the configured repository. It
does not accept repository or upstream URL parameters from the client. The
strict tag and numeric asset-ID path segments must match a broker-allowlisted
release. GitHub redirects are followed only a bounded number of times to HTTPS
GitHub download hosts, and the Authorization header is removed before the
redirected request. Metadata and binary size/type are validated, responses use
`no-store`, and metadata/download calls have separate per-address rate limits.
Metadata cache misses are coalesced. APK delivery is capped at four concurrent
streams, twelve starts per minute process-wide, and four starts per minute per
address for this private/friends deployment. Move binary delivery to dedicated
object storage or a CDN before using the updater at public scale.
Versioned paths are accepted only for the latest release or a release recently
advertised by this broker; arbitrary historical tags and asset IDs are not a
GitHub download oracle.

Example sanitized metadata:

```json
{
  "version": "1.11.6",
  "tag_name": "v1.11.6",
  "name": "TetoTV v1.11.6",
  "release_notes": "...",
  "published_at": "2026-08-10T00:00:00.000Z",
  "asset": {
    "name": "TetoTV-v1.11.6-universal.apk",
    "size": 113650688,
    "content_type": "application/vnd.android.package-archive",
    "download_url": "https://tetotv-auth.onrender.com/v1/app-updates/releases/v1.11.6/assets/116001/universal.apk"
  }
}
```
