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
