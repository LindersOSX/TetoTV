package dev.animetv.anime_tv.player

import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Media3PlayerSafetyTest {
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
}
