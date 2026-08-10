package dev.animetv.anime_tv.player

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.app.Dialog
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.TypedValue
import android.view.KeyEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.Button
import android.widget.Toast
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import android.app.AlertDialog
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
import androidx.media3.ui.TrackSelectionDialogBuilder
import dev.animetv.anime_tv.R
import dev.animetv.anime_tv.security.NetworkRequestPolicy
import dev.animetv.anime_tv.security.PublicNetworkDns
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.max
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.json.JSONObject
import java.io.IOException

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
    private lateinit var audioTrackButton: ImageButton
    private lateinit var captionTrackButton: ImageButton
    private lateinit var captionSizeButton: ImageButton
    private lateinit var pictureModeButton: ImageButton
    private lateinit var fixVideoButton: ImageButton
    private lateinit var optionsButton: ImageButton
    private lateinit var skipSegmentButton: Button
    private lateinit var pausedTitleView: TextView
    private val handler = Handler(Looper.getMainLooper())
    private val metadataClient = OkHttpClient.Builder()
        .dns(PublicNetworkDns())
        .connectTimeout(6, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    private fun isTelevisionDevice(): Boolean =
        resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK ==
            Configuration.UI_MODE_TYPE_TELEVISION

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
    private var preferredSubtitleLanguage = "eng"
    private var subtitlesEnabled = true
    private var subtitleSize = 34f
    private var subtitlePosition = 100
    private var highContrastSubtitles = false
    private var subtitleTextColor = Color.WHITE
    private var subtitleBackgroundColor = Color.TRANSPARENT
    private var seekBackIncrementMs = 10_000L
    private var seekForwardIncrementMs = 10_000L
    private var autoSkipIntros = false
    private var autoSkipOutros = false
    private var videoResizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
    private var preferredAudioOverrideApplied = false
    private var preferredSubtitleOverrideApplied = false
    private var backgroundStopped = false
    private var backgroundResumeMs = 0L
    private var dropWindowElapsedMs = 0L
    private var dropWindowFrames = 0
    private var consecutiveChoppyWindows = 0
    private var activeTrackDialog: Dialog? = null
    private var consumedNavigationKeyUp: Int? = null
    private var malMediaId = 0
    private var episodeNumber = 0
    private var skipFetchComplete = false
    private var skipFetchInFlight = false
    private var skipFetchAttempts = 0
    private var activeSkipSegment: NativeSkipSegment? = null
    private val skipSegments = mutableListOf<NativeSkipSegment>()
    private val autoFocusedSkipSegments = mutableSetOf<String>()
    private val autoSkippedSegments = mutableSetOf<String>()
    private var exitDialog: AlertDialog? = null

    private data class NativeSkipSegment(
        val startMs: Long,
        val endMs: Long,
        val kind: String,
    )

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

    private val hideControllerRunnable = Runnable {
        if (
            ::playerView.isInitialized &&
            activeTrackDialog?.isShowing != true &&
            !isFinishing &&
            !isDestroyed
        ) {
            playerView.hideController()
        }
    }

    private val skipSegmentRunnable = object : Runnable {
        override fun run() {
            updateSkipSegmentButton()
            if (!isFinishing && !isDestroyed && isForeground) {
                handler.postDelayed(this, SKIP_SEGMENT_POLL_MS)
            }
        }
    }

    private val skipFetchRetryRunnable = Runnable { fetchSkipSegmentsIfReady() }

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
                override fun handleOnBackPressed() = showExitConfirmation()
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
        malMediaId = intent.getIntExtra(EXTRA_MAL_MEDIA_ID, 0).coerceAtLeast(0)
        episodeNumber = intent.getIntExtra(EXTRA_EPISODE_NUMBER, 0).coerceAtLeast(0)
        val sourceOrigin = NetworkRequestPolicy.httpsOrigin(source)
        if (source.isBlank() || (sourceOrigin == null && source != SMOKE_VIDEO_URI)) {
            terminalError = "The native player requires an HTTPS debrid URL."
            finishWithResult(STATUS_ERROR)
            return
        }

        preferredAudioLanguage =
            intent.getStringExtra(EXTRA_AUDIO_LANGUAGE)?.ifBlank { "eng" } ?: "eng"
        val audioLanguages = preferredLanguageTags(preferredAudioLanguage)
        val audioLabels = preferredAudioLabels(
            preferredAudioLanguage,
        )
        preferredSubtitleLanguage =
            intent.getStringExtra(EXTRA_SUBTITLE_LANGUAGE)?.ifBlank { "eng" } ?: "eng"
        val subtitleLanguages = preferredLanguageTags(preferredSubtitleLanguage)
        subtitlesEnabled = intent.getBooleanExtra(EXTRA_SUBTITLES_ENABLED, true)
        subtitleSize = intent.getFloatExtra(EXTRA_SUBTITLE_SIZE, 34f).coerceIn(18f, 60f)
        subtitlePosition =
            intent.getIntExtra(EXTRA_SUBTITLE_POSITION, 100).coerceIn(60, 100)
        highContrastSubtitles =
            intent.getBooleanExtra(EXTRA_HIGH_CONTRAST_SUBTITLES, false)
        subtitleTextColor = intent.getIntExtra(EXTRA_SUBTITLE_TEXT_COLOR, Color.WHITE)
        subtitleBackgroundColor =
            intent.getIntExtra(EXTRA_SUBTITLE_BACKGROUND_COLOR, Color.TRANSPARENT)
        seekBackIncrementMs =
            intent.getLongExtra(EXTRA_SEEK_BACK_MS, 10_000L).coerceIn(5_000L, 60_000L)
        seekForwardIncrementMs =
            intent.getLongExtra(EXTRA_SEEK_FORWARD_MS, 10_000L).coerceIn(5_000L, 60_000L)
        autoSkipIntros = intent.getBooleanExtra(EXTRA_AUTO_SKIP_INTROS, false)
        autoSkipOutros = intent.getBooleanExtra(EXTRA_AUTO_SKIP_OUTROS, false)
        videoResizeMode = when (intent.getStringExtra(EXTRA_VIDEO_FIT)) {
            "cover" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
        val trackSelector = DefaultTrackSelector(this).apply {
            parameters = buildUponParameters()
                .setPreferredAudioLanguages(*audioLanguages.toTypedArray())
                .setPreferredAudioLabels(*audioLabels.toTypedArray())
                .setPreferredTextLanguages(*subtitleLanguages.toTypedArray())
                // Anime releases frequently leave an otherwise valid English
                // ASS/SRT track's language undefined. Prefer it only when no
                // explicitly preferred-language track is available.
                .setSelectUndeterminedTextLanguage(subtitlesEnabled)
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

        val suppliedHeaders = NetworkRequestPolicy.sanitizeRequestHeaders(intentHeaders())
        val httpClientBuilder = OkHttpClient.Builder()
            .dns(PublicNetworkDns())
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .retryOnConnectionFailure(true)
        if (sourceOrigin != null && suppliedHeaders.isNotEmpty()) {
            // The same Media3 data-source factory also loads external subtitle
            // files and cross-origin playlist segments. Never forward account
            // credentials or add-on-specific secret headers outside the exact
            // origin for which they were supplied.
            httpClientBuilder.addNetworkInterceptor { chain ->
                val request = chain.request()
                val requestOrigin = NetworkRequestPolicy.origin(
                    request.url.scheme,
                    request.url.host,
                    request.url.port,
                )
                val builder = request.newBuilder()
                suppliedHeaders.keys
                    .filterNot { header ->
                        NetworkRequestPolicy.shouldForwardHeader(
                            header,
                            sourceOrigin,
                            requestOrigin,
                        )
                    }
                    .forEach(builder::removeHeader)
                chain.proceed(builder.build())
            }
        }
        val httpClient = httpClientBuilder.build()
        val requestHeaders = linkedMapOf(
            "Accept" to "*/*",
            "User-Agent" to "TetoTV/1.7 AndroidTV Media3",
        ).apply { putAll(suppliedHeaders) }
        val httpFactory = OkHttpDataSource.Factory(httpClient)
            .setUserAgent(requestHeaders.getValue("User-Agent"))
            .setDefaultRequestProperties(requestHeaders)
        val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)

        player = ExoPlayer.Builder(this, renderersFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .setSeekBackIncrementMs(seekBackIncrementMs)
            .setSeekForwardIncrementMs(seekForwardIncrementMs)
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

        setContentView(R.layout.activity_media3_player)
        playerView = findViewById<PlayerView>(R.id.tetotv_player_view).apply {
            setBackgroundColor(Color.BLACK)
            setShutterBackgroundColor(Color.BLACK)
            useController = true
            // Media3 otherwise keeps controls visible forever while paused.
            // TetoTV uses one deterministic inactivity policy in every state.
            controllerAutoShow = !isTelevisionDevice()
            controllerHideOnTouch = true
            controllerShowTimeoutMs = CONTROLLER_HIDE_TIMEOUT_MS.toInt()
            setShowPreviousButton(false)
            setShowNextButton(false)
            setShowRewindButton(true)
            setShowFastForwardButton(true)
            // TetoTV owns the explicit, TV-focusable caption picker below.
            setShowSubtitleButton(false)
            setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING)
            setKeepContentOnPlayerReset(false)
            resizeMode = videoResizeMode
            subtitleView?.apply {
                val customCaptionColors =
                    subtitleTextColor != Color.WHITE || subtitleBackgroundColor != Color.TRANSPARENT
                setApplyEmbeddedStyles(!highContrastSubtitles && !customCaptionColors)
                setApplyEmbeddedFontSizes(
                    !highContrastSubtitles && subtitleSize == DEFAULT_SUBTITLE_SIZE,
                )
                setFixedTextSize(
                    TypedValue.COMPLEX_UNIT_SP,
                    subtitleSize,
                )
                setBottomPaddingFraction((108 - subtitlePosition) / 100f)
                if (highContrastSubtitles || customCaptionColors) {
                    setStyle(
                        CaptionStyleCompat(
                            subtitleTextColor,
                            if (highContrastSubtitles) 0xDD000000.toInt()
                            else subtitleBackgroundColor,
                            Color.TRANSPARENT,
                            CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                            Color.BLACK,
                            null,
                        ),
                    )
                }
            }
            player = this@Media3PlayerActivity.player
        }
        audioTrackButton = playerView.findViewById<ImageButton>(R.id.tetotv_audio_tracks).apply {
            setOnClickListener {
                showTrackPicker(C.TRACK_TYPE_AUDIO, this)
            }
        }
        captionTrackButton =
            playerView.findViewById<ImageButton>(R.id.tetotv_caption_tracks).apply {
                setOnClickListener {
                    showTrackPicker(C.TRACK_TYPE_TEXT, this)
                }
            }
        captionSizeButton =
            playerView.findViewById<ImageButton>(R.id.tetotv_caption_size).apply {
                setOnClickListener { showSubtitleSizePicker(this) }
            }
        pictureModeButton =
            playerView.findViewById<ImageButton>(R.id.tetotv_picture_mode).apply {
                setOnClickListener { cyclePictureMode(this) }
            }
        fixVideoButton =
            playerView.findViewById<ImageButton>(R.id.tetotv_fix_video).apply {
                setOnClickListener { showPlayerPicker(this) }
            }
        optionsButton =
            playerView.findViewById<ImageButton>(R.id.tetotv_player_options).apply {
                setOnClickListener { showPlaybackOptions(this) }
            }
        skipSegmentButton =
            findViewById<Button>(R.id.tetotv_skip_segment).apply {
                visibility = View.GONE
                setOnClickListener {
                    val segment = activeSkipSegment ?: return@setOnClickListener
                    player.seekTo(segment.endMs.coerceAtMost(safeDurationMs()))
                    activeSkipSegment = null
                    visibility = View.GONE
                    if (playerView.isControllerFullyVisible) {
                        requestTransportFocus()
                        armControllerAutoHide()
                    } else {
                        playerView.requestFocus()
                    }
                }
            }
        pausedTitleView = playerView.findViewById<TextView>(R.id.tetotv_paused_title).apply {
            text = intent.getStringExtra(EXTRA_TITLE).orEmpty()
            visibility = View.GONE
        }
        playerView.findViewById<TextView>(R.id.tetotv_controller_title).text =
            intent.getStringExtra(EXTRA_TITLE).orEmpty()
        playerView.findViewById<TextView>(R.id.tetotv_stream_label).text =
            intent.getStringExtra(EXTRA_STREAM_LABEL).orEmpty().ifBlank { "Debrid stream" }
        updateCaptionSizeDescription()
        playerView.findViewById<View>(androidx.media3.ui.R.id.exo_rew).apply {
            contentDescription = getString(
                R.string.tetotv_player_rewind_seconds,
                seekBackIncrementMs / 1_000,
            )
            setOnClickListener { seekRelative(-seekBackIncrementMs, it) }
        }
        playerView.findViewById<View>(androidx.media3.ui.R.id.exo_ffwd).apply {
            contentDescription = getString(
                R.string.tetotv_player_fast_forward_seconds,
                seekForwardIncrementMs / 1_000,
            )
            setOnClickListener { seekRelative(seekForwardIncrementMs, it) }
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
        requestTransportFocus()
        armControllerAutoHide()
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
        val allowedSubtitleUrl = subtitleUrl?.takeIf {
            it == SMOKE_SUBTITLE_URI || NetworkRequestPolicy.httpsOrigin(it) != null
        }
        if (!allowedSubtitleUrl.isNullOrBlank()) {
            val subtitleMime = inferSubtitleMimeType(
                intent.getStringExtra(EXTRA_SUBTITLE_MIME_TYPE),
                allowedSubtitleUrl,
            )
            val subtitle = MediaItem.SubtitleConfiguration.Builder(Uri.parse(allowedSubtitleUrl))
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
                fetchSkipSegmentsIfReady()
                if (isForeground && !firstFrameRendered && hasSelectedVideoTrack()) {
                    handler.postDelayed(firstFrameWatchdog, FIRST_FRAME_TIMEOUT_MS)
                }
            }
            Player.STATE_ENDED -> finishWithResult(STATUS_COMPLETED)
            Player.STATE_BUFFERING, Player.STATE_IDLE -> Unit
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        if (::pausedTitleView.isInitialized) {
            pausedTitleView.visibility = if (isPlaying) View.GONE else View.VISIBLE
        }
    }

    private fun fetchSkipSegmentsIfReady() {
        if (
            skipFetchComplete ||
            skipFetchInFlight ||
            skipFetchAttempts >= MAX_SKIP_FETCH_ATTEMPTS ||
            malMediaId <= 0 ||
            episodeNumber <= 0
        ) return
        val durationMs = safeDurationMs()
        if (durationMs <= 0L) return
        skipFetchInFlight = true
        skipFetchAttempts++
        val episodeLength = durationMs / 1_000.0
        val url = buildString {
            append("https://api.aniskip.com/v2/skip-times/")
            append(malMediaId)
            append('/')
            append(episodeNumber)
            append("?types%5B%5D=op&types%5B%5D=ed")
            append("&types%5B%5D=mixed-op&types%5B%5D=mixed-ed")
            append("&types%5B%5D=recap")
            append("&episodeLength=")
            append(episodeLength)
        }
        val request = Request.Builder()
            .url(url)
            .header("Accept", "application/json")
            .header("User-Agent", "TetoTV/1.9 AndroidTV Media3")
            .build()
        metadataClient.newCall(request).enqueue(
            object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    handler.post {
                        if (resultSent || isFinishing || isDestroyed) return@post
                        skipFetchInFlight = false
                        scheduleSkipFetchRetry()
                    }
                }

                override fun onResponse(call: Call, response: Response) {
                    response.use {
                        val successful = response.isSuccessful
                        val retryableStatus = response.code == 429 || response.code >= 500
                        val parsed = if (successful) {
                            val body = response.body
                            val contentLength = body?.contentLength() ?: 0L
                            val payload = runCatching {
                                body?.source()?.let { source ->
                                    if (contentLength > MAX_SKIP_RESPONSE_BYTES) {
                                        null
                                    } else {
                                        source.request(MAX_SKIP_RESPONSE_BYTES + 1L)
                                        if (source.buffer.size > MAX_SKIP_RESPONSE_BYTES) {
                                            null
                                        } else {
                                            source.buffer.clone().readUtf8()
                                        }
                                    }
                                }
                            }.getOrNull()
                            payload?.let {
                                runCatching { parseSkipSegments(it, durationMs) }.getOrNull()
                            }
                        } else {
                            null
                        }
                        handler.post {
                            if (resultSent || isFinishing || isDestroyed) return@post
                            skipFetchInFlight = false
                            when {
                                successful && parsed != null -> {
                                    skipFetchComplete = true
                                    skipSegments.clear()
                                    skipSegments.addAll(parsed)
                                    updateSkipSegmentButton()
                                }
                                retryableStatus || successful -> scheduleSkipFetchRetry()
                                else -> skipFetchComplete = true
                            }
                        }
                    }
                }
            },
        )
    }

    private fun scheduleSkipFetchRetry() {
        if (skipFetchAttempts >= MAX_SKIP_FETCH_ATTEMPTS) {
            skipFetchComplete = true
            return
        }
        handler.removeCallbacks(skipFetchRetryRunnable)
        if (!isForeground) return
        handler.postDelayed(
            skipFetchRetryRunnable,
            SKIP_FETCH_RETRY_BASE_MS * skipFetchAttempts,
        )
    }

    private fun parseSkipSegments(payload: String, durationMs: Long): List<NativeSkipSegment> {
        val results = JSONObject(payload).optJSONArray("results") ?: return emptyList()
        val episodeLengthSeconds = durationMs / 1_000.0
        return buildList {
            for (index in 0 until results.length()) {
                val item = results.optJSONObject(index) ?: continue
                val interval = item.optJSONObject("interval") ?: continue
                val startMs = (interval.optDouble("startTime", -1.0) * 1_000).toLong()
                val endMs = (interval.optDouble("endTime", -1.0) * 1_000).toLong()
                val referenceLength = item.optDouble("episodeLength", episodeLengthSeconds)
                val durationTolerance = max(45.0, episodeLengthSeconds * 0.05)
                if (abs(referenceLength - episodeLengthSeconds) > durationTolerance) continue
                val clampedStart = startMs.coerceIn(0L, durationMs)
                val clampedEnd = endMs.coerceIn(0L, durationMs)
                val length = clampedEnd - clampedStart
                if (length !in MIN_SKIP_SEGMENT_MS..MAX_SKIP_SEGMENT_MS) continue
                val kind = when (item.optString("skipType").lowercase()) {
                    "op", "mixed-op", "opening", "intro" -> "opening"
                    "ed", "mixed-ed", "ending", "outro" -> "ending"
                    "recap" -> "recap"
                    else -> continue
                }
                add(NativeSkipSegment(clampedStart, clampedEnd, kind))
            }
        }.sortedBy(NativeSkipSegment::startMs)
    }

    private fun updateSkipSegmentButton() {
        if (!::skipSegmentButton.isInitialized || !::player.isInitialized) return
        val position = safePositionMs()
        val active = skipSegments.firstOrNull {
            position >= it.startMs && position < it.endMs - 500L
        }
        if (active == activeSkipSegment) return
        activeSkipSegment = active
        if (active != null) {
            val autoSkip =
                (active.kind == "opening" && autoSkipIntros) ||
                    (active.kind == "ending" && autoSkipOutros)
            val key = "${active.kind}:${active.startMs}"
            if (autoSkip && autoSkippedSegments.add(key)) {
                player.seekTo(active.endMs.coerceAtMost(safeDurationMs()))
                activeSkipSegment = null
                skipSegmentButton.visibility = View.GONE
                Toast.makeText(
                    this,
                    if (active.kind == "opening") "Intro skipped" else "Outro skipped",
                    Toast.LENGTH_SHORT,
                ).show()
                return
            }
        }
        skipSegmentButton.visibility = if (active == null) View.GONE else View.VISIBLE
        if (active != null) {
            skipSegmentButton.setText(
                when (active.kind) {
                    "ending" -> R.string.tetotv_player_skip_outro
                    "recap" -> R.string.tetotv_player_skip_recap
                    else -> R.string.tetotv_player_skip_intro
                },
            )
            val focusKey = "${active.kind}:${active.startMs}"
            if (autoFocusedSkipSegments.add(focusKey)) {
                skipSegmentButton.post { skipSegmentButton.requestFocus() }
            }
        }
    }

    override fun onPlayerError(error: PlaybackException) {
        terminalError = buildString {
            append(error.errorCodeName)
            NetworkRequestPolicy.redactNetworkDiagnostic(error.message)?.let {
                append(": $it")
            }
            error.cause?.let { cause ->
                append(" (${cause.javaClass.simpleName}")
                NetworkRequestPolicy.redactNetworkDiagnostic(cause.message)?.let {
                    append(": $it")
                }
                append(')')
            }
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
        applyPreferredSubtitleOverride(tracks)
        updateTrackButtons(tracks)
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

    private fun applyPreferredSubtitleOverride(tracks: Tracks) {
        if (preferredSubtitleOverrideApplied || !subtitlesEnabled) return
        val preferredTags = preferredLanguageTags(preferredSubtitleLanguage).toSet()
        val normalizedPreference = preferredSubtitleLanguage.trim().lowercase()
        var bestGroup: Tracks.Group? = null
        var bestTrack = -1
        var bestScore = Int.MIN_VALUE
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_TEXT) continue
            for (index in 0 until group.length) {
                if (!group.isTrackSupported(index)) continue
                val format = group.getTrackFormat(index)
                val language = format.language.orEmpty().lowercase()
                val label = format.label.orEmpty().lowercase()
                val description = "$language $label"
                var score = 0
                if (language in preferredTags) score += 140
                if (normalizedPreference in description) score += 80
                if (
                    normalizedPreference in setOf("eng", "en", "english") &&
                    ("english" in description || "eng " in description)
                ) score += 120
                if (format.selectionFlags and C.SELECTION_FLAG_DEFAULT != 0) score += 15
                if ("full" in description || "dialogue" in description) score += 30
                if ("closed caption" in description || "cc" in label || "sdh" in label) score += 20
                if (format.selectionFlags and C.SELECTION_FLAG_FORCED != 0) score -= 100
                if ("sign" in description || "song" in description || "forced" in description) {
                    score -= 100
                }
                if (score > bestScore) {
                    bestScore = score
                    bestGroup = group
                    bestTrack = index
                }
            }
        }
        val group = bestGroup ?: return
        if (bestTrack < 0 || bestScore < 50) return
        // Set the guard before changing parameters because that change can
        // synchronously result in another onTracksChanged callback.
        preferredSubtitleOverrideApplied = true
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, bestTrack))
            .build()
    }

    private fun updateTrackButtons(tracks: Tracks) {
        if (!::audioTrackButton.isInitialized || !::captionTrackButton.isInitialized) return
        val hasAudio = tracks.groups.any { group ->
            group.type == C.TRACK_TYPE_AUDIO &&
                (0 until group.length).any(group::isTrackSupported)
        }
        val hasCaptions = tracks.groups.any { group ->
            group.type == C.TRACK_TYPE_TEXT &&
                (0 until group.length).any(group::isTrackSupported)
        }
        audioTrackButton.isEnabled = hasAudio
        audioTrackButton.alpha = if (hasAudio) 1f else DISABLED_CONTROL_ALPHA
        captionTrackButton.isEnabled = hasCaptions
        captionTrackButton.alpha = if (hasCaptions) 1f else DISABLED_CONTROL_ALPHA
        val captionsSelected = tracks.groups.any { group ->
            group.type == C.TRACK_TYPE_TEXT && group.isSelected
        }
        captionTrackButton.isSelected = captionsSelected
        captionTrackButton.setImageResource(
            if (captionsSelected) {
                R.drawable.tetotv_ic_subtitle_on
            } else {
                R.drawable.tetotv_ic_subtitle_off
            },
        )
        captionTrackButton.contentDescription = getString(
            if (captionsSelected) {
                R.string.tetotv_player_closed_captions_on
            } else {
                R.string.tetotv_player_closed_captions_off
            },
        )
    }

    private fun showTrackPicker(trackType: Int, sourceButton: View) {
        val selectableTracks = player.currentTracks.groups.any { group ->
            group.type == trackType &&
                (0 until group.length).any(group::isTrackSupported)
        }
        if (!selectableTracks) {
            val message = if (trackType == C.TRACK_TYPE_AUDIO) {
                R.string.tetotv_player_no_audio_tracks
            } else {
                R.string.tetotv_player_no_caption_tracks
            }
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
            armControllerAutoHide()
            return
        }

        handler.removeCallbacks(hideControllerRunnable)
        activeTrackDialog?.dismiss()
        val title = if (trackType == C.TRACK_TYPE_AUDIO) {
            R.string.tetotv_player_select_audio
        } else {
            R.string.tetotv_player_select_captions
        }
        try {
            val dialog = TrackSelectionDialogBuilder(this, getString(title), player, trackType)
                .setTheme(R.style.NativePlayerTrackDialogTheme)
                .setAllowAdaptiveSelections(false)
                .setAllowMultipleOverrides(false)
                .setShowDisableOption(trackType == C.TRACK_TYPE_TEXT)
                .build()
            activeTrackDialog = dialog
            dialog.setOnDismissListener {
                if (activeTrackDialog === dialog) activeTrackDialog = null
                if (!isFinishing && !isDestroyed) {
                    playerView.showController()
                    sourceButton.requestFocus()
                    armControllerAutoHide()
                }
            }
            dialog.show()
        } catch (_: Throwable) {
            activeTrackDialog = null
            Toast.makeText(
                this,
                R.string.tetotv_player_track_picker_error,
                Toast.LENGTH_SHORT,
            ).show()
            playerView.showController()
            sourceButton.requestFocus()
            armControllerAutoHide()
        }
    }

    private fun showSubtitleSizePicker(sourceButton: View) {
        handler.removeCallbacks(hideControllerRunnable)
        activeTrackDialog?.dismiss()
        val values = SUBTITLE_SIZE_VALUES
        val labels = arrayOf(
            getString(R.string.tetotv_player_caption_size_small),
            getString(R.string.tetotv_player_caption_size_medium),
            getString(R.string.tetotv_player_caption_size_large),
            getString(R.string.tetotv_player_caption_size_extra_large),
        )
        val selectedIndex = values.indices.minByOrNull { index ->
            abs(values[index] - subtitleSize)
        } ?: 1
        try {
            val dialog = AlertDialog.Builder(this, R.style.NativePlayerTrackDialogTheme)
                .setTitle(R.string.tetotv_player_select_caption_size)
                .setSingleChoiceItems(labels, selectedIndex) { picker, index ->
                    subtitleSize = values[index]
                    applySubtitleStyle()
                    Toast.makeText(
                        this,
                        getString(
                            R.string.tetotv_player_caption_size_changed,
                            labels[index],
                        ),
                        Toast.LENGTH_SHORT,
                    ).show()
                    picker.dismiss()
                }
                .setNegativeButton(android.R.string.cancel, null)
                .create()
            activeTrackDialog = dialog
            dialog.setOnDismissListener {
                if (activeTrackDialog === dialog) activeTrackDialog = null
                if (!isFinishing && !isDestroyed) {
                    playerView.showController()
                    sourceButton.requestFocus()
                    armControllerAutoHide()
                }
            }
            dialog.show()
        } catch (_: Throwable) {
            activeTrackDialog = null
            Toast.makeText(
                this,
                R.string.tetotv_player_track_picker_error,
                Toast.LENGTH_SHORT,
            ).show()
            playerView.showController()
            sourceButton.requestFocus()
            armControllerAutoHide()
        }
    }

    private fun cyclePictureMode(sourceButton: View) {
        videoResizeMode = when (videoResizeMode) {
            AspectRatioFrameLayout.RESIZE_MODE_FIT ->
                AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            AspectRatioFrameLayout.RESIZE_MODE_ZOOM ->
                AspectRatioFrameLayout.RESIZE_MODE_FILL
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
        playerView.resizeMode = videoResizeMode
        val label = when (videoResizeMode) {
            AspectRatioFrameLayout.RESIZE_MODE_ZOOM -> "Fill screen"
            AspectRatioFrameLayout.RESIZE_MODE_FILL -> "Stretch"
            else -> "Fit"
        }
        Toast.makeText(this, "Picture: $label", Toast.LENGTH_SHORT).show()
        playerView.showController()
        sourceButton.requestFocus()
        armControllerAutoHide()
    }

    private fun showPlaybackOptions(sourceButton: View) {
        handler.removeCallbacks(hideControllerRunnable)
        activeTrackDialog?.dismiss()
        val labels = arrayOf(
            "Picture mode",
            "Audio tracks",
            "Closed captions",
            "Caption size",
            "Choose player",
        )
        try {
            val dialog = AlertDialog.Builder(this, R.style.NativePlayerTrackDialogTheme)
                .setTitle(R.string.tetotv_player_options)
                .setItems(labels) { picker, index ->
                    picker.dismiss()
                    handler.post {
                        when (index) {
                            0 -> cyclePictureMode(sourceButton)
                            1 -> showTrackPicker(C.TRACK_TYPE_AUDIO, audioTrackButton)
                            2 -> showTrackPicker(C.TRACK_TYPE_TEXT, captionTrackButton)
                            3 -> showSubtitleSizePicker(captionSizeButton)
                            4 -> showPlayerPicker(sourceButton)
                        }
                    }
                }
                .setNegativeButton(android.R.string.cancel, null)
                .create()
            activeTrackDialog = dialog
            dialog.setOnDismissListener {
                if (activeTrackDialog === dialog) activeTrackDialog = null
                if (!isFinishing && !isDestroyed) {
                    playerView.showController()
                    sourceButton.requestFocus()
                    armControllerAutoHide()
                }
            }
            dialog.show()
        } catch (_: Throwable) {
            activeTrackDialog = null
            Toast.makeText(
                this,
                R.string.tetotv_player_track_picker_error,
                Toast.LENGTH_SHORT,
            ).show()
            playerView.showController()
            sourceButton.requestFocus()
            armControllerAutoHide()
        }
    }

    private fun showPlayerPicker(sourceButton: View) {
        handler.removeCallbacks(hideControllerRunnable)
        activeTrackDialog?.dismiss()
        val labels = arrayOf(
            "Media3 - current",
            "MPV - best for subtitles and web streams",
            "VLC - compatibility player",
        )
        try {
            val dialog = AlertDialog.Builder(this, R.style.NativePlayerTrackDialogTheme)
                .setTitle("Choose player")
                .setSingleChoiceItems(labels, 0) { picker, index ->
                    picker.dismiss()
                    when (index) {
                        1 -> {
                            persistCheckpoint()
                            finishWithResult(STATUS_USE_MPV)
                        }
                        2 -> {
                            persistCheckpoint()
                            finishWithResult(STATUS_USE_VLC)
                        }
                        else -> {
                            playerView.showController()
                            sourceButton.requestFocus()
                            armControllerAutoHide()
                        }
                    }
                }
                .setNegativeButton(android.R.string.cancel, null)
                .create()
            activeTrackDialog = dialog
            dialog.setOnDismissListener {
                if (activeTrackDialog === dialog) activeTrackDialog = null
                if (!isFinishing && !isDestroyed) {
                    playerView.showController()
                    sourceButton.requestFocus()
                    armControllerAutoHide()
                }
            }
            dialog.show()
        } catch (_: Throwable) {
            activeTrackDialog = null
            Toast.makeText(
                this,
                R.string.tetotv_player_track_picker_error,
                Toast.LENGTH_SHORT,
            ).show()
            playerView.showController()
            sourceButton.requestFocus()
            armControllerAutoHide()
        }
    }

    private fun applySubtitleStyle() {
        playerView.subtitleView?.apply {
            val customCaptionColors =
                subtitleTextColor != Color.WHITE || subtitleBackgroundColor != Color.TRANSPARENT
            setApplyEmbeddedStyles(!highContrastSubtitles && !customCaptionColors)
            setApplyEmbeddedFontSizes(
                !highContrastSubtitles && !customCaptionColors &&
                    subtitleSize == DEFAULT_SUBTITLE_SIZE,
            )
            setFixedTextSize(TypedValue.COMPLEX_UNIT_SP, subtitleSize)
            setBottomPaddingFraction((108 - subtitlePosition) / 100f)
            if (highContrastSubtitles || customCaptionColors) {
                setStyle(
                    CaptionStyleCompat(
                        subtitleTextColor,
                        if (highContrastSubtitles) 0xDD000000.toInt()
                        else subtitleBackgroundColor,
                        Color.TRANSPARENT,
                        CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                        Color.BLACK,
                        null,
                    ),
                )
            }
        }
        updateCaptionSizeDescription()
    }

    private fun updateCaptionSizeDescription() {
        if (!::captionSizeButton.isInitialized) return
        val label = when (subtitleSize) {
            in 0f..30f -> getString(R.string.tetotv_player_caption_size_small)
            in 30f..38f -> getString(R.string.tetotv_player_caption_size_medium)
            in 38f..46f -> getString(R.string.tetotv_player_caption_size_large)
            else -> getString(R.string.tetotv_player_caption_size_extra_large)
        }
        captionSizeButton.contentDescription = getString(
            R.string.tetotv_player_caption_size_changed,
            label,
        )
    }

    private fun seekRelative(offsetMs: Long, sourceButton: View) {
        val duration = safeDurationMs()
        val candidate = safePositionMs() + offsetMs
        val target = when {
            candidate < 0L -> 0L
            duration > 0L && candidate > duration -> duration
            else -> candidate
        }
        player.seekTo(target)
        playerView.showController()
        sourceButton.requestFocus()
        armControllerAutoHide()
    }

    private fun showExitConfirmation() {
        if (exitDialog?.isShowing == true || isFinishing || isDestroyed) return
        // isPlaying is false while buffering even though playWhenReady is true.
        // Always pause so playback cannot start behind the confirmation dialog.
        val resumeAfterDialog = ::player.isInitialized && player.playWhenReady
        if (::player.isInitialized) player.pause()
        val dialog = AlertDialog.Builder(this, R.style.NativePlayerTrackDialogTheme)
            .setTitle("Exit video?")
            .setMessage("Your current playback position will be saved.")
            .setCancelable(false)
            .setNegativeButton("Continue watching") { _, _ ->
                if (resumeAfterDialog && !isFinishing && !isDestroyed) player.play()
                playerView.showController()
                requestTransportFocus()
                armControllerAutoHide()
            }
            .setPositiveButton("Exit video") { _, _ ->
                persistCheckpoint()
                finishWithResult(STATUS_STOPPED)
            }
            .create()
        exitDialog = dialog
        dialog.setOnDismissListener {
            if (exitDialog === dialog) exitDialog = null
        }
        dialog.setOnShowListener {
            val continueButton = dialog.getButton(AlertDialog.BUTTON_NEGATIVE)
            val exitButton = dialog.getButton(AlertDialog.BUTTON_POSITIVE)
            val horizontalPadding = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                18f,
                resources.displayMetrics,
            ).toInt()
            val verticalPadding = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                11f,
                resources.displayMetrics,
            ).toInt()
            dialog.findViewById<TextView>(android.R.id.message)?.apply {
                setTextColor(Color.WHITE)
                alpha = 0.92f
            }
            continueButton?.apply {
                isAllCaps = false
                setTextColor(Color.WHITE)
                setBackgroundResource(R.drawable.tetotv_dialog_neutral_button)
                setPadding(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding)
            }
            exitButton?.apply {
                isAllCaps = false
                setTextColor(Color.WHITE)
                setBackgroundResource(R.drawable.tetotv_dialog_danger_button)
                setPadding(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding)
            }
            continueButton?.setOnKeyListener { _, keyCode, event ->
                if (
                    event.action == KeyEvent.ACTION_DOWN &&
                    (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT ||
                        keyCode == KeyEvent.KEYCODE_DPAD_DOWN)
                ) {
                    exitButton?.requestFocus()
                    true
                } else {
                    false
                }
            }
            exitButton?.setOnKeyListener { _, keyCode, event ->
                if (
                    event.action == KeyEvent.ACTION_DOWN &&
                    (keyCode == KeyEvent.KEYCODE_DPAD_LEFT ||
                        keyCode == KeyEvent.KEYCODE_DPAD_UP)
                ) {
                    continueButton?.requestFocus()
                    true
                } else {
                    false
                }
            }
            continueButton?.requestFocus()
        }
        dialog.show()
    }

    private fun requestTransportFocus() {
        val playPause = playerView.findViewById<View>(androidx.media3.ui.R.id.exo_play_pause)
        if (playPause?.requestFocus() != true) playerView.requestFocus()
    }

    private fun armControllerAutoHide() {
        handler.removeCallbacks(hideControllerRunnable)
        if (
            ::playerView.isInitialized &&
            playerView.isControllerFullyVisible &&
            activeTrackDialog?.isShowing != true
        ) {
            handler.postDelayed(hideControllerRunnable, CONTROLLER_HIDE_TIMEOUT_MS)
        }
    }

    // ComponentActivity exposes the platform Activity dispatch hook through
    // androidx.core with a library-group annotation. Overriding it is required
    // here so a hidden controller can consume the first DPAD-left/right event
    // before a video or time bar sees it.
    @SuppressLint("RestrictedApi")
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!::playerView.isInitialized) return super.dispatchKeyEvent(event)
        // Modal dialogs own directional focus. Letting the hidden controller
        // consume their first Left/Right press made "Exit video" unreachable
        // on a number of Fire TV and Google TV remotes.
        if (exitDialog?.isShowing == true || activeTrackDialog?.isShowing == true) {
            return super.dispatchKeyEvent(event)
        }
        if (::skipSegmentButton.isInitialized && skipSegmentButton.hasFocus()) {
            return super.dispatchKeyEvent(event)
        }

        consumedNavigationKeyUp?.let { consumedKey ->
            if (event.keyCode == consumedKey) {
                if (event.action == KeyEvent.ACTION_UP) consumedNavigationKeyUp = null
                return true
            }
        }

        val isInitialKeyDown = event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0
        if (isInitialKeyDown) {
            if (event.keyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
                if (playerView.isControllerFullyVisible) {
                    consumedNavigationKeyUp = event.keyCode
                    handler.removeCallbacks(hideControllerRunnable)
                    playerView.hideController()
                    return true
                }
            }

            if (event.keyCode in CONTROLLER_NAVIGATION_KEYS) {
                if (!playerView.isControllerFullyVisible) {
                    // The first direction press only opens the controls. This
                    // prevents DPAD-left/right from leaking into a seek path.
                    consumedNavigationKeyUp = event.keyCode
                    playerView.showController()
                    requestTransportFocus()
                    armControllerAutoHide()
                    return true
                }
                armControllerAutoHide()
            } else if (event.keyCode in CONTROLLER_INTERACTION_KEYS) {
                // Dedicated media buttons still perform their native action,
                // but the viewer should also see the updated play/seek state.
                if (!playerView.isControllerFullyVisible) {
                    playerView.showController()
                }
                armControllerAutoHide()
            }
        }

        val handled = super.dispatchKeyEvent(event)
        if (
            event.action == KeyEvent.ACTION_UP &&
            playerView.isControllerFullyVisible &&
            event.keyCode in CONTROLLER_INTERACTION_KEYS
        ) {
            armControllerAutoHide()
        }
        return handled
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
        handler.removeCallbacks(skipSegmentRunnable)
        handler.removeCallbacks(skipFetchRetryRunnable)
        handler.removeCallbacks(firstFrameWatchdog)
        handler.removeCallbacks(startupWatchdog)
        handler.removeCallbacks(hideControllerRunnable)
    }

    private fun armForegroundWork() {
        pauseScheduledWork()
        if (resultSent || !isForeground || !::player.isInitialized) return
        handler.postDelayed(checkpointRunnable, CHECKPOINT_INTERVAL_MS)
        handler.post(skipSegmentRunnable)
        fetchSkipSegmentsIfReady()
        if (playerView.isControllerFullyVisible) armControllerAutoHide()
        if (firstFrameRendered) return
        if (player.playbackState == Player.STATE_READY && hasSelectedVideoTrack()) {
            handler.postDelayed(firstFrameWatchdog, FIRST_FRAME_TIMEOUT_MS)
        } else {
            handler.postDelayed(startupWatchdog, STARTUP_TIMEOUT_MS)
        }
    }

    override fun onDestroy() {
        exitDialog?.dismiss()
        exitDialog = null
        activeTrackDialog?.dismiss()
        activeTrackDialog = null
        metadataClient.dispatcher.cancelAll()
        metadataClient.connectionPool.evictAll()
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
        handler.removeCallbacks(skipSegmentRunnable)
        handler.removeCallbacks(skipFetchRetryRunnable)
        handler.removeCallbacks(hideControllerRunnable)
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
            putExtra(RESULT_SUBTITLE_SIZE, subtitleSize)
            putExtra(RESULT_AUDIO_LANGUAGE, selectedTrackLanguage(C.TRACK_TYPE_AUDIO))
            putExtra(RESULT_SUBTITLE_LANGUAGE, selectedTrackLanguage(C.TRACK_TYPE_TEXT))
            putExtra(RESULT_SUBTITLES_ENABLED, hasSelectedTextTrack())
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

    private fun hasSelectedTextTrack(): Boolean =
        ::player.isInitialized && player.currentTracks.groups.any {
            it.type == C.TRACK_TYPE_TEXT && it.isSelected
        }

    private fun selectedTrackLanguage(trackType: Int): String? {
        if (!::player.isInitialized) return null
        for (group in player.currentTracks.groups) {
            if (group.type != trackType || !group.isSelected) continue
            for (index in 0 until group.length) {
                if (!group.isTrackSelected(index)) continue
                val format = group.getTrackFormat(index)
                return format.language?.takeIf(String::isNotBlank)
                    ?: format.label?.takeIf(String::isNotBlank)
            }
        }
        return null
    }

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
        const val EXTRA_STREAM_LABEL = "streamLabel"
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
        const val EXTRA_SUBTITLE_TEXT_COLOR = "subtitleTextColor"
        const val EXTRA_SUBTITLE_BACKGROUND_COLOR = "subtitleBackgroundColor"
        const val EXTRA_SEEK_BACK_MS = "seekBackMs"
        const val EXTRA_SEEK_FORWARD_MS = "seekForwardMs"
        const val EXTRA_AUTO_SKIP_INTROS = "autoSkipIntros"
        const val EXTRA_AUTO_SKIP_OUTROS = "autoSkipOutros"
        const val EXTRA_VIDEO_FIT = "videoFit"
        const val EXTRA_START_FROM_BEGINNING = "startFromBeginning"
        const val EXTRA_CHECKPOINT_KEY = "checkpointKey"
        const val EXTRA_MAL_MEDIA_ID = "malMediaId"
        const val EXTRA_EPISODE_NUMBER = "episodeNumber"

        const val RESULT_STATUS = "status"
        const val RESULT_POSITION_MS = "positionMs"
        const val RESULT_DURATION_MS = "durationMs"
        const val RESULT_COMPLETED = "completed"
        const val RESULT_ERROR = "error"
        const val RESULT_FIRST_FRAME = "firstFrame"
        const val RESULT_DECODER = "decoder"
        const val RESULT_DROPPED_FRAMES = "droppedFrames"
        const val RESULT_SUBTITLE_SIZE = "subtitleSize"
        const val RESULT_AUDIO_LANGUAGE = "audioLanguage"
        const val RESULT_SUBTITLE_LANGUAGE = "subtitleLanguage"
        const val RESULT_SUBTITLES_ENABLED = "subtitlesEnabled"
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
        const val STATUS_USE_MPV = "use_mpv"
        const val STATUS_USE_VLC = "use_vlc"

        private const val CHECKPOINT_PREFERENCES = "native_media3_checkpoints"
        private const val CHECKPOINT_INTERVAL_MS = 5_000L
        private const val CONTROLLER_HIDE_TIMEOUT_MS = 5_000L
        private const val SKIP_SEGMENT_POLL_MS = 300L
        private const val MAX_SKIP_FETCH_ATTEMPTS = 3
        private const val MAX_SKIP_RESPONSE_BYTES = 256L * 1024L
        private const val SKIP_FETCH_RETRY_BASE_MS = 2_000L
        private const val MIN_SKIP_SEGMENT_MS = 8_000L
        private const val MAX_SKIP_SEGMENT_MS = 240_000L
        private const val DEFAULT_SUBTITLE_SIZE = 34f
        private val SUBTITLE_SIZE_VALUES = floatArrayOf(28f, 34f, 42f, 50f)
        private const val DISABLED_CONTROL_ALPHA = 0.38f
        private const val FIRST_FRAME_TIMEOUT_MS = 12_000L
        private const val STARTUP_TIMEOUT_MS = 45_000L
        private const val CHOPPY_WINDOW_MIN_MS = 4_000L
        private const val CHOPPY_MIN_DROPPED_FRAMES = 20
        private const val CHOPPY_DROP_RATIO = 0.25f
        private const val CHOPPY_CONSECUTIVE_WINDOWS = 2
        private val CONTROLLER_NAVIGATION_KEYS = setOf(
            KeyEvent.KEYCODE_DPAD_UP,
            KeyEvent.KEYCODE_DPAD_DOWN,
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
        )
        private val CONTROLLER_INTERACTION_KEYS = CONTROLLER_NAVIGATION_KEYS + setOf(
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_MEDIA_PLAY,
            KeyEvent.KEYCODE_MEDIA_PAUSE,
            KeyEvent.KEYCODE_MEDIA_REWIND,
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
        )
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
