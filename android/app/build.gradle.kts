import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
val bundledUpdateTokenDefined = providers.gradleProperty("dart-defines")
    .orNull
    ?.split(',')
    ?.mapNotNull { encoded ->
        runCatching {
            String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
        }.getOrNull()
    }
    ?.any { define ->
        define.startsWith("TETOTV_GITHUB_UPDATE_TOKEN=") &&
            define.substringAfter('=').isNotBlank()
    } == true
if (releaseTaskRequested && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "Release signing is not configured. Restore android/key.properties " +
            "and the original keystore before building an update.",
    )
}
if (releaseTaskRequested && !bundledUpdateTokenDefined) {
    throw GradleException(
        "Release updater access is not provisioned. Build with a non-empty " +
            "--dart-define=TETOTV_GITHUB_UPDATE_TOKEN=<read-only token>.",
    )
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.animetv.anime_tv"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Use a unique reverse-domain application ID before store publishing.
        applicationId = "dev.animetv.anime_tv"
        // Flutter currently requires API 24. This supports Fire OS 6+
        // (API 25+) but cannot be installed on Fire OS 5 (API 22).
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    // media_kit loads libmpv through Dart FFI and explicitly requests extracted
    // native libraries. Honor that request for older Fire OS/Android TV loaders
    // instead of silently overriding it with AGP's modern in-APK default.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    lint {
        // Flutter owns and regenerates the ignored local.properties file. Its
        // Windows path escaping is valid for Gradle but trips this lint check.
        disable += "PropertyEscape"
    }
}

val media3Version = "1.11.0"

dependencies {
    implementation("androidx.media:media:1.8.0")
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")
    implementation("androidx.media3:media3-datasource-okhttp:$media3Version")
    implementation("androidx.media3:media3-session:$media3Version")
    implementation("androidx.profileinstaller:profileinstaller:1.4.1")
    implementation("androidx.tvprovider:tvprovider:1.1.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
