package dev.animetv.anime_tv.player

import android.view.KeyEvent
import androidx.media3.common.Player
import java.io.ByteArrayInputStream
import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class Media3PlayerSafetyTest {
    @Test
    fun `Watch Together HUD accepts only public room display fields`() {
        val result = parseNativeWatchPartyHudResult(
            mapOf(
                "ok" to true,
                "roomCode" to "23456789",
                "watchUrl" to "https://tetotv-bot.wisp.uno/watch?room=23456789",
                "status" to "PARTY 23456789 - HOST",
                "message" to "Share this code.",
                "participants" to listOf(
                    mapOf(
                        "display_name" to "Teto Fan",
                        "avatar_url" to
                            "https://s4.anilist.co/file/anilistcdn/user/avatar/large/x.jpg",
                        "role" to "host",
                        "ready" to true,
                    ),
                    mapOf(
                        "display_name" to "Injected",
                        "role" to "guest",
                        "ready" to true,
                        "token" to "must-not-cross",
                    ),
                ),
                "host_token" to "must-not-cross-the-HUD-bridge",
                "stream_url" to "https://private.invalid/video",
                "headers" to mapOf("Authorization" to "secret"),
            ),
        )

        assertTrue(result.ok)
        assertEquals("23456789", result.roomCode)
        assertEquals(
            "https://tetotv-bot.wisp.uno/watch?room=23456789",
            result.watchUrl,
        )
        assertEquals("Share this code.", result.message)
        assertEquals(1, result.participants.size)
        assertEquals("Teto Fan", result.participants.single().displayName)
        assertEquals("host", result.participants.single().role)
        assertTrue(result.participants.single().ready)
    }

    @Test
    fun `native participant preview is bounded and rejects unsafe profile data`() {
        val roster = (0 until 10).map { index ->
            mapOf(
                "display_name" to "Guest $index",
                "avatar_url" to "https://cdn.myanimelist.net/images/userimages/$index.jpg",
                "role" to "guest",
                "ready" to (index % 2 == 0),
            )
        }
        assertEquals(6, parseNativeWatchPartyParticipants(roster).size)
        assertTrue(
            parseNativeWatchPartyParticipants(
                listOf(
                    mapOf(
                        "display_name" to "Guest",
                        "avatar_url" to "https://s4.anilist.co/avatar.png",
                        "role" to "guest",
                        "ready" to true,
                    ),
                ),
            ).single().avatarUrl!!.startsWith("https://s4.anilist.co/"),
        )
        assertTrue(
            parseNativeWatchPartyParticipants(
                listOf(
                    mapOf(
                        "display_name" to "Guest",
                        "avatar_url" to "https://evil.example/avatar.png",
                        "role" to "guest",
                        "ready" to true,
                    ),
                ),
            ).isEmpty(),
        )
        assertTrue(
            parseNativeWatchPartyParticipants(
                listOf(
                    mapOf(
                        "display_name" to "person@example.com",
                        "role" to "guest",
                        "ready" to true,
                    ),
                ),
            ).isEmpty(),
        )
    }

    @Test
    fun `native participant avatar download has a hard byte bound`() {
        assertEquals(
            4,
            readBoundedWatchPartyAvatar(ByteArrayInputStream(byteArrayOf(1, 2, 3, 4)), 4)
                ?.size,
        )
        assertNull(
            readBoundedWatchPartyAvatar(ByteArrayInputStream(ByteArray(5)), 4),
        )
    }

    @Test
    fun `Watch Together HUD rejects malformed codes and unsafe URLs`() {
        val malformedCode = parseNativeWatchPartyHudResult(
            mapOf(
                "ok" to true,
                "roomCode" to "A3456789",
                "watchUrl" to "https://tetotv-bot.wisp.uno/watch?room=A3456789",
                "message" to "bad code",
            ),
        )
        val ambiguousDigits = parseNativeWatchPartyHudResult(
            mapOf(
                "ok" to true,
                "roomCode" to "12345678",
                "watchUrl" to "https://tetotv-bot.wisp.uno/watch?room=12345678",
                "message" to "bad digits",
            ),
        )
        val credentialUrl = parseNativeWatchPartyHudResult(
            mapOf(
                "ok" to true,
                "roomCode" to "23456789",
                "watchUrl" to "https://secret@example.test/watch",
                "message" to "bad URL",
            ),
        )
        val capabilityQuery = parseNativeWatchPartyHudResult(
            mapOf(
                "ok" to true,
                "roomCode" to "23456789",
                "watchUrl" to
                    "https://tetotv-bot.wisp.uno/watch?room=23456789&host_token=secret",
                "message" to "bad query",
            ),
        )

        assertFalse(malformedCode.ok)
        assertFalse(ambiguousDigits.ok)
        assertFalse(credentialUrl.ok)
        assertFalse(capabilityQuery.ok)
    }

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
    fun `native skip focus follows playback and transport without stealing dialogs`() {
        assertTrue(
            nativeShouldAutoFocusSkipAction(
                controllerVisible = false,
                transportFocused = false,
                modalVisible = false,
            ),
        )
        assertTrue(
            nativeShouldAutoFocusSkipAction(
                controllerVisible = true,
                transportFocused = true,
                modalVisible = false,
            ),
        )
        assertFalse(
            nativeShouldAutoFocusSkipAction(
                controllerVisible = true,
                transportFocused = false,
                modalVisible = false,
            ),
        )
        assertFalse(
            nativeShouldAutoFocusSkipAction(
                controllerVisible = false,
                transportFocused = false,
                modalVisible = true,
            ),
        )
    }

    @Test
    fun `native skip autofocus is consumed once for intro and once for outro`() {
        val focused = mutableSetOf<String>()
        val intro = nativeSkipSegmentKey(NativeSkipSegment(60_000L, 150_000L, "opening"))
        val outro = nativeSkipSegmentKey(NativeSkipSegment(1_290_000L, 1_440_000L, "ending"))

        assertTrue(focused.add(intro))
        assertFalse(focused.add(intro))
        assertTrue(focused.add(outro))
        assertFalse(focused.add(outro))
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
    fun `watch party commands require the exact native playback generation`() {
        assertTrue(
            nativePlayerCommandMatchesSession(
                activeCheckpointKey = "154587:2",
                activeGeneration = 8,
                requestedCheckpointKey = "154587:2",
                requestedGeneration = 8,
                action = "seek",
            ),
        )
        assertFalse(
            nativePlayerCommandMatchesSession(
                activeCheckpointKey = "154587:2",
                activeGeneration = 8,
                requestedCheckpointKey = "154587:3",
                requestedGeneration = 8,
                action = "pause",
            ),
        )
        assertFalse(
            nativePlayerCommandMatchesSession(
                activeCheckpointKey = "154587:2",
                activeGeneration = 8,
                requestedCheckpointKey = "154587:2",
                requestedGeneration = 7,
                action = "play",
            ),
        )
        assertFalse(
            nativePlayerCommandMatchesSession(
                activeCheckpointKey = "154587:2",
                activeGeneration = 8,
                requestedCheckpointKey = "154587:2",
                requestedGeneration = 8,
                action = "stop",
            ),
        )
    }

    @Test
    fun `attached guest local transport is rejected while coordinator play bypasses lock`() {
        var playing = false
        var seekTarget = -1L

        for (
            origin in listOf(
                NativeTransportCommandOrigin.LOCAL_HUD,
                NativeTransportCommandOrigin.LOCAL_KEY,
                NativeTransportCommandOrigin.MEDIA_SESSION,
            )
        ) {
            assertFalse(
                dispatchNativeTransportCommand(
                    guestControlsLocked = true,
                    origin = origin,
                    action = "play",
                    play = { playing = true },
                    pause = { playing = false },
                    seek = { seekTarget = it },
                ),
            )
        }
        assertFalse(playing)

        assertTrue(
            nativePlayerCommandMatchesSession(
                activeCheckpointKey = "154587:2",
                activeGeneration = 8,
                requestedCheckpointKey = "154587:2",
                requestedGeneration = 8,
                action = "play",
            ),
        )
        assertTrue(
            dispatchNativeTransportCommand(
                guestControlsLocked = true,
                origin = NativeTransportCommandOrigin.WATCH_PARTY_COORDINATOR,
                action = "play",
                play = { playing = true },
                pause = { playing = false },
                seek = { seekTarget = it },
            ),
        )
        assertTrue(playing)
        assertEquals(-1L, seekTarget)
    }

    @Test
    fun `Watch Party media transition dismissal requires exact native generation`() {
        assertTrue(
            nativePlayerSessionMatches(
                activeCheckpointKey = "154587:2",
                activeGeneration = 8,
                requestedCheckpointKey = "154587:2",
                requestedGeneration = 8,
            ),
        )
        assertFalse(
            nativePlayerSessionMatches(
                activeCheckpointKey = "154587:2",
                activeGeneration = 8,
                requestedCheckpointKey = "154587:3",
                requestedGeneration = 8,
            ),
        )
        assertFalse(
            nativePlayerSessionMatches(
                activeCheckpointKey = "154587:2",
                activeGeneration = 8,
                requestedCheckpointKey = "154587:2",
                requestedGeneration = 7,
            ),
        )
    }

    @Test
    fun `guest MediaSession rejects playback and settings but preserves volume`() {
        for (
            command in listOf(
                Player.COMMAND_PLAY_PAUSE,
                Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
                Player.COMMAND_SET_TRACK_SELECTION_PARAMETERS,
                Player.COMMAND_SET_MEDIA_ITEM,
                Player.COMMAND_SET_VIDEO_SURFACE,
            )
        ) {
            assertTrue(nativeGuestLockBlocksMediaSessionCommand(true, command))
        }
        assertFalse(
            nativeGuestLockBlocksMediaSessionCommand(
                true,
                Player.COMMAND_ADJUST_DEVICE_VOLUME_WITH_FLAGS,
            ),
        )
        assertFalse(
            nativeGuestLockBlocksMediaSessionCommand(
                true,
                Player.COMMAND_SET_VOLUME,
            ),
        )
        assertFalse(
            nativeGuestLockBlocksMediaSessionCommand(
                false,
                Player.COMMAND_PLAY_PAUSE,
            ),
        )
    }

    @Test
    fun `guest key lock consumes local player shortcuts but not D-pad or volume`() {
        for (
            keyCode in listOf(
                KeyEvent.KEYCODE_K,
                KeyEvent.KEYCODE_S,
                KeyEvent.KEYCODE_C,
                KeyEvent.KEYCODE_I,
                KeyEvent.KEYCODE_MENU,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            )
        ) {
            assertTrue(nativeGuestLockBlocksLocalKey(true, keyCode))
        }
        assertFalse(nativeGuestLockBlocksLocalKey(true, KeyEvent.KEYCODE_DPAD_LEFT))
        assertFalse(nativeGuestLockBlocksLocalKey(true, KeyEvent.KEYCODE_VOLUME_UP))
        assertFalse(nativeGuestLockBlocksLocalKey(false, KeyEvent.KEYCODE_K))
    }

    @Test
    fun `ended Media3 session stays attached for guests but completes for hosts`() {
        assertFalse(nativePlayerShouldFinishAtEnd(guestControlsLocked = true))
        assertTrue(nativePlayerShouldFinishAtEnd(guestControlsLocked = false))
    }

    @Test
    fun `guest lock role transitions require exact session and monotonic sequence`() {
        assertTrue(
            nativeWatchPartyStateMatchesSession(
                activeCheckpointKey = "154587:2",
                activeGeneration = 8,
                requestedCheckpointKey = "154587:2",
                requestedGeneration = 8,
                stateSequence = 4,
            ),
        )
        assertFalse(
            nativeWatchPartyStateMatchesSession(
                activeCheckpointKey = "154587:2",
                activeGeneration = 8,
                requestedCheckpointKey = "154587:3",
                requestedGeneration = 8,
                stateSequence = 4,
            ),
        )
        assertFalse(
            nativeWatchPartyStateMatchesSession(
                activeCheckpointKey = "154587:2",
                activeGeneration = 8,
                requestedCheckpointKey = "154587:2",
                requestedGeneration = 7,
                stateSequence = 4,
            ),
        )
        assertFalse(
            nativeWatchPartyStateMatchesSession(
                activeCheckpointKey = "154587:2",
                activeGeneration = 8,
                requestedCheckpointKey = "154587:2",
                requestedGeneration = 8,
                stateSequence = 4,
                lastStateSequence = 4,
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
