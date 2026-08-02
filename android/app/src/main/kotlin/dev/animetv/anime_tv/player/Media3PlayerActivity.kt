package dev.animetv.anime_tv.player

import android.app.ActivityManager
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.TypedValue
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.annotation.OptIn
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.session.MediaSession
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import java.util.concurrent.TimeUnit
import kotlin.math.max
import okhttp3.OkHttpClient

/**
 * Full-screen native Android playback isolated from Flutter's texture pipeline.
 *
 * [PlayerView] creates a real [SurfaceView] by default. Keeping this in a
 * separate Activity avoids Flutter TextureRegistry, virtual-display, and
 * platform-view composition paths that corrupt frames on some Fire TV devices.
 */
@OptIn(UnstableApi::class)
class Media3PlayerActivity : ComponentActivity(), Player.Listener, AnalyticsListener {
    private lateinit var player: ExoPlayer
    private lateinit var playerView: PlayerView
    private lateinit var mediaSession: MediaSession
    private val handler = Handler(Looper.getMainLooper())

    private var source = ""
    private var checkpointKey = ""
    private var firstFrameRendered = false
    private var everFirstFrameRendered = false
    private var surfaceReady = false
    private var decoderName: String? = null
    private var droppedFrames = 0
    private var terminalError: String? = null
    private var resultSent = false
    private var resumeProvided = false
    private var requestedResumeMs = 0L
    private var requestedResumeUpdatedAtMs = 0L
    private var resumeAfterTransientPause = false
    private var isForeground = false
    private var preferredAudioLanguage = "eng"
    private var preferredAudioOverrideApplied = false
    private var backgroundStopped = false
    private var backgroundResumeMs = 0L
    private var dropWindowElapsedMs = 0L
    private var dropWindowFrames = 0
    private var consecutiveChoppyWindows = 0

    private val checkpointPreferences by lazy {
        getSharedPreferences(CHECKPOINT_PREFERENCES, MODE_PRIVATE)
    }

    private val checkpointRunnable = object : Runnable {
        override fun run() {
            persistCheckpoint()
            if (!isFinishing && !isDestroyed && isForeground) {
                handler.postDelayed(this, CHECKPOINT_INTERVAL_MS)
            }
        }
    }

    private val firstFrameWatchdog = Runnable {
        if (
            resultSent || !isForeground || firstFrameRendered || !hasSelectedVideoTrack()
        ) return@Runnable
        val position = safePositionMs()
        terminalError =
            "Media3 reached a playable state but the SurfaceView received no video frame " +
                "(position=${position}ms, decoder=${decoderName ?: "unknown"}, " +
                "surfaceReady=$surfaceReady)."
        finishWithResult(STATUS_ERROR)
    }

    private val startupWatchdog = Runnable {
        if (resultSent || !isForeground || firstFrameRendered) return@Runnable
        terminalError = if (hasSelectedVideoTrack()) {
            "Media3 did not render a video frame within ${STARTUP_TIMEOUT_MS / 1_000}s " +
                "(state=${player.playbackState}, decoder=${decoderName ?: "unknown"})."
        } else {
            "Media3 did not discover a playable video track within " +
                "${STARTUP_TIMEOUT_MS / 1_000}s."
        }
        finishWithResult(STATUS_ERROR)
    }

