# AllDebrid integration

TetoTV supports AllDebrid through its official API and never embeds a shared
account credential.

## Account setup

1. Choose **AllDebrid** under **Settings > Streaming**.
2. Use **Connect by phone** to start AllDebrid's PIN flow, or enter a personal
   API key manually.
3. TetoTV validates the key with the authenticated user endpoint and requires
   an active premium account before saving it with Android Keystore-backed
   secure storage.

The PIN flow uses `/v4.1/pin/get` and `/v4/pin/check`. Disconnecting removes
the saved key from the device.

## Episode flow

For a release explicitly selected by the user, TetoTV uploads its magnet,
polls `/v4.1/magnet/status`, obtains the ready file tree from
`/v4/magnet/files`, chooses the matching video file, and unlocks only that
file's link. Only the resulting HTTPS link is passed to the player.

Official API documentation: <https://docs.alldebrid.com/>.
