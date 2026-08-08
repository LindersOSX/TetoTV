# Build and sideload on Windows

These commands assume PowerShell.

## 1. Install the host tools

Install Git and Android Studio:

```powershell
winget install --exact --id Git.Git
winget install --exact --id Google.AndroidStudio
```

Open Android Studio once. In **More Actions > SDK Manager**, install:

- the current stable Android SDK Platform;
- Android SDK Build-Tools;
- Android SDK Platform-Tools;
- Android SDK Command-line Tools (latest);
- Android Emulator.

In **Device Manager**, install a current Android TV or Google TV system image
and create a 1080p TV virtual device.

Install Flutter stable into a user-owned tools directory:

```powershell
$flutterRoot = "$env:LOCALAPPDATA\Programs\flutter"
git clone --branch stable https://github.com/flutter/flutter.git $flutterRoot
$env:Path += ";$flutterRoot\bin"
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";$flutterRoot\bin",
  "User"
)
```

Point Flutter at the standard Android SDK location, accept the licenses, and
verify everything:

```powershell
flutter config --android-sdk "$env:LOCALAPPDATA\Android\Sdk"
flutter doctor --android-licenses
flutter doctor -v
```

Every Android item in `flutter doctor` should be green before continuing.

## 2. Initialize this project from scratch

This repository is already initialized. These are the exact commands that
created its base project and dependencies:

```powershell
New-Item -ItemType Directory -Path "C:\dev\anime_tv"
Set-Location "C:\dev\anime_tv"

flutter create `
  --platforms=android `
  --org=dev.animetv `
  --project-name=anime_tv `
  .

flutter pub add `
  flutter_vlc_player `
  media_kit `
  media_kit_video `
  media_kit_libs_android_video `
  flutter_riverpod `
  go_router `
  dio `
  flutter_secure_storage `
  qr_flutter `
  cached_network_image
```

`dev.animetv.anime_tv` is a placeholder application ID. Change it, its Kotlin
package/directory, and the `namespace` before publishing.

The checked-in TV manifest already declares:

```xml
<uses-feature
    android:name="android.software.leanback"
    android:required="false" />
<uses-feature
    android:name="android.hardware.touchscreen"
    android:required="false" />
```

Its main activity includes:

```xml
<category android:name="android.intent.category.LAUNCHER" />
<category android:name="android.intent.category.LEANBACK_LAUNCHER" />
```

It also supplies `android:banner`, Internet permission, landscape orientation,
and no fake-touch requirement.

## 3. Analyze and test

From the repository root:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

## 4. Run on an Android TV emulator

The command-line equivalent of Android Studio's Device Manager is:

```powershell
$sdk = "$env:LOCALAPPDATA\Android\Sdk"

& "$sdk\cmdline-tools\latest\bin\sdkmanager.bat" `
  "platform-tools" `
  "emulator" `
  "system-images;android-36;google-tv;x86_64"

"no" | & "$sdk\cmdline-tools\latest\bin\avdmanager.bat" create avd `
  --name TetoTV_API36 `
  --package "system-images;android-36;google-tv;x86_64" `
  --device "tv_1080p"

& "$sdk\emulator\emulator.exe" -avd TetoTV_API36
```

The emulator command opens a visible, interactive Google TV window. Start the
TV AVD there or in Android Studio, then:

```powershell
flutter devices
flutter run -d <device-id>
```

Use keyboard arrows as the D-pad, Enter as the center button, and Escape as
Back. The home screen should show a bright focus outline and scale effect.

## 5. Build the first sideloadable APK

Build a debug APK:

```powershell
flutter build apk --debug
```

Output:

```text
build\app\outputs\flutter-apk\app-debug.apk
```

Install it on the running emulator or connected TV:

```powershell
adb install -r .\build\app\outputs\flutter-apk\app-debug.apk
```

Launch it explicitly if needed:

```powershell
adb shell am start -n dev.animetv.anime_tv/.MainActivity
```

For an Nvidia Shield or Google TV device, enable Developer Options and network
debugging. On devices that expose wireless pairing:

```powershell
adb pair <tv-ip>:<pairing-port>
adb connect <tv-ip>:<debug-port>
adb devices
adb install -r .\build\app\outputs\flutter-apk\app-debug.apk
```

## 6. Release-sized APKs

Create a private upload key outside the repository:

```powershell
keytool -genkeypair -v `
  -keystore "C:\secure\anime-tv-upload.jks" `
  -alias upload `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000
```

Copy `android\key.properties.example` to `android\key.properties`, replace all
values, and keep the real properties and keystore outside source control. Back
up both files securely before installing the first distributed build. The
release task intentionally fails without them, and Android cannot update an
installed app signed by a different key. Then build one APK per ABI:

```powershell
flutter build apk --release --split-per-abi
```

Many Fire TV models expose a 32-bit application ABI even when their CPU is
64-bit. Check the target before choosing a split APK:

```powershell
adb shell getprop ro.product.cpu.abilist
adb shell getprop ro.build.version.sdk
```

Use `app-armeabi-v7a-release.apk` when the ABI list contains only
`armeabi-v7a`, `app-arm64-v8a-release.apk` for `arm64-v8a`, and the x86_64 APK
only for an emulator. A universal `flutter build apk --release` build avoids
ABI selection errors. Do not alternate between split and universal APKs under
the same low version code: Flutter adds ABI-specific offsets to split version
codes, so Android can reject a later universal build as a downgrade.

The current Flutter toolchain has a minimum SDK of API 24. It supports Fire OS
6 and newer, but not Fire OS 5 devices (API 22).
