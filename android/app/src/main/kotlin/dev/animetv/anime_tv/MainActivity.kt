package dev.animetv.anime_tv

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
import android.view.WindowManager
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val channelName = "dev.tetotv/android_tv"
    private lateinit var channel: MethodChannel
    private lateinit var mediaSession: MediaSessionCompat

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
        val hdrTypes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            display?.hdrCapabilities?.supportedHdrTypes?.toList() ?: emptyList()
        } else {
            emptyList()
        }

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
        val audioOutputs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { device ->
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
        } else {
            emptyList()
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

    private fun publishWatchNext(data: Map<String, Any?>): Long? {
        val mediaId = (data["mediaId"] as? Number)?.toLong() ?: return null
        val episode = (data["episode"] as? Number)?.toInt() ?: 1
        val title = data["title"] as? String ?: return null
        val description = data["description"] as? String ?: "Continue watching on TetoTV"
        val poster = (data["posterUrl"] as? String)?.let(Uri::parse)
        val duration = (data["durationMs"] as? Number)?.toInt() ?: 0
        val position = (data["positionMs"] as? Number)?.toInt() ?: 0
        val deepLink = Uri.parse("tetotv:///anime/$mediaId?episode=$episode")

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
        return ContentUris.parseId(uri).also { id -> preferences.edit().putLong(key, id).apply() }
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
        if (::mediaSession.isInitialized) mediaSession.release()
        super.onDestroy()
    }
}
