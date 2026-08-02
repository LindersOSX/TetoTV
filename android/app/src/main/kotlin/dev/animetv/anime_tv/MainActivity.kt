package dev.animetv.anime_tv

import android.annotation.SuppressLint
import android.content.ContentUris
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.edit
import androidx.core.content.FileProvider
import androidx.core.net.toUri
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import dev.animetv.anime_tv.player.Media3PlayerActivity
import java.io.File
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val channelName = "dev.tetotv/android_tv"
    private lateinit var channel: MethodChannel
    private lateinit var mediaSession: MediaSessionCompat
    private var pendingNativePlayerResult: MethodChannel.Result? = null
    private var pendingApkInstallResult: MethodChannel.Result? = null
    private var pendingApkPath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        createMediaSession()
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getDeviceProfile" -> result.success(deviceProfile())
                    "getAppVersion" -> result.success(appVersion())
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    "startNativePlayer" -> {
                        @Suppress("UNCHECKED_CAST")
                        startNativePlayer(call.arguments as? Map<String, Any?> ?: emptyMap(), result)
                    }
                    "setPreferredFrameRate" -> {
                        val fps = call.argument<Double>("fps") ?: 0.0
                        result.success(setPreferredFrameRate(fps))
                    }
                    "updateMediaSession" -> {
                        @Suppress("UNCHECKED_CAST")
                        updateMediaSession(call.arguments as? Map<String, Any?> ?: emptyMap())
                        result.success(null)
                    }
                    "publishWatchNext" -> {
                        @Suppress("UNCHECKED_CAST")
                        result.success(publishWatchNext(call.arguments as? Map<String, Any?> ?: emptyMap()))
                    }
                    "scheduleReminder" -> {
                        @Suppress("UNCHECKED_CAST")
                        result.success(scheduleReminder(call.arguments as? Map<String, Any?> ?: emptyMap()))
                    }
                    "clearPreferredFrameRate" -> {
                        window.attributes = window.attributes.apply { preferredDisplayModeId = 0 }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error("ANDROID_TV_BRIDGE", error.message, null)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun startNativePlayer(data: Map<String, Any?>, result: MethodChannel.Result) {
        if (pendingNativePlayerResult != null) {
            result.error("NATIVE_PLAYER_BUSY", "A native playback session is already active.", null)
            return
        }
        val source = data["source"] as? String
        if (source.isNullOrBlank()) {
            result.error("NATIVE_PLAYER_SOURCE", "A debrid stream URL is required.", null)
            return
        }
        val headers = HashMap<String, String>()
        (data["headers"] as? Map<*, *>)?.forEach { (key, value) ->
            if (key is String && value is String) headers[key] = value
        }
        val intent = Intent(this, Media3PlayerActivity::class.java).apply {
            putExtra(Media3PlayerActivity.EXTRA_SOURCE, source)
            putExtra(Media3PlayerActivity.EXTRA_TITLE, data["title"] as? String)
            putExtra(
                Media3PlayerActivity.EXTRA_SUBTITLE_URL,
                data["subtitleUrl"] as? String ?: data["externalSubtitle"] as? String,
            )
            putExtra(
                Media3PlayerActivity.EXTRA_SUBTITLE_MIME_TYPE,
                data["subtitleMimeType"] as? String,
            )
            putExtra(
                Media3PlayerActivity.EXTRA_SUBTITLE_LANGUAGE,
                data["subtitleLanguage"] as? String,
            )
            putExtra(Media3PlayerActivity.EXTRA_SUBTITLE_LABEL, data["subtitleLabel"] as? String)
            putExtra(Media3PlayerActivity.EXTRA_MIME_TYPE, data["mimeType"] as? String)
            putExtra(
                Media3PlayerActivity.EXTRA_FILE_NAME,
                data["fileName"] as? String ?: data["releaseName"] as? String,
            )
            putExtra(Media3PlayerActivity.EXTRA_HEADERS, headers)
            putExtra(
                Media3PlayerActivity.EXTRA_RESUME_MS,
                (data["resumeMs"] as? Number)?.toLong() ?: 0L,
            )
            putExtra(
                Media3PlayerActivity.EXTRA_RESUME_PROVIDED,
                data["resumeProvided"] as? Boolean ?: false,
            )
            putExtra(
                Media3PlayerActivity.EXTRA_RESUME_UPDATED_AT_MS,
                (data["resumeUpdatedAtMs"] as? Number)?.toLong() ?: 0L,
            )
            putExtra(Media3PlayerActivity.EXTRA_AUTO_PLAY, data["autoPlay"] as? Boolean ?: true)
            putExtra(
                Media3PlayerActivity.EXTRA_AUDIO_LANGUAGE,
                data["audioLanguage"] as? String,
            )
            putExtra(
                Media3PlayerActivity.EXTRA_SUBTITLE_LANGUAGE,
                data["subtitleLanguage"] as? String,
            )
            putExtra(
                Media3PlayerActivity.EXTRA_SUBTITLES_ENABLED,
                data["subtitlesEnabled"] as? Boolean ?: true,
            )
            putExtra(
                Media3PlayerActivity.EXTRA_SUBTITLE_SIZE,
                (data["subtitleSize"] as? Number)?.toFloat() ?: 34f,
            )
            putExtra(
                Media3PlayerActivity.EXTRA_SUBTITLE_POSITION,
                (data["subtitlePosition"] as? Number)?.toInt() ?: 100,
            )
            putExtra(
                Media3PlayerActivity.EXTRA_HIGH_CONTRAST_SUBTITLES,
                data["highContrastSubtitles"] as? Boolean ?: false,
            )
            putExtra(Media3PlayerActivity.EXTRA_VIDEO_FIT, data["videoFit"] as? String)
            putExtra(
                Media3PlayerActivity.EXTRA_START_FROM_BEGINNING,
                data["startFromBeginning"] as? Boolean ?: false,
            )
            putExtra(Media3PlayerActivity.EXTRA_CHECKPOINT_KEY, data["checkpointKey"] as? String)
        }
        pendingNativePlayerResult = result
        try {
            if (::mediaSession.isInitialized) mediaSession.isActive = false
            startActivityForResult(intent, NATIVE_PLAYER_REQUEST_CODE)
        } catch (error: Throwable) {
            if (::mediaSession.isInitialized) mediaSession.isActive = true
            pendingNativePlayerResult = null
            throw error
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == APK_INSTALL_PERMISSION_REQUEST_CODE) {
            val pending = pendingApkInstallResult
            val path = pendingApkPath
            pendingApkInstallResult = null
            pendingApkPath = null
            if (pending == null || path == null) return
            if (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                pending.error(
                    "APK_INSTALL_PERMISSION",
                    "Allow TetoTV to install unknown apps, then try again.",
                    null,
                )
                return
            }
            try {
                launchApkInstaller(File(path))
                pending.success("launched")
            } catch (error: Throwable) {
                pending.error("APK_INSTALL", error.message, null)
            }
            return
        }
        if (requestCode == NATIVE_PLAYER_REQUEST_CODE) {
            if (::mediaSession.isInitialized) mediaSession.isActive = true
            val pending = pendingNativePlayerResult
            pendingNativePlayerResult = null
            if (pending == null) return
            if (resultCode != RESULT_OK || data == null) {
                pending.success(
                    mapOf(
                        "status" to "cancelled",
                        "positionMs" to 0L,
                        "durationMs" to 0L,
                        "completed" to false,
                        "firstFrame" to false,
                        "droppedFrames" to 0,
                    ),
                )
                return
            }
            pending.success(
                mapOf(
                    Media3PlayerActivity.RESULT_STATUS to
                        data.getStringExtra(Media3PlayerActivity.RESULT_STATUS),
                    Media3PlayerActivity.RESULT_POSITION_MS to
                        data.getLongExtra(Media3PlayerActivity.RESULT_POSITION_MS, 0L),
                    Media3PlayerActivity.RESULT_DURATION_MS to
                        data.getLongExtra(Media3PlayerActivity.RESULT_DURATION_MS, 0L),
                    Media3PlayerActivity.RESULT_COMPLETED to
                        data.getBooleanExtra(Media3PlayerActivity.RESULT_COMPLETED, false),
                    Media3PlayerActivity.RESULT_ERROR to
                        data.getStringExtra(Media3PlayerActivity.RESULT_ERROR),
                    Media3PlayerActivity.RESULT_FIRST_FRAME to
                        data.getBooleanExtra(Media3PlayerActivity.RESULT_FIRST_FRAME, false),
                    "firstFrameRendered" to
                        data.getBooleanExtra(Media3PlayerActivity.RESULT_FIRST_FRAME, false),
                    Media3PlayerActivity.RESULT_DECODER to
                        data.getStringExtra(Media3PlayerActivity.RESULT_DECODER),
                    Media3PlayerActivity.RESULT_DROPPED_FRAMES to
                        data.getIntExtra(Media3PlayerActivity.RESULT_DROPPED_FRAMES, 0),
                    Media3PlayerActivity.RESULT_SUBTITLE_SIZE to
                        data.getFloatExtra(Media3PlayerActivity.RESULT_SUBTITLE_SIZE, 34f),
                    Media3PlayerActivity.RESULT_SURFACE_READY to
                        data.getBooleanExtra(Media3PlayerActivity.RESULT_SURFACE_READY, false),
                    Media3PlayerActivity.RESULT_MANUFACTURER to
                        data.getStringExtra(Media3PlayerActivity.RESULT_MANUFACTURER),
                    Media3PlayerActivity.RESULT_MODEL to
                        data.getStringExtra(Media3PlayerActivity.RESULT_MODEL),
                    Media3PlayerActivity.RESULT_SDK to
                        data.getIntExtra(Media3PlayerActivity.RESULT_SDK, 0),
                    Media3PlayerActivity.RESULT_ABIS to
                        data.getStringArrayExtra(Media3PlayerActivity.RESULT_ABIS)?.toList(),
                    Media3PlayerActivity.RESULT_MEMORY_CLASS_MB to
                        data.getIntExtra(Media3PlayerActivity.RESULT_MEMORY_CLASS_MB, 0),
                    Media3PlayerActivity.RESULT_LOW_MEMORY_DEVICE to
                        data.getBooleanExtra(
                            Media3PlayerActivity.RESULT_LOW_MEMORY_DEVICE,
                            false,
                        ),
                    Media3PlayerActivity.RESULT_VIDEO_MIME to
                        data.getStringExtra(Media3PlayerActivity.RESULT_VIDEO_MIME),
                    Media3PlayerActivity.RESULT_VIDEO_CODECS to
                        data.getStringExtra(Media3PlayerActivity.RESULT_VIDEO_CODECS),
                    Media3PlayerActivity.RESULT_VIDEO_WIDTH to
                        data.getIntExtra(Media3PlayerActivity.RESULT_VIDEO_WIDTH, 0),
                    Media3PlayerActivity.RESULT_VIDEO_HEIGHT to
                        data.getIntExtra(Media3PlayerActivity.RESULT_VIDEO_HEIGHT, 0),
                    Media3PlayerActivity.RESULT_VIDEO_FRAME_RATE to
                        data.getFloatExtra(Media3PlayerActivity.RESULT_VIDEO_FRAME_RATE, 0f),
                    Media3PlayerActivity.RESULT_AUDIO_MIME to
                        data.getStringExtra(Media3PlayerActivity.RESULT_AUDIO_MIME),
                    Media3PlayerActivity.RESULT_AUDIO_CODECS to
                        data.getStringExtra(Media3PlayerActivity.RESULT_AUDIO_CODECS),
                ),
            )
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    @Suppress("DEPRECATION")
    private fun appVersion(): Map<String, Any> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }
        return mapOf(
            "versionName" to (info.versionName ?: "unknown"),
            "versionCode" to versionCode,
        )
    }

    @Suppress("DEPRECATION")
    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (pendingApkInstallResult != null) {
            result.error("APK_INSTALL_BUSY", "An update install is already pending.", null)
            return
        }
        val file = path?.let(::File)
        if (file == null || !file.isFile || !isUpdateCacheFile(file)) {
            result.error("APK_INSTALL_FILE", "The downloaded update could not be found.", null)
            return
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            pendingApkInstallResult = result
            pendingApkPath = file.absolutePath
            try {
                startActivityForResult(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ),
                    APK_INSTALL_PERMISSION_REQUEST_CODE,
                )
            } catch (error: Throwable) {
                pendingApkInstallResult = null
                pendingApkPath = null
                result.error("APK_INSTALL_PERMISSION", error.message, null)
            }
            return
        }
        launchApkInstaller(file)
        result.success("launched")
    }

    private fun isUpdateCacheFile(file: File): Boolean {
        val updateDirectory = File(cacheDir, "updates").canonicalFile
        val candidate = file.canonicalFile
        return candidate.path.startsWith(updateDirectory.path + File.separator)
    }

    private fun launchApkInstaller(file: File) {
        val apkUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = apkUri
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            putExtra(Intent.EXTRA_RETURN_RESULT, false)
        }
        if (intent.resolveActivity(packageManager) == null) {
            throw IllegalStateException("No Android package installer is available on this TV.")
        }
        startActivity(intent)
    }

    private fun createMediaSession() {
        mediaSession = MediaSessionCompat(this, "TetoTV").apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
            )
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay() = invokePlayer("play")
                override fun onPause() = invokePlayer("pause")
                override fun onSeekTo(pos: Long) = invokePlayer("seekTo", pos)
                override fun onSkipToNext() = invokePlayer("next")
                override fun onSkipToPrevious() = invokePlayer("previous")
                override fun onFastForward() = invokePlayer("seekBy", 10000L)
                override fun onRewind() = invokePlayer("seekBy", -10000L)
            })
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                setSessionActivity(android.app.PendingIntent.getActivity(
                    this@MainActivity,
                    0,
                    launchIntent,
                    android.app.PendingIntent.FLAG_IMMUTABLE or
                        android.app.PendingIntent.FLAG_UPDATE_CURRENT,
                ))
            }
            isActive = true
        }
    }

    private fun invokePlayer(action: String, value: Long? = null) {
        runOnUiThread {
            channel.invokeMethod("mediaAction", mapOf("action" to action, "value" to value))
        }
    }

    private fun updateMediaSession(data: Map<String, Any?>) {
        val title = data["title"] as? String ?: "TetoTV"
        val subtitle = data["subtitle"] as? String ?: ""
        val duration = (data["durationMs"] as? Number)?.toLong() ?: 0L
        val position = (data["positionMs"] as? Number)?.toLong() ?: 0L
        val playing = data["playing"] as? Boolean ?: false

        mediaSession.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
                .putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, subtitle)
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration)
                .build(),
        )
        val actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_SEEK_TO or
            PlaybackStateCompat.ACTION_FAST_FORWARD or
            PlaybackStateCompat.ACTION_REWIND or
            PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
            PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
        mediaSession.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(
                    if (playing) PlaybackStateCompat.STATE_PLAYING else PlaybackStateCompat.STATE_PAUSED,
                    position,
                    if (playing) 1f else 0f,
                )
                .build(),
        )
        mediaSession.isActive = true
    }

    private fun deviceProfile(): Map<String, Any?> {
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val display = displayManager.getDisplay(android.view.Display.DEFAULT_DISPLAY)
        val modes = display?.supportedModes?.map {
            mapOf(
                "id" to it.modeId,
                "width" to it.physicalWidth,
                "height" to it.physicalHeight,
                "refreshRate" to it.refreshRate.toDouble(),
            )
        } ?: emptyList()
        val hdrTypes = display?.hdrCapabilities?.supportedHdrTypes?.toList() ?: emptyList()

        val codecs = mutableListOf<Map<String, Any?>>()
        MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos
            .filter { !it.isEncoder }
            .forEach { info ->
                info.supportedTypes
                    .filter { it.startsWith("video/") }
                    .forEach { mime ->
                        codecs.add(
                            mapOf(
                                "name" to info.name,
                                "mime" to mime.lowercase(),
                                "hardware" to isHardwareAccelerated(info),
                            ),
                        )
                    }
            }

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val audioOutputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { device ->
            mapOf(
                "type" to device.type,
                "name" to (device.productName?.toString() ?: "Audio output"),
                "channels" to device.channelCounts.toList(),
                "sampleRates" to device.sampleRates.toList(),
                "encodings" to device.encodings.toList(),
                "hdmi" to (device.type == AudioDeviceInfo.TYPE_HDMI ||
                    device.type == AudioDeviceInfo.TYPE_HDMI_ARC ||
                    (Build.VERSION.SDK_INT >= 31 && device.type == AudioDeviceInfo.TYPE_HDMI_EARC)),
            )
        }

        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "sdk" to Build.VERSION.SDK_INT,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "displayModes" to modes,
            "hdrTypes" to hdrTypes,
            "codecs" to codecs,
            "audioOutputs" to audioOutputs,
        )
    }

    private fun isHardwareAccelerated(info: MediaCodecInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return info.isHardwareAccelerated
        val name = info.name.lowercase()
        return !(name.startsWith("omx.google") || name.startsWith("c2.android") ||
            name.contains("ffmpeg") || name.contains("software"))
    }

    private fun setPreferredFrameRate(fps: Double): Int {
        if (fps <= 0.0) return 0
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            this.display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        } ?: return 0
        val current = display.mode
        val target = display.supportedModes
            .filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
            .minByOrNull { mode ->
                minOf(
                    abs(mode.refreshRate - fps),
                    abs(mode.refreshRate - fps * 2),
                )
            } ?: return 0
        window.attributes = window.attributes.apply { preferredDisplayModeId = target.modeId }
        return target.modeId
    }

    @SuppressLint("RestrictedApi")
    private fun publishWatchNext(data: Map<String, Any?>): Long? {
        val mediaId = (data["mediaId"] as? Number)?.toLong() ?: return null
        val episode = (data["episode"] as? Number)?.toInt() ?: 1
        val title = data["title"] as? String ?: return null
        val description = data["description"] as? String ?: "Continue watching on TetoTV"
        val poster = (data["posterUrl"] as? String)?.let(Uri::parse)
        val duration = (data["durationMs"] as? Number)?.toInt() ?: 0
        val position = (data["positionMs"] as? Number)?.toInt() ?: 0
        val deepLink = "tetotv:///anime/$mediaId?episode=$episode".toUri()

        val builder = WatchNextProgram.Builder()
            .setType(TvContractCompat.WatchNextPrograms.TYPE_TV_EPISODE)
            .setWatchNextType(TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE)
            .setTitle(title)
            .setEpisodeNumber(episode)
            .setDescription(description)
            .setInternalProviderId("$mediaId:$episode")
            .setIntentUri(deepLink)
            .setLastPlaybackPositionMillis(position)
            .setDurationMillis(duration)
            .setLastEngagementTimeUtcMillis(System.currentTimeMillis())
        if (poster != null) builder.setPosterArtUri(poster)

        val preferences = getSharedPreferences("watch_next", Context.MODE_PRIVATE)
        val key = "program_${mediaId}_$episode"
        val existingId = preferences.getLong(key, -1L)
        if (existingId > 0) {
            val existingUri = ContentUris.withAppendedId(
                TvContractCompat.WatchNextPrograms.CONTENT_URI,
                existingId,
            )
            if (contentResolver.update(existingUri, builder.build().toContentValues(), null, null) > 0) {
                return existingId
            }
        }
        val uri = contentResolver.insert(
            TvContractCompat.WatchNextPrograms.CONTENT_URI,
            builder.build().toContentValues(),
        ) ?: return null
        return ContentUris.parseId(uri).also { id -> preferences.edit { putLong(key, id) } }
    }

    private fun scheduleReminder(data: Map<String, Any?>): Boolean {
        val mediaId = (data["mediaId"] as? Number)?.toLong() ?: return false
        val episode = (data["episode"] as? Number)?.toInt() ?: return false
        val title = data["title"] as? String ?: return false
        val atMillis = (data["atMillis"] as? Number)?.toLong() ?: return false
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 5105)
        }
        val intent = Intent(this, AiringReminderReceiver::class.java).apply {
            putExtra("mediaId", mediaId)
            putExtra("episode", episode)
            putExtra("title", title)
        }
        val requestCode = ((mediaId * 31 + episode) and 0x7fffffff).toInt()
        val pending = PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarm = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
        return true
    }

    override fun onDestroy() {
        pendingNativePlayerResult?.error(
            "NATIVE_PLAYER_DESTROYED",
            "The Android TV activity closed before native playback returned.",
            null,
        )
        pendingNativePlayerResult = null
        pendingApkInstallResult?.error(
            "APK_INSTALL_DESTROYED",
            "The Android TV activity closed before the installer opened.",
            null,
        )
        pendingApkInstallResult = null
        pendingApkPath = null
        if (::mediaSession.isInitialized) mediaSession.release()
        super.onDestroy()
    }

    companion object {
        private const val NATIVE_PLAYER_REQUEST_CODE = 7314
        private const val APK_INSTALL_PERMISSION_REQUEST_CODE = 7315
    }
}
