# TetoTV flutter_vlc_player patch

This directory is based on the public `flutter_vlc_player` 7.4.4 package:

- Upstream: <https://github.com/solid-software/flutter_vlc_player>
- Upstream commit: `988a7e67140786fb5510c96e4cb415dbfd837944`
- pub.dev archive SHA-256: `32c0109cc191a97246df759a8804a1051c4ca6909597833506f13587cb3bf1be`
- License: BSD 3-Clause; see `LICENSE` in this directory.

TetoTV carries one Android compatibility delta in `VLCTextureView.java`:
calls to `SurfaceTexture.isReleased()`, an API added in Android 8.0 (API 26),
are routed through an SDK-gated helper. Android 7.0/7.1 therefore preserve the
existing release behavior without resolving an unavailable framework method.

Keep the matching `flutter_vlc_player_platform_interface` release-tag override
in the application `pubspec.yaml`; version 7.4.4's generated Android channels
do not match the older platform-interface archive published on pub.dev.
