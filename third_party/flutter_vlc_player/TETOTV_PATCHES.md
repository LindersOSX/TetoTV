# TetoTV flutter_vlc_player patch

This directory is based on the public `flutter_vlc_player` 7.4.4 package:

- Upstream: <https://github.com/solid-software/flutter_vlc_player>
- Upstream commit: `988a7e67140786fb5510c96e4cb415dbfd837944`
- pub.dev archive SHA-256: `32c0109cc191a97246df759a8804a1051c4ca6909597833506f13587cb3bf1be`
- License: BSD 3-Clause; see `LICENSE` in this directory.

TetoTV carries an Android surface-ownership fix in `VLCTextureView.java` and
`FlutterVlcPlayer.java`. Flutter's `TextureRegistry.SurfaceTextureEntry` is the
sole owner of the registry texture; the view no longer releases that same
`SurfaceTexture` independently. During disposal, libVLC stops and detaches its
video output and releases `MediaPlayer` before the registry entry is released,
then `LibVLC` is released last. This prevents a double-release / reversed-vout
teardown race observed as an ARMv7 Mali `pthread_mutex_lock called on a
destroyed mutex` SIGABRT while switching or exiting players.

Disposal is re-entrancy guarded and each native/resource cleanup step is
best-effort and independent. A failing `stop`, vout detach, or player release
therefore cannot skip the remaining TextureView, registry texture, and LibVLC
ownership releases, and the player is marked disposed only after every step was
attempted.

The revised path does not call `SurfaceTexture.isReleased()`, so it also stays
compatible with TetoTV's Android 7.0 minimum without API-level branching.

Keep the matching `flutter_vlc_player_platform_interface` release-tag override
in the application `pubspec.yaml`; version 7.4.4's generated Android channels
do not match the older platform-interface archive published on pub.dev.
