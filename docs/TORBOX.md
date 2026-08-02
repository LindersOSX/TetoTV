# TorBox streaming

TetoTV supports TorBox as a second debrid backend. The app never starts a
BitTorrent client or connects to peers.

## Account setup

1. Open **Accounts & streaming** in TetoTV and choose **Connect by QR**.
2. Scan the TorBox QR code, confirm the six-digit code, and approve the TV.
3. The TV polls TorBox's device-token endpoint and validates the returned token
   with `GET /v1/api/user/me`.
4. The app stores the validated token with `flutter_secure_storage`.

Manual API-token entry remains available as a fallback.

TorBox currently requires a paid plan for third-party API streaming.

## Episode flow

1. Torrentio supplies release metadata and a magnet.
2. The user selects the exact Sub or Dub/Dual release.
3. TetoTV submits the magnet to
   `POST /v1/api/torrents/createtorrent`.
4. It polls `GET /v1/api/torrents/mylist` with `bypass_cache=true`.
5. It preserves Torrentio's `fileIdx` when selecting the episode from a batch,
   with episode-name matching as a fallback.
6. It requests the temporary CDN stream from
   `GET /v1/api/torrents/requestdl`.
7. Only that TorBox-generated HTTPS URL is admitted to the MPV player.

The API token is never placed in project configuration or source control.
