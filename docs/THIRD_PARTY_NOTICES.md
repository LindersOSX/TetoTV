# Third-party playback and networking notices

TetoTV's default Android player and its independent compatibility engines use
the following third-party components:

| Component | Use in TetoTV | Upstream license |
| --- | --- | --- |
| AndroidX Media3 1.10.1 (`media3-exoplayer`, `media3-ui`, `media3-session`, and `media3-datasource-okhttp`) | Native default player, `PlayerView`/`SurfaceView`, MediaSession, and OkHttp-backed media data source | Apache License 2.0 |
| OkHttp | HTTPS redirects, byte-range requests, retries, and debrid request headers for Media3 | Apache License 2.0 |
| `media_kit`, `media_kit_video`, and `media_kit_libs_android_video` | MPV compatibility player and Flutter integration | MIT License for the media_kit projects; bundled native components retain their own licenses |
| mpv, FFmpeg, and libass | Compatibility decoding and styled ASS subtitle rendering inside the media_kit Android runtime | Their respective upstream licenses apply; FFmpeg/mpv obligations depend on the exact binary build configuration |
| `flutter_vlc_player` 7.4.4 | Flutter integration for the final VLC fallback | BSD 3-Clause License |
| VideoLAN libVLC 3.6.3 | Final software compatibility player | GNU Lesser General Public License 2.1 or later, subject to the licenses of included modules |

Upstream projects and license sources:

- AndroidX Media3: <https://github.com/androidx/media>
- OkHttp: <https://github.com/square/okhttp>
- media_kit and its Android native-library package:
  <https://github.com/media-kit/media-kit>
- mpv: <https://github.com/mpv-player/mpv>
- FFmpeg: <https://ffmpeg.org/legal.html>
- libass: <https://github.com/libass/libass>
- flutter_vlc_player:
  <https://github.com/solid-software/flutter_vlc_player>
- VLC for Android/libVLC:
  <https://code.videolan.org/videolan/vlc-android>

The exact resolved Dart package versions are recorded in `pubspec.lock`.
Native Android versions are declared in `android/app/build.gradle.kts`, plugin
Gradle metadata, and the resolved Gradle dependency graph. Copyright notices
and complete license texts shipped by those dependencies remain applicable.
When redistributing an APK, retain those notices and comply with the source,
relinking, attribution, and other requirements that apply to the exact native
binaries in that build. This summary is not a replacement for the full license
texts.

## Kasane Teto name and artwork

TetoTV is an independent, unofficial application and is not endorsed by the
Kasane Teto rights holders. The launcher artwork, character name, and related
branding must be used in accordance with the official Kasane Teto character
guidelines: <https://kasaneteto.jp/guidelines/>.

Required character attribution retained by the app:

```text
重音テト © 線 / 小山乃舞世 / TWINDRILL
```

Those guidelines and any separate commercial-use permissions apply in
addition to the software licenses above. A distributor is responsible for
confirming that its particular release, artwork, territory, and monetization
model are permitted.
