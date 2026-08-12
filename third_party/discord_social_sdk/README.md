# Discord Social SDK

TetoTV uses the official Discord Social SDK for optional, user-authorized Rich
Presence on Android TV, Fire TV, and Android phones.

- Version: `1.10.18369`
- Release date: 2026-08-04
- Upstream archive: `DiscordSocialSdk-1.10.18369.zip`
- Vendored Android artifact: `android/app/libs/discord_partner_sdk.aar`
- AAR SHA-256: `85A5B0C9B2B828C84D27A7D7839D834BD7DAC323895A691E2A19E056543D2FAA`
- Application ID: `1536801401710055474`
- Rich Presence large-image key: `tetotv_app_icon`

## Rich Presence artwork

Discord does not read the Android launcher icon from the APK. The TetoTV
Discord application therefore has `assets/branding/tetotv_icon.png` uploaded
under **Rich Presence > Art Assets** with the exact key
`tetotv_app_icon`. `discord_rich_presence.cpp` sends that key as the activity's
large image and labels it `TetoTV`.

The portal key and native key must remain identical. If the portal asset is
removed or renamed, Discord displays a placeholder/question-mark image until
the matching asset exists and its cache refreshes.

The full upstream archive is not committed. Only the Android release AAR and
the supplied open-source notices are retained. Access and use remain subject
to the Discord Social SDK Terms accepted by the application owner. The
feature is disabled until a user explicitly links a Discord account.