    private val surfaceCallback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            surfaceReady = true
            if (
                isForeground &&
                ::player.isInitialized &&
                player.playbackState == Player.STATE_READY &&
                !firstFrameRendered
            ) {
                handler.removeCallbacks(firstFrameWatchdog)
                handler.postDelayed(firstFrameWatchdog, FIRST_FRAME_TIMEOUT_MS)
            }
        }

        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            surfaceReady = width > 0 && height > 0
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
            surfaceReady = false
            firstFrameRendered = false
            resetDropWindow()
            handler.removeCallbacks(firstFrameWatchdog)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() = finishWithResult(STATUS_STOPPED)
            },
        )
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        enterImmersiveMode()

        source = normalizeMediaUri(intent.getStringExtra(EXTRA_SOURCE).orEmpty())
        checkpointKey = intent.getStringExtra(EXTRA_CHECKPOINT_KEY).orEmpty()
        resumeProvided = intent.getBooleanExtra(EXTRA_RESUME_PROVIDED, false)
        requestedResumeMs = intent.getLongExtra(EXTRA_RESUME_MS, 0L).coerceAtLeast(0L)
        requestedResumeUpdatedAtMs =
            intent.getLongExtra(EXTRA_RESUME_UPDATED_AT_MS, 0L).coerceAtLeast(0L)
        if (source.isBlank() || (!source.startsWith("https://") && source != SMOKE_VIDEO_URI)) {
            terminalError = "The native player requires an HTTPS debrid URL."
            finishWithResult(STATUS_ERROR)
            return
        }

        preferredAudioLanguage = intent.getStringExtra(EXTRA_AUDIO_LANGUAGE) ?: "eng"
        val audioLanguages = preferredLanguageTags(preferredAudioLanguage)
        val audioLabels = preferredAudioLabels(
            preferredAudioLanguage,
        )
        val subtitleLanguages = preferredLanguageTags(
            intent.getStringExtra(EXTRA_SUBTITLE_LANGUAGE) ?: "eng",
        )
        val subtitlesEnabled = intent.getBooleanExtra(EXTRA_SUBTITLES_ENABLED, true)
        val trackSelector = DefaultTrackSelector(this).apply {
            parameters = buildUponParameters()
                .setPreferredAudioLanguages(*audioLanguages.toTypedArray())
                .setPreferredAudioLabels(*audioLabels.toTypedArray())
                .setPreferredTextLanguages(*subtitleLanguages.toTypedArray())
                .setSelectUndeterminedTextLanguage(false)
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, !subtitlesEnabled)
                .build()
        }
        val renderersFactory = DefaultRenderersFactory(this)
            .setEnableDecoderFallback(true)

        // Size the progressive buffer for the device instead of assuming a
        // particular Fire TV, Shield, Chromecast, or generic Android TV box.
        val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        val lowMemoryDevice = activityManager.isLowRamDevice
        val memoryClassMb = activityManager.memoryClass
        val minimumBufferMs = if (lowMemoryDevice) 8_000 else 12_000
        val maximumBufferMs = when {
            lowMemoryDevice -> 25_000
            memoryClassMb <= 256 -> 35_000
            else -> 45_000
        }
        // Keep the allocator below roughly one quarter of the app heap. The
        // Flutter engine remains alive behind this Activity, so allowing a 4K
        // remux to ignore the byte limit can otherwise force low-memory TV
        // boxes into GC thrashing or an OOM.
        val targetBufferBytes =
            (memoryClassMb / 4).coerceIn(16, 96) * 1024 * 1024
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                minimumBufferMs,
                maximumBufferMs,
                1_500,
                3_000,
            )
            .setTargetBufferBytes(targetBufferBytes)
            .setPrioritizeTimeOverSizeThresholds(false)
            .setBackBuffer(5_000, false)
            .build()

        val httpClient = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .retryOnConnectionFailure(true)
            .build()
        val requestHeaders = linkedMapOf(
            "Accept" to "*/*",
            "User-Agent" to "TetoTV/1.7 AndroidTV Media3",
        ).apply { putAll(intentHeaders()) }
        val httpFactory = OkHttpDataSource.Factory(httpClient)
            .setUserAgent(requestHeaders.getValue("User-Agent"))
            .setDefaultRequestProperties(requestHeaders)
        val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)

        player = ExoPlayer.Builder(this, renderersFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .setSeekBackIncrementMs(10_000)
            .setSeekForwardIncrementMs(10_000)
            .build()
            .also {
                it.addListener(this)
                it.addAnalyticsListener(this)
                it.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                        .setUsage(C.USAGE_MEDIA)
                        .build(),
                    true,
                )
                it.setHandleAudioBecomingNoisy(true)
                // Ask Android to match 23.976/24/25/50/60 fps only when the
                // display can do so without a disruptive mode switch. This
                // reduces judder on capable TVs while remaining safe on boxes
                // that expose only a fixed 60 Hz output mode.
                it.videoChangeFrameRateStrategy =
                    C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS
            }

        playerView = PlayerView(this).apply {
            setBackgroundColor(Color.BLACK)
            setShutterBackgroundColor(Color.BLACK)
            useController = true
            controllerAutoShow = true
            controllerHideOnTouch = true
            controllerShowTimeoutMs = 5_000
            setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING)
            setKeepContentOnPlayerReset(false)
            resizeMode = when (intent.getStringExtra(EXTRA_VIDEO_FIT)) {
                "cover" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
            }
            subtitleView?.apply {
                val highContrast =
                    intent.getBooleanExtra(EXTRA_HIGH_CONTRAST_SUBTITLES, false)
                val subtitleSize =
                    intent.getFloatExtra(EXTRA_SUBTITLE_SIZE, 34f).coerceIn(18f, 60f)
                setApplyEmbeddedStyles(!highContrast)
                setApplyEmbeddedFontSizes(!highContrast && subtitleSize == 34f)
                setFixedTextSize(
                    TypedValue.COMPLEX_UNIT_SP,
                    subtitleSize,
                )
                val subtitlePosition =
                    intent.getIntExtra(EXTRA_SUBTITLE_POSITION, 100).coerceIn(60, 100)
                setBottomPaddingFraction((108 - subtitlePosition) / 100f)
                if (highContrast) {
                    setStyle(
                        CaptionStyleCompat(
                            Color.WHITE,
                            0x99000000.toInt(),
                            Color.TRANSPARENT,
                            CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                            Color.BLACK,
                            null,
                        ),
                    )
                }
            }
            player = this@Media3PlayerActivity.player
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        val videoSurface = playerView.videoSurfaceView
        if (videoSurface !is SurfaceView) {
            terminalError =
                "Media3 did not create the required direct SurfaceView " +
                    "(${videoSurface?.javaClass?.name ?: "none"})."
            finishWithResult(STATUS_ERROR)
            return
        }
        videoSurface.holder.addCallback(surfaceCallback)
        setContentView(playerView)
        mediaSession = MediaSession.Builder(this, player)
            // Media3 requires IDs to remain unique until the prior Activity's
            // asynchronous destruction has released its session. This matters
            // for auto-next and immediate retry/fallback launches.
            .setId("TetoTVNativePlayer-${SystemClock.elapsedRealtimeNanos()}")
            .build()

        val startFromBeginning = intent.getBooleanExtra(EXTRA_START_FROM_BEGINNING, false)
        val nativeCheckpointMs = if (checkpointKey.isBlank()) {
            0L
        } else {
            checkpointPreferences.getLong(positionKey(), 0L)
        }
        val nativeCheckpointUpdatedAtMs = if (checkpointKey.isBlank()) {
            0L
        } else {
            checkpointPreferences.getLong(updatedKey(), 0L)
        }
        val nativeCheckpointCompleted = checkpointKey.isNotBlank() &&
            checkpointPreferences.getBoolean(completedKey(), false)
        if (startFromBeginning && checkpointKey.isNotBlank()) clearNativeCheckpoint()
        val startPositionMs = when {
            startFromBeginning -> 0L
            nativeCheckpointCompleted -> {
                if (
                    resumeProvided &&
                    (nativeCheckpointUpdatedAtMs == 0L ||
                        requestedResumeUpdatedAtMs >= nativeCheckpointUpdatedAtMs)
                ) requestedResumeMs else 0L
            }
            resumeProvided && requestedResumeUpdatedAtMs >= nativeCheckpointUpdatedAtMs ->
                requestedResumeMs
            nativeCheckpointUpdatedAtMs > 0L -> nativeCheckpointMs
            resumeProvided -> requestedResumeMs
            else -> 0L
        }.coerceAtLeast(0L)
        player.setMediaItem(buildMediaItem(), startPositionMs)
        player.prepare()
        player.playWhenReady = intent.getBooleanExtra(EXTRA_AUTO_PLAY, true)
        playerView.showController()
        playerView.requestFocus()
    }

    private fun buildMediaItem(): MediaItem {
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty().ifBlank { "TetoTV" }
        val builder = MediaItem.Builder()
            .setUri(Uri.parse(source))
            .setMediaMetadata(MediaMetadata.Builder().setTitle(title).build())

        inferContainerMimeType(
            intent.getStringExtra(EXTRA_MIME_TYPE),
            intent.getStringExtra(EXTRA_FILE_NAME),
            source,
        )?.let(builder::setMimeType)

        val subtitleUrl = intent.getStringExtra(EXTRA_SUBTITLE_URL)?.let(::normalizeMediaUri)
        if (!subtitleUrl.isNullOrBlank()) {
            val subtitleMime = inferSubtitleMimeType(
                intent.getStringExtra(EXTRA_SUBTITLE_MIME_TYPE),
                subtitleUrl,
            )
            val subtitle = MediaItem.SubtitleConfiguration.Builder(Uri.parse(subtitleUrl))
                .setMimeType(subtitleMime)
                .setLanguage(intent.getStringExtra(EXTRA_SUBTITLE_LANGUAGE) ?: "en")
                .setLabel(intent.getStringExtra(EXTRA_SUBTITLE_LABEL) ?: "Subtitles")
                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                .build()
            builder.setSubtitleConfigurations(listOf(subtitle))
        }
        return builder.build()
    }

    private fun intentHeaders(): Map<String, String> {
        @Suppress("DEPRECATION", "UNCHECKED_CAST")
        val values = intent.getSerializableExtra(EXTRA_HEADERS) as? HashMap<String, String>
        return values.orEmpty()
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        when (playbackState) {
            Player.STATE_READY -> {
                handler.removeCallbacks(firstFrameWatchdog)
                if (isForeground && !firstFrameRendered && hasSelectedVideoTrack()) {
                    handler.postDelayed(firstFrameWatchdog, FIRST_FRAME_TIMEOUT_MS)
                }
            }
            Player.STATE_ENDED -> finishWithResult(STATUS_COMPLETED)
            Player.STATE_BUFFERING, Player.STATE_IDLE -> Unit
        }
    }

    override fun onPlayerError(error: PlaybackException) {
        terminalError = buildString {
            append(error.errorCodeName)
            if (!error.message.isNullOrBlank()) append(": ${error.message}")
            error.cause?.let { append(" (${it.javaClass.simpleName}: ${it.message})") }
        }
        finishWithResult(STATUS_ERROR)
    }

    override fun onRenderedFirstFrame() {
        firstFrameRendered = true
        everFirstFrameRendered = true
        resetDropWindow()
        handler.removeCallbacks(firstFrameWatchdog)
        handler.removeCallbacks(startupWatchdog)
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        // Reading this callback forces Media3 to validate the video renderer,
        // while onRenderedFirstFrame remains the authoritative display signal.
        if (videoSize.width <= 0 || videoSize.height <= 0) return
    }

    override fun onTracksChanged(tracks: Tracks) {
        val audioGroups = tracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
        if (
            audioGroups.isNotEmpty() &&
            audioGroups.none { group ->
                (0 until group.length).any(group::isTrackSupported)
            }
        ) {
            terminalError = "Media3 found audio tracks but no supported audio decoder."
            finishWithResult(STATUS_ERROR)
            return
        }
        applyPreferredAudioOverride(tracks)
        if (
            isForeground &&
            player.playbackState == Player.STATE_READY &&
            !firstFrameRendered &&
            hasSelectedVideoTrack()
        ) {
            handler.removeCallbacks(firstFrameWatchdog)
            handler.postDelayed(firstFrameWatchdog, FIRST_FRAME_TIMEOUT_MS)
        }
    }

    private fun applyPreferredAudioOverride(tracks: Tracks) {
        if (preferredAudioOverrideApplied) return
        val preferredTags = preferredLanguageTags(preferredAudioLanguage).toSet()
        val normalizedPreference = preferredAudioLanguage.trim().lowercase()
        var bestGroup: Tracks.Group? = null
        var bestTrack = -1
        var bestScore = Int.MIN_VALUE
        var bestNonCommentaryGroup: Tracks.Group? = null
        var bestNonCommentaryTrack = -1
        var bestNonCommentaryScore = Int.MIN_VALUE
        var preferredCommentarySeen = false
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_AUDIO) continue
            for (index in 0 until group.length) {
                if (!group.isTrackSupported(index)) continue
                val format = group.getTrackFormat(index)
                val language = format.language.orEmpty().lowercase()
                val label = format.label.orEmpty().lowercase()
                val description = "$language $label"
                val isPreferred = language in preferredTags ||
                    normalizedPreference in description ||
                    (normalizedPreference in setOf("eng", "en", "english") &&
                        ("english" in description || "eng " in description || "dub" in description)) ||
                    (normalizedPreference in setOf("jpn", "ja", "japanese") &&
                        ("japanese" in description || "jpn" in description || "original" in description))
                val isCommentary =
                    "commentary" in description ||
                        "descriptive" in description ||
                        "description" in description
                if (isPreferred && isCommentary) preferredCommentarySeen = true
                var score = 0
                if (language in preferredTags) score += 120
                if (normalizedPreference in description) score += 70
                if (
                    normalizedPreference in setOf("eng", "en", "english") &&
                    ("english" in description || "eng " in description || "dub" in description)
                ) score += 100
                if (
                    normalizedPreference in setOf("jpn", "ja", "japanese") &&
                    ("japanese" in description || "jpn" in description || "original" in description)
                ) score += 100
                if (format.selectionFlags and C.SELECTION_FLAG_DEFAULT != 0) score += 10
                score += format.channelCount.coerceIn(0, 8)
                if (isCommentary) score -= 250
                if (score > bestScore) {
                    bestScore = score
                    bestGroup = group
                    bestTrack = index
                }
                if (!isCommentary && score > bestNonCommentaryScore) {
                    bestNonCommentaryScore = score
                    bestNonCommentaryGroup = group
                    bestNonCommentaryTrack = index
                }
            }
        }
        var group = bestGroup ?: return
        var track = bestTrack
        if (bestScore < 50) {
            if (!preferredCommentarySeen) return
            group = bestNonCommentaryGroup ?: return
            track = bestNonCommentaryTrack
        }
        if (track < 0) return
        preferredAudioOverrideApplied = true
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, track))
            .build()
    }

    override fun onVideoDecoderInitialized(
        eventTime: AnalyticsListener.EventTime,
        decoderName: String,
        initializedTimestampMs: Long,
        initializationDurationMs: Long,
    ) {
        this.decoderName = decoderName
    }

    override fun onDroppedVideoFrames(
        eventTime: AnalyticsListener.EventTime,
        droppedFrames: Int,
        elapsedMs: Long,
    ) {
        this.droppedFrames += droppedFrames
        if (!firstFrameRendered || !isForeground || !player.isPlaying) return
        dropWindowFrames += droppedFrames
        dropWindowElapsedMs += elapsedMs.coerceAtLeast(0L)
        if (dropWindowElapsedMs < CHOPPY_WINDOW_MIN_MS) return
        val frameRate = (player.videoFormat?.frameRate ?: 0f).takeIf { it > 0f } ?: 24f
        val expectedFrames = frameRate * dropWindowElapsedMs / 1_000f
        val droppedRatio = dropWindowFrames / max(1f, expectedFrames)
        if (dropWindowFrames >= CHOPPY_MIN_DROPPED_FRAMES && droppedRatio >= CHOPPY_DROP_RATIO) {
            consecutiveChoppyWindows++
        } else {
            consecutiveChoppyWindows = 0
        }
        val sampledFrames = dropWindowFrames
        val sampledMs = dropWindowElapsedMs
        resetDropWindow(keepConsecutiveCount = true)
        if (consecutiveChoppyWindows >= CHOPPY_CONSECUTIVE_WINDOWS) {
            terminalError =
                    "Media3 detected excessive dropped frames " +
                    "($sampledFrames in ${sampledMs / 1_000f}s, " +
                    "ratio=${(droppedRatio * 100).toInt()}%, " +
                    "decoder=${decoderName ?: "unknown"})."
            finishWithResult(STATUS_ERROR)
        }
    }

    private fun resetDropWindow(keepConsecutiveCount: Boolean = false) {
        dropWindowElapsedMs = 0L
        dropWindowFrames = 0
        if (!keepConsecutiveCount) consecutiveChoppyWindows = 0
    }

    private fun hasSelectedVideoTrack(): Boolean =
        player.currentTracks.groups.any { group ->
            group.type == C.TRACK_TYPE_VIDEO && group.isSelected
        }

    private fun safePositionMs(): Long =
        if (::player.isInitialized) player.currentPosition.coerceAtLeast(0L) else 0L

    private fun safeDurationMs(): Long {
        if (!::player.isInitialized) return 0L
        return player.duration.takeIf { it != C.TIME_UNSET && it > 0L } ?: 0L
    }

    private fun persistCheckpoint() {
        if (checkpointKey.isBlank() || !::player.isInitialized) return
        val duration = safeDurationMs()
        val position = safePositionMs()
        val completed = duration > 0L && position.toDouble() / duration >= 0.93
        checkpointPreferences.edit()
            .putLong(positionKey(), if (completed) 0L else position)
            .putLong(durationKey(), duration)
            .putBoolean(completedKey(), completed)
            .putLong(updatedKey(), System.currentTimeMillis())
            .apply()
    }

    private fun clearNativeCheckpoint() {
        checkpointPreferences.edit()
            .remove(positionKey())
            .remove(durationKey())
            .remove(completedKey())
            .remove(updatedKey())
            .apply()
    }

    private fun positionKey() = "$checkpointKey.positionMs"
    private fun durationKey() = "$checkpointKey.durationMs"
    private fun completedKey() = "$checkpointKey.completed"
    private fun updatedKey() = "$checkpointKey.updatedAt"

    override fun onPause() {
        isForeground = false
        pauseScheduledWork()
        if (::player.isInitialized) {
            persistCheckpoint()
            resumeAfterTransientPause = player.playWhenReady
            player.pause()
        }
        super.onPause()
    }

    override fun onStart() {
        super.onStart()
        if (backgroundStopped && ::player.isInitialized && !resultSent) {
            firstFrameRendered = false
            resetDropWindow()
            player.setMediaItem(buildMediaItem(), backgroundResumeMs.coerceAtLeast(0L))
            player.prepare()
            player.playWhenReady = false
            backgroundStopped = false
        }
    }

    override fun onResume() {
        super.onResume()
        isForeground = true
        enterImmersiveMode()
        if (::player.isInitialized && resumeAfterTransientPause && !resultSent) {
            resumeAfterTransientPause = false
            player.play()
        }
        armForegroundWork()
    }

    override fun onStop() {
        pauseScheduledWork()
        persistCheckpoint()
        if (::player.isInitialized && !resultSent) {
            // Release renderers, MediaCodec, network loading, and the large
            // progressive buffer while another app owns the screen. The same
            // ExoPlayer/MediaSession is prepared from this exact position in
            // onStart, avoiding decoder starvation on low-memory TV devices.
            backgroundResumeMs = safePositionMs()
            backgroundStopped = true
            player.stop()
            player.clearMediaItems()
        }
        super.onStop()
    }

    private fun pauseScheduledWork() {
        handler.removeCallbacks(checkpointRunnable)
        handler.removeCallbacks(firstFrameWatchdog)
        handler.removeCallbacks(startupWatchdog)
    }

    private fun armForegroundWork() {
        pauseScheduledWork()
        if (resultSent || !isForeground || !::player.isInitialized) return
        handler.postDelayed(checkpointRunnable, CHECKPOINT_INTERVAL_MS)
        if (firstFrameRendered) return
        if (player.playbackState == Player.STATE_READY && hasSelectedVideoTrack()) {
            handler.postDelayed(firstFrameWatchdog, FIRST_FRAME_TIMEOUT_MS)
        } else {
            handler.postDelayed(startupWatchdog, STARTUP_TIMEOUT_MS)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (::playerView.isInitialized) {
            (playerView.videoSurfaceView as? SurfaceView)?.holder?.removeCallback(surfaceCallback)
            playerView.player = null
        }
        if (::player.isInitialized) {
            player.removeListener(this)
            player.removeAnalyticsListener(this)
            if (::mediaSession.isInitialized) mediaSession.release()
            player.release()
        }
        super.onDestroy()
    }

    private fun finishWithResult(status: String) {
        if (resultSent) return
        resultSent = true
        handler.removeCallbacks(firstFrameWatchdog)
        handler.removeCallbacks(startupWatchdog)
        handler.removeCallbacks(checkpointRunnable)
        persistCheckpoint()
        val duration = safeDurationMs()
        val position = safePositionMs()
        val completed = status == STATUS_COMPLETED ||
            (duration > 0L && position.toDouble() / duration >= 0.93)
        val result = Intent().apply {
            putExtra(RESULT_STATUS, status)
            putExtra(RESULT_POSITION_MS, position)
            putExtra(RESULT_DURATION_MS, duration)
            putExtra(RESULT_COMPLETED, completed)
            putExtra(RESULT_ERROR, terminalError)
            putExtra(RESULT_FIRST_FRAME, everFirstFrameRendered)
            putExtra(RESULT_DECODER, decoderName)
            putExtra(RESULT_DROPPED_FRAMES, droppedFrames)
            putExtra(RESULT_SURFACE_READY, surfaceReady)
            putExtra(RESULT_MANUFACTURER, Build.MANUFACTURER)
            putExtra(RESULT_MODEL, Build.MODEL)
            putExtra(RESULT_SDK, Build.VERSION.SDK_INT)
            putExtra(RESULT_ABIS, Build.SUPPORTED_ABIS)
            putExtra(RESULT_MEMORY_CLASS_MB, memoryClassMb())
            putExtra(RESULT_LOW_MEMORY_DEVICE, isLowMemoryDevice())
            putExtra(RESULT_VIDEO_MIME, playerVideoFormat()?.sampleMimeType)
            putExtra(RESULT_VIDEO_CODECS, playerVideoFormat()?.codecs)
            putExtra(RESULT_VIDEO_WIDTH, playerVideoFormat()?.width ?: 0)
            putExtra(RESULT_VIDEO_HEIGHT, playerVideoFormat()?.height ?: 0)
            putExtra(RESULT_VIDEO_FRAME_RATE, playerVideoFormat()?.frameRate ?: 0f)
            putExtra(RESULT_AUDIO_MIME, playerAudioFormat()?.sampleMimeType)
            putExtra(RESULT_AUDIO_CODECS, playerAudioFormat()?.codecs)
        }
        setResult(RESULT_OK, result)
        finish()
    }

    private fun memoryClassMb(): Int =
        (getSystemService(ACTIVITY_SERVICE) as ActivityManager).memoryClass

    private fun isLowMemoryDevice(): Boolean =
        (getSystemService(ACTIVITY_SERVICE) as ActivityManager).isLowRamDevice

    private fun playerVideoFormat() =
        if (::player.isInitialized) player.videoFormat else null

    private fun playerAudioFormat() =
        if (::player.isInitialized) player.audioFormat else null

    @Suppress("DEPRECATION")
    private fun enterImmersiveMode() {
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }

    companion object {
        const val EXTRA_SOURCE = "source"
        const val EXTRA_TITLE = "title"
        const val EXTRA_SUBTITLE_URL = "subtitleUrl"
        const val EXTRA_SUBTITLE_MIME_TYPE = "subtitleMimeType"
        const val EXTRA_SUBTITLE_LANGUAGE = "subtitleLanguage"
        const val EXTRA_SUBTITLE_LABEL = "subtitleLabel"
        const val EXTRA_MIME_TYPE = "mimeType"
        const val EXTRA_FILE_NAME = "fileName"
        const val EXTRA_HEADERS = "headers"
        const val EXTRA_RESUME_MS = "resumeMs"
        const val EXTRA_RESUME_PROVIDED = "resumeProvided"
        const val EXTRA_RESUME_UPDATED_AT_MS = "resumeUpdatedAtMs"
        const val EXTRA_AUTO_PLAY = "autoPlay"
        const val EXTRA_AUDIO_LANGUAGE = "audioLanguage"
        const val EXTRA_SUBTITLES_ENABLED = "subtitlesEnabled"
        const val EXTRA_SUBTITLE_SIZE = "subtitleSize"
        const val EXTRA_SUBTITLE_POSITION = "subtitlePosition"
        const val EXTRA_HIGH_CONTRAST_SUBTITLES = "highContrastSubtitles"
        const val EXTRA_VIDEO_FIT = "videoFit"
        const val EXTRA_START_FROM_BEGINNING = "startFromBeginning"
        const val EXTRA_CHECKPOINT_KEY = "checkpointKey"

        const val RESULT_STATUS = "status"
        const val RESULT_POSITION_MS = "positionMs"
        const val RESULT_DURATION_MS = "durationMs"
        const val RESULT_COMPLETED = "completed"
        const val RESULT_ERROR = "error"
        const val RESULT_FIRST_FRAME = "firstFrame"
        const val RESULT_DECODER = "decoder"
        const val RESULT_DROPPED_FRAMES = "droppedFrames"
        const val RESULT_SURFACE_READY = "surfaceReady"
        const val RESULT_MANUFACTURER = "manufacturer"
        const val RESULT_MODEL = "model"
        const val RESULT_SDK = "sdk"
        const val RESULT_ABIS = "abis"
        const val RESULT_MEMORY_CLASS_MB = "memoryClassMb"
        const val RESULT_LOW_MEMORY_DEVICE = "lowMemoryDevice"
        const val RESULT_VIDEO_MIME = "videoMime"
        const val RESULT_VIDEO_CODECS = "videoCodecs"
        const val RESULT_VIDEO_WIDTH = "videoWidth"
        const val RESULT_VIDEO_HEIGHT = "videoHeight"
        const val RESULT_VIDEO_FRAME_RATE = "videoFrameRate"
        const val RESULT_AUDIO_MIME = "audioMime"
        const val RESULT_AUDIO_CODECS = "audioCodecs"

        const val STATUS_COMPLETED = "completed"
        const val STATUS_STOPPED = "stopped"
        const val STATUS_ERROR = "error"

        private const val CHECKPOINT_PREFERENCES = "native_media3_checkpoints"
        private const val CHECKPOINT_INTERVAL_MS = 5_000L
        private const val FIRST_FRAME_TIMEOUT_MS = 12_000L
        private const val STARTUP_TIMEOUT_MS = 45_000L
        private const val CHOPPY_WINDOW_MIN_MS = 4_000L
        private const val CHOPPY_MIN_DROPPED_FRAMES = 20
        private const val CHOPPY_DROP_RATIO = 0.25f
        private const val CHOPPY_CONSECUTIVE_WINDOWS = 2
        private const val SMOKE_VIDEO_REQUEST_URI = "asset:///assets/videos/vlc_smoke.mp4"
        private const val SMOKE_VIDEO_URI =
            "asset:///flutter_assets/assets/videos/vlc_smoke.mp4"
        private const val SMOKE_SUBTITLE_REQUEST_URI =
            "asset:///assets/subtitles/libass_smoke.ass"
        private const val SMOKE_SUBTITLE_URI =
            "asset:///flutter_assets/assets/subtitles/libass_smoke.ass"

        private fun normalizeMediaUri(value: String): String = when (value) {
            SMOKE_VIDEO_REQUEST_URI -> SMOKE_VIDEO_URI
            SMOKE_SUBTITLE_REQUEST_URI -> SMOKE_SUBTITLE_URI
            else -> value
        }

        private fun preferredLanguageTags(language: String): List<String> {
            val normalized = language.trim().lowercase()
            return when (normalized) {
                "eng", "en", "english" -> listOf("en", "eng")
                "jpn", "ja", "japanese" -> listOf("ja", "jpn")
                else -> listOf(normalized)
            }
        }

        private fun preferredAudioLabels(language: String): List<String> {
            val normalized = language.trim().lowercase()
            return when (normalized) {
                "eng", "en", "english" ->
                    listOf("English", "English Dub", "Dub")
                "jpn", "ja", "japanese" ->
                    listOf("Japanese", "Original", "Japan")
                else -> listOf(language.trim()).filter(String::isNotBlank)
            }
        }

        private fun inferContainerMimeType(
            explicit: String?,
            fileName: String?,
            source: String,
        ): String? {
            if (!explicit.isNullOrBlank()) return explicit
            val value = "${fileName.orEmpty()} $source".lowercase().substringBefore('?')
            return when {
                value.contains(".mkv") -> MimeTypes.APPLICATION_MATROSKA
                value.contains(".webm") -> MimeTypes.VIDEO_WEBM
                value.contains(".mp4") || value.contains(".m4v") -> MimeTypes.VIDEO_MP4
                value.contains(".ts") || value.contains(".m2ts") -> MimeTypes.VIDEO_MP2T
                else -> null
            }
        }

        private fun inferSubtitleMimeType(explicit: String?, url: String): String {
            if (!explicit.isNullOrBlank()) return explicit
            return when (url.lowercase().substringBefore('?').substringAfterLast('.')) {
                "ass", "ssa" -> MimeTypes.TEXT_SSA
                "vtt" -> MimeTypes.TEXT_VTT
                "ttml", "xml" -> MimeTypes.APPLICATION_TTML
                else -> MimeTypes.APPLICATION_SUBRIP
            }
        }
    }
}
