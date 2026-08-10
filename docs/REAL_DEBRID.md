# Real-Debrid integration

The app uses Real-Debrid's official open-source device OAuth flow. The TV
displays `https://real-debrid.com/device` as a QR code and a short user code.
Access token, refresh token, and user-bound client credentials are encrypted
with `flutter_secure_storage`.

TetoTV does not ask users to paste a Real-Debrid private API token. Existing
encrypted credentials from older private builds remain usable until the user
disconnects the account, but new connections use device OAuth only. Never ship
account tokens inside an APK or source file.

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
4. select an exact source-provided file index when supplied, or match the episode
   filename with `POST /torrents/selectFiles/{id}`;
5. poll torrent info and emit progress;
6. use the first selected file link after status becomes `downloaded`;
7. `POST /unrestrict/link`;
8. pass the returned HTTPS URL directly to the MPV player.

Cached torrents normally advance to `downloaded` quickly. Uncached torrents
remain on the progress screen until Real-Debrid finishes or the resolver's
timeout is reached. The removed/undocumented instant-availability endpoint is
not used.

TetoTV ships without a torrent index, source repository, or preconfigured
Stremio add-on. A user may explicitly add a compatible HTTPS manifest in the
app. The adapter only accepts torrent `infoHash` results; Real-Debrid
credentials remain on the device and are never placed in an add-on URL. Use
only sources and content you are authorized to access.

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
