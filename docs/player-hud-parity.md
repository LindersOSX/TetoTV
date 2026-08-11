# Player HUD parity

TetoTV has two HUD implementations because MPV and VLC render inside Flutter,
while Media3 owns a native Android `SurfaceView`. The implementations follow the
same user-facing contract even though their playback APIs are different.

| Contract | MPV | VLC | Media3 |
| --- | --- | --- | --- |
| Card, title, engine/source badges | Shared `TetoPlayerChrome` | Shared `TetoPlayerChrome` | Native equivalent with the same spacing, colors, and responsive width cap |
| Control order | Back, Play/Pause, Forward, Audio, CC, Size, Picture, Player, Sources when applicable, Options | Same | Same; Sources is omitted because Media3 is only used for native/debrid playback |
| Action-to-progress spacing | 18 dp (15 dp compact) | 18 dp (15 dp compact) | Visual bar is 18 dp below controls inside an accessible 32 dp touch target |
| Progress and elapsed/duration | Accent progress, elapsed/duration footer | Same | Same |
| Auto-hide | 5 seconds in playing and paused states | Same | Same |
| Early dismissal | D-pad Down or tap | Same | Same |
| Reveal/focus | First directional press reveals HUD and focuses Play | Same | Same |
| Keyboard/gamepad shortcuts | J/L seek, K play/pause, S captions, Menu/M/Y options | Same | Same |
| Audio and CC unavailable state | Picker explains when tracks are unavailable | Same | Controls are visibly dimmed and disabled until supported tracks exist |
| Icons and TV focus | App-owned rounded Material icons; 3 dp Teto-red ring/glow with dark inner keyline | Same | App-owned vector equivalents and Fire TV-safe red glow/ring/dark keyline selector |
| Skip segment | Separate translucent overlay | Same | Separate native translucent overlay |

Engine-specific playback capabilities stay honest rather than exposing buttons
that cannot work:

- Web source switching is available only for MPV/VLC web streams. Native Media3
  is deliberately limited to direct/debrid media.
- MPV can create seek-preview screenshots; VLC and Media3 surfaces cannot always
  expose decoded frames safely.
- Track pickers are engine-native, but use the same Audio/CC entry points and
  restore focus to the originating control.
