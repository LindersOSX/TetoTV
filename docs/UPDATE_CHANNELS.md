# TetoTV update channels

TetoTV defaults every fresh installation to the **Public** update channel.
Developer mode is unlocked by activating **Settings > System** ten times. Its
Public/Beta choice is stored locally in encrypted preferences and can be
changed later. Public updates remain credential-free; private Beta access
requires a separately issued tester key.

## Public releases

Public metadata and APK downloads come anonymously from the dedicated public,
releases-only repository:

```text
LindersOSX/TetoTV-Releases
```

Create the first completed (not draft or prerelease) release as `v1.0.0` and
attach the signed universal APK. Keep the application ID and Android signing
certificate identical to the Beta build so Android accepts an in-place update.
The paired Public `1.0.0` and Beta `2.0.0` APKs use the same Android
`versionCode` (`410001`). Every later Public tag and later release-pair
`versionCode` must increase monotonically. The repository should contain release
artifacts and user-facing release information only; private source, secrets,
workflows that expose private infrastructure, and Beta artifacts do not belong
there.

The client sends no `Authorization` header to this repository. GitHub's release
asset `digest` is verified when present, and Android package compatibility is
checked before the installer opens.

## Beta releases

Beta metadata and APK bytes continue to use the update broker and the private
source repository:

```text
GITHUB_RELEASE_REPOSITORY=LindersOSX/TetoTV
GITHUB_RELEASE_TOKEN=<fine-grained Contents: Read-only token>
BETA_ACCESS_KEY_SHA256_HASHES=<comma-separated lowercase SHA-256 hashes>
```

Generate a long opaque key for each authorized tester, give the raw key to that
tester through a private channel, and put only its lowercase SHA-256 hash in the
broker environment. Multiple hashes allow individual rotation/revocation. The
broker never needs the raw key at rest.

The first private Beta release from this codebase is tagged `v2.0.0` and its
user-facing release name is **TetoTV 2.0.0 Beta**. Keep the machine-readable tag
strictly numeric (`v2.0.0`); the app adds the `Beta` channel label in its UI.
Future private Beta versions continue on the 2.x series.

Switching channels is deliberately bidirectional. When the installed app is in
the 2.x Beta family, selecting Public treats the completed 1.x release as an
install candidate even though its SemVer is lower. Likewise, a 1.x Public build
can switch to a completed 2.x Beta release. Once the installed major family
matches the selected channel, ordinary version comparison resumes; automatic
checks therefore do not repeatedly offer the same release.

The Beta channel uses the existing endpoints:

```text
GET /v1/app-updates/latest
GET /v1/app-updates/releases/vX.Y.Z/assets/ASSET_ID/universal.apk
HEAD /v1/app-updates/releases/vX.Y.Z/assets/ASSET_ID/universal.apk
```

Every metadata, HEAD, and APK request requires
`Authorization: Beta <opaque tester key>`. Missing or invalid credentials are
rejected and separately rate-limited. Redirects from the app to the broker are
not accepted. The GitHub token remains server-side and is never the tester key.
Do not place either credential in the public release repository, APK, release
notes, logs, diagnostics, or an asset URL.

The app stores a tester-entered raw key only in Android Keystore-backed Flutter
secure storage. It never displays the saved value and sends it only to the
fixed `https://tetotv-updates-lindows.onrender.com` broker origin. Clearing the
key immediately returns the update channel to Public. `/health` exposes only
`beta_updates_configured: true|false`; it never returns a key or hash.

## Publishing checks

Before publishing either channel:

1. Build one universal APK containing the supported ARM ABIs.
2. Sign it with the same protected production signing key used by prior builds.
3. For the initial paired builds, use Android `versionCode` `410001` for both
   Public `1.0.0` and Beta `2.0.0`. Future paired builds must use a code greater
   than every previously distributed pair.
4. Use a completed `vX.Y.Z` release, never a draft.
5. Install over the preceding build on at least one TV-class device and one
   handheld Android device.

TetoTV's updater recognizes Public 1.x and Beta 2.x as separate release
families, so changing the selected channel can install the counterpart even
when its user-facing SemVer is lower. Native APK inspection must allow an equal
`versionCode` only when the package/signing certificate match and the target
`versionName` differs. It must continue rejecting lower codes, signature or
package mismatches, and an identical installed version.
