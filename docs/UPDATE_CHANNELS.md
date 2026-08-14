# TetoTV update channels

TetoTV defaults every fresh installation to the **Public** update channel.
Developer mode is unlocked by activating **Settings > System** ten times. Its
Public/Beta choice is stored locally in encrypted preferences and can be
changed later. Public updates remain credential-free; private Beta access
uses a shared revocable credential injected into both signed builds at compile
time. There is no key-entry screen and no raw key is stored in app preferences.
Because a shared key can be extracted from a public APK, it is a broker abuse
control rather than a confidentiality or authorization boundary.

## Public releases

Public metadata and APK downloads come anonymously from the dedicated public,
releases-only repository:

```text
LindersOSX/TetoTV-Releases
```

Public started at completed release `v1.0.0`; the current hotfix is `v1.0.1`.
Attach the signed universal APK and keep the application ID and Android signing
certificate identical to the Beta build so Android accepts an in-place update.
The paired Public `1.0.1` and Beta `2.0.1` APKs use the same Android
`versionCode` (`410001`). Releases offered for in-app rollback must keep the
same package ID, production signer, compatible SDK/ABIs, and Android
`versionCode`; Android will not normally install a lower code. A future build
that raises the code creates a one-way boundary: versions below that code stay
visible but cannot be reinstalled over it. The repository should contain
release artifacts and user-facing release information only; private source,
secrets, workflows that expose private infrastructure, and Beta artifacts do
not belong there.

The client sends no `Authorization` header to this repository. GitHub's release
asset `digest` is verified when present, and Android package compatibility is
checked before the installer opens.

Public versioning intentionally restarted below the earlier private 1.11.x
line. An installed pre-Public 1.x build with an Android `versionCode` below
`410001` is therefore offered the Public release even though `1.0.0` is lower
under SemVer. The exception requires the numeric installed build code and ends
at `410001`, so a completed Public install cannot repeatedly offer the same
release. The legacy APK itself cannot receive this client-side rule; its
anonymous broker compatibility route must remain available until supported
legacy installations have migrated.

## Beta releases

Beta metadata and APK bytes continue to use the update broker and the private
source repository:

```text
GITHUB_RELEASE_REPOSITORY=LindersOSX/TetoTV
GITHUB_RELEASE_TOKEN=<fine-grained Contents: Read-only token>
BETA_ACCESS_KEY_SHA256_HASHES=<comma-separated lowercase SHA-256 hashes>
```

Generate one long opaque build credential outside source control and put only
its lowercase SHA-256 hash in the broker environment. Supply the raw value to
both signed builds with a protected `--dart-define-from-file` JSON file whose
property is `TETOTV_BETA_UPDATE_ACCESS_KEY`. Never place the raw value directly
in a command, workflow log, repository file, release note, diagnostic, or URL.
The broker never needs the raw key at rest. Rotate the credential and broker
hash together if it is abused; older builds will then fail closed for Beta.

Beta started at `v2.0.0`; the current paired hotfix is tagged `v2.0.1` and its
user-facing release name is **TetoTV 2.0.1 Beta**. Keep machine-readable tags
strictly numeric (`v2.0.1`); the app adds the `Beta` channel label in its UI.
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
GET /v1/app-updates/releases
GET /v1/app-updates/releases/vX.Y.Z/assets/ASSET_ID/universal.apk
HEAD /v1/app-updates/releases/vX.Y.Z/assets/ASSET_ID/universal.apk
```

Every private Beta metadata, history, HEAD, and APK request requires
`Authorization: Beta <opaque build credential>`. Missing or invalid credentials
are rejected and separately rate-limited. Redirects from the app to the broker
are not accepted. The GitHub token remains server-side and is never embedded.
The app never displays or persistently stores the build credential and sends it
only to `https://tetotv-updates-lindows.onrender.com`. `/health` exposes only
`beta_updates_configured: true|false`; it never returns a key or hash.

The authenticated history response is bounded to 20 completed, normal Beta 2.x
releases, newest first:

```json
{"releases":[{"version":"2.0.1","tag_name":"v2.0.1","asset":{"download_url":"https://tetotv-updates-lindows.onrender.com/v1/app-updates/releases/v2.0.1/assets/123/universal.apk"}}]}
```

Each item uses the same sanitized metadata schema as `latest`. Public history
comes anonymously from the public repository and is restricted to completed
Public 1.x releases. The Developer UI submits only a release returned by the
current history list, then verifies size, digest when supplied, package ID,
signer, Android build code, SDK, ABI, and version name before opening Android's
installer.

## Publishing checks

Before publishing either channel:

1. Build one universal APK containing the supported ARM ABIs.
2. Sign it with the same protected production signing key used by prior builds.
3. Use Android `versionCode` `410001` for both Public and Beta releases that
   must remain mutually rollback-compatible. Raise it only when intentionally
   creating a one-way update boundary.
4. Use a completed `vX.Y.Z` release, never a draft.
5. Install over the preceding build on at least one TV-class device and one
   handheld Android device.

TetoTV's updater recognizes Public 1.x and Beta 2.x as separate release
families, so changing the selected channel can install the counterpart even
when its user-facing SemVer is lower. Native APK inspection must allow an equal
`versionCode` only when the package/signing certificate match and the target
`versionName` differs. It must continue rejecting lower codes, signature or
package mismatches, and an identical installed version.
