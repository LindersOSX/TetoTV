package dev.animetv.anime_tv.player

import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class Media3PlayerSafetyTest {
    @Test
    fun `HLS media source factory remains available at runtime`() {
        val factory = Class.forName(
            "androidx.media3.exoplayer.hls.HlsMediaSource\$Factory",
        )

        assertEquals(
            "androidx.media3.exoplayer.hls.HlsMediaSource\$Factory",
            factory.name,
        )
    }

    @Test
    fun `network cleanup never runs inline with Activity destruction`() {
        val queued = mutableListOf<Runnable>()
        val cleanup = Media3NetworkCleanup(Executor(queued::add))
        var callsCanceled = false
        var connectionsEvicted = false

        cleanup.schedule(
            cancelCalls = { callsCanceled = true },
            evictConnections = { connectionsEvicted = true },
        )

        assertEquals(1, queued.size)
        assertFalse(callsCanceled)
        assertFalse(connectionsEvicted)

        queued.single().run()

        assertTrue(callsCanceled)
        assertTrue(connectionsEvicted)
    }

    @Test
    fun `connection eviction still runs when call cancellation fails`() {
        val cleanup = Media3NetworkCleanup(Executor(Runnable::run))
        var connectionsEvicted = false

        cleanup.schedule(
            cancelCalls = { error("synthetic cancellation failure") },
            evictConnections = { connectionsEvicted = true },
        )

        assertTrue(connectionsEvicted)
    }

    @Test
    fun `skip target avoids the exact end of the file`() {
        assertEquals(1_439_000L, safeNativeSkipTargetMs(1_440_000L, 1_440_000L))
        assertEquals(1_290_000L, safeNativeSkipTargetMs(1_290_000L, 1_440_000L))
    }

    @Test
    fun `skip target remains usable before duration is known`() {
        assertEquals(240_000L, safeNativeSkipTargetMs(240_000L, 0L))
        assertEquals(0L, safeNativeSkipTargetMs(-1L, 1_440_000L))
    }

    @Test
    fun `terminal outro is recognized even with the eof guard`() {
        assertTrue(nativeSkipReachesPlaybackEnd(1_440_000L, 1_440_000L))
        assertTrue(nativeSkipReachesPlaybackEnd(1_439_500L, 1_440_000L))
        assertFalse(nativeSkipReachesPlaybackEnd(1_290_000L, 1_440_000L))
    }

    @Test
    fun `consuming an intro leaves a later outro eligible`() {
        val intro = NativeSkipSegment(60_000L, 150_000L, "opening")
        val outro = NativeSkipSegment(1_290_000L, 1_440_000L, "ending")
        val consumed = setOf(nativeSkipSegmentKey(intro))

        assertEquals(
            outro,
            activeNativeSkipSegment(
                positionMs = 1_300_000L,
                segments = listOf(intro, outro),
                consumedSegmentKeys = consumed,
            ),
        )
        assertFalse(nativeSkipSegmentKey(outro) in consumed)
    }

    @Test
    fun `dual and multi audio release labels request extended discovery`() {
        assertTrue(nativeReleaseAdvertisesMultipleAudio("[Group] Show - Dual Audio"))
        assertTrue(nativeReleaseAdvertisesMultipleAudio("Show.Multi-Audio.1080p"))
        assertTrue(nativeReleaseAdvertisesMultipleAudio("Show [DUAL] 1080p"))
        assertTrue(nativeReleaseAdvertisesMultipleAudio("Show ENG+JPN 1080p"))
        assertFalse(nativeReleaseAdvertisesMultipleAudio("Show Japanese Audio 1080p"))
        assertFalse(nativeReleaseAdvertisesMultipleAudio(null))
    }

    @Test
    fun `undefined native track language uses its descriptive label`() {
        assertEquals("English Dub", nativeSelectedTrackLanguage("und", "English Dub"))
        assertEquals("Japanese", nativeSelectedTrackLanguage("zxx", "Japanese"))
        assertEquals("eng", nativeSelectedTrackLanguage("eng", "Japanese"))
        assertEquals(null, nativeSelectedTrackLanguage("mul", ""))
    }

    @Test
    fun `manual native audio events publish canonical persisted languages`() {
        assertEquals("eng", nativeCanonicalTrackLanguage("en-US", "Japanese"))
        assertEquals("eng", nativeCanonicalTrackLanguage("und", "English Dub 5.1"))
        assertEquals("jpn", nativeCanonicalTrackLanguage(null, "Japanese"))
        assertEquals("spa", nativeCanonicalTrackLanguage("es", null))
        assertEquals(null, nativeCanonicalTrackLanguage("mul", ""))
    }

    @Test
    fun `native progress allows explicit audio before duration discovery`() {
        assertTrue(nativePlaybackProgressIsPublishable("15125:9", 1_440_000L))
        assertFalse(nativePlaybackProgressIsPublishable("", 1_440_000L))
        assertFalse(nativePlaybackProgressIsPublishable("15125:9", 0L))
        assertTrue(
            nativePlaybackProgressIsPublishable(
                "15125:9",
                0L,
                audioPreferenceSet = true,
            ),
        )
        assertFalse(
            nativePlaybackProgressIsPublishable(
                "",
                0L,
                audioPreferenceSet = true,
            ),
        )
    }

    @Test
    fun `commentary never qualifies as preferred native dialogue`() {
        assertTrue(nativePreferredAudioCandidateIsUsable(140, "eng English Dub"))
        assertFalse(
            nativePreferredAudioCandidateIsUsable(
                140,
                "eng English Director Commentary",
            ),
        )
        assertFalse(nativePreferredAudioCandidateIsUsable(20, "jpn Japanese Stereo"))
    }

    @Test
    fun `provisional audio fallback remains replaceable by a later preferred track`() {
        val provisional = nativePreferredAudioOverrideAction(
            preferredAlreadyApplied = false,
            viewerSelectionActive = false,
            candidateMatchesPreference = false,
            candidateMatchesLastOverride = false,
            candidateAlreadySelected = false,
        )
        assertTrue(provisional.applyOverride)
        assertFalse(provisional.markPreferredApplied)

        val repeatedSnapshot = nativePreferredAudioOverrideAction(
            preferredAlreadyApplied = provisional.markPreferredApplied,
            viewerSelectionActive = false,
            candidateMatchesPreference = false,
            candidateMatchesLastOverride = true,
            candidateAlreadySelected = true,
        )
        assertFalse(repeatedSnapshot.applyOverride)
        assertFalse(repeatedSnapshot.markPreferredApplied)

        val preferredArrives = nativePreferredAudioOverrideAction(
            preferredAlreadyApplied = repeatedSnapshot.markPreferredApplied,
            viewerSelectionActive = false,
            candidateMatchesPreference = true,
            candidateMatchesLastOverride = false,
            candidateAlreadySelected = false,
        )
        assertTrue(preferredArrives.applyOverride)
        assertTrue(preferredArrives.markPreferredApplied)
    }

    @Test
    fun `preferred dub is reasserted when a later snapshot selects Japanese`() {
        val action = nativePreferredAudioOverrideAction(
            preferredAlreadyApplied = true,
            viewerSelectionActive = false,
            candidateMatchesPreference = true,
            candidateMatchesLastOverride = true,
            candidateAlreadySelected = false,
        )

        assertTrue(action.applyOverride)
        assertTrue(action.markPreferredApplied)
    }

    @Test
    fun `viewer audio selection stops automatic snapshot overrides`() {
        val action = nativePreferredAudioOverrideAction(
            preferredAlreadyApplied = false,
            viewerSelectionActive = true,
            candidateMatchesPreference = true,
            candidateMatchesLastOverride = false,
            candidateAlreadySelected = false,
        )

        assertFalse(action.applyOverride)
        assertFalse(action.markPreferredApplied)
    }

    @Test
    fun `unsupported torrent container errors use same-stream MPV fallback`() {
        assertTrue(
            nativePlaybackErrorRequiresMpv(
                "ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED: sniff failures: [NoDeclaredBrand]",
            ),
        )
        assertTrue(
            nativePlaybackErrorRequiresMpv(
                "None of the available extractors could read the stream",
            ),
        )
        assertFalse(nativePlaybackErrorRequiresMpv("ERROR_CODE_IO_NETWORK_CONNECTION_FAILED"))
    }

    @Test
    fun `torrent seek remains actionable through MPV when Media3 disables it`() {
        assertTrue(
            nativeShouldOfferSeekFallback(
                expectedSeekable = true,
                seekAttemptSucceeded = false,
            ),
        )
        assertFalse(
            nativeShouldOfferSeekFallback(
                expectedSeekable = false,
                seekAttemptSucceeded = false,
            ),
        )
        assertFalse(
            nativeShouldOfferSeekFallback(
                expectedSeekable = true,
                seekAttemptSucceeded = true,
            ),
        )

        assertFalse(nativeSeekAttemptSucceeded(canSeek = false) { error("must not run") })
        assertFalse(nativeSeekAttemptSucceeded(canSeek = true) { error("command lost") })
        assertTrue(nativeSeekAttemptSucceeded(canSeek = true) {})
    }

    @Test
    fun `embedded unsupported captions use MPV while a missing caption track does not`() {
        assertTrue(
            nativeShouldUseMpvForUnsupportedCaptions(
                embeddedCaptionTrackCount = 2,
                supportedCaptionTrackCount = 0,
            ),
        )
        assertFalse(
            nativeShouldUseMpvForUnsupportedCaptions(
                embeddedCaptionTrackCount = 0,
                supportedCaptionTrackCount = 0,
            ),
        )
        assertFalse(
            nativeShouldUseMpvForUnsupportedCaptions(
                embeddedCaptionTrackCount = 2,
                supportedCaptionTrackCount = 1,
            ),
        )

        assertTrue(
            nativeSubtitlesEnabledResult(
                selectedTextTrack = false,
                subtitlePreferenceChanged = false,
                forceMpvCaptionIntent = true,
            ) == true,
        )
        assertFalse(
            nativeSubtitlesEnabledResult(
                selectedTextTrack = false,
                subtitlePreferenceChanged = true,
                forceMpvCaptionIntent = false,
            ) ?: true,
        )
        assertTrue(
            nativeSubtitlesEnabledResult(
                selectedTextTrack = true,
                subtitlePreferenceChanged = true,
                forceMpvCaptionIntent = false,
            ) == true,
        )
        assertNull(
            nativeSubtitlesEnabledResult(
                selectedTextTrack = false,
                subtitlePreferenceChanged = false,
                forceMpvCaptionIntent = false,
            ),
        )
        assertNull(
            nativeSubtitlesEnabledResult(
                selectedTextTrack = true,
                subtitlePreferenceChanged = false,
                forceMpvCaptionIntent = false,
            ),
        )
    }

    @Test
    fun `preferred captions are reasserted after a Matroska group replacement`() {
        val action = nativePreferredAudioOverrideAction(
            preferredAlreadyApplied = true,
            viewerSelectionActive = false,
            candidateMatchesPreference = true,
            candidateMatchesLastOverride = true,
            candidateAlreadySelected = false,
        )

        assertTrue(action.applyOverride)
        assertTrue(action.markPreferredApplied)
    }
}
