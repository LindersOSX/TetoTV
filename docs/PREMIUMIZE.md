# Premiumize integration

TetoTV supports a user's personal Premiumize API key. The key is validated
with `/api/account/info`, sent only as a Bearer authorization header, and saved
with Android Keystore-backed secure storage after an active plan is confirmed.
It is never placed in a URL, project configuration, release asset, or source
repository.

Premiumize OAuth device authorization requires a registered OAuth client, so
the public APK uses the official personal API-key path without embedding an
application secret.

## Episode flow

TetoTV first calls `/api/transfer/directdl` for an immediately available file
list. When the transfer is not ready, it creates and polls a cloud transfer,
then resolves the finished file or folder through the documented item/folder
endpoints. It chooses the episode's matching video file and passes its HTTPS
link to the same debrid-only player gate used by the other providers.

Official API documentation: <https://www.premiumize.me/api>.
