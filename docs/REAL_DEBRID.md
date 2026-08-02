# Real-Debrid integration

The app supports two account setup paths:

1. **Connect by phone** uses Real-Debrid's official open-source device OAuth
   flow. The TV displays `https://real-debrid.com/device` as a QR code and a
   short user code. Access token, refresh token, and user-bound client
   credentials are encrypted with `flutter_secure_storage`.
2. **Personal token** accepts a token from
   `https://real-debrid.com/apitoken`. The app calls `GET /user` first and only
   saves a valid token. This is intended for personal sideloading; do not ship
   private tokens inside a public APK.

The OAuth client automatically refreshes an expiring access token when refresh
credentials are present. Disconnect removes all Real-Debrid credentials from
the device.

The player route also carries a Real-Debrid provider marker. URLs that were not
resolved by a supported debrid backend are rejected before MPV is created.

## Stream resolution

`RealDebridStreamResolver` performs:

1. display candidates from the configured `ReleaseSource` so the user can
   select Sub, Dub/Dual Audio, resolution, codec, size, and provider;
2. `POST /torrents/addMagnet`;
3. `GET /torrents/info/{id}`;
4. select the exact Stremio `fileIdx` when supplied, or match the episode
   filename with `POST /torrents/selectFiles/{id}`;
5. poll torrent info and emit progress;
6. use the first selected file link after status becomes `downloaded`;
7. `POST /unrestrict/link`;
8. pass the returned HTTPS URL directly to the MPV player.

Cached torrents normally advance to `downloaded` quickly. Uncached torrents
remain on the progress screen until Real-Debrid finishes or the resolver's
timeout is reached. The removed/undocumented instant-availability endpoint is
not used.

`TorrentioReleaseSource` reads a configurable Stremio add-on manifest. The
default development value is `https://torrentio.strem.fun/manifest.json`.
It only accepts torrent `infoHash` results; Real-Debrid credentials remain in
the app and are never placed in the add-on URL. Set
`STREMIO_ADDON_MANIFEST_URL` to another HTTPS `manifest.json` URL or an empty
value to disable it. Use only sources and content you are authorized to access.

The included `HostedReleaseSource` calls:

```text
GET {RELEASE_RESOLVER_BASE_URL}/v1/releases
  ?anilist_id=...
  &mal_id=...
  &title=...
  &episode=...
  &alternative_titles=Title%201%7CTitle%202
```

The resolver returns either an array or `{ "releases": [...] }`:

```json
{
  "releases": [
    {
      "info_hash": "hex-or-base32-hash",
      "magnet_uri": "magnet:?xt=urn:btih:...",
      "release_name": "Release name",
      "seeders": 12,
      "source_id": "user-configured-indexer",
      "is_batch": false
    }
  ]
}
```
