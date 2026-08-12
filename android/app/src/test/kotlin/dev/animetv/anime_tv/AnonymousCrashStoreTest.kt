package dev.animetv.anime_tv

import android.app.ApplicationExitInfo
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AnonymousCrashStoreTest {
    @Test
    fun `only crash and ANR exit reasons are reportable`() {
        assertTrue(AnonymousCrashStore.isReportableReason(ApplicationExitInfo.REASON_CRASH))
        assertTrue(AnonymousCrashStore.isReportableReason(ApplicationExitInfo.REASON_CRASH_NATIVE))
        assertTrue(AnonymousCrashStore.isReportableReason(ApplicationExitInfo.REASON_ANR))
        assertFalse(AnonymousCrashStore.isReportableReason(ApplicationExitInfo.REASON_EXIT_SELF))
        assertFalse(AnonymousCrashStore.isReportableReason(ApplicationExitInfo.REASON_USER_REQUESTED))
    }

    @Test
    fun `native descriptions are redacted and bounded`() {
        val output = AnonymousCrashStore.sanitize(
            "failed https://private.example/watch Bearer secret token=private " +
                "magnet:?xt=urn:btih:123 ${"a".repeat(64)}\nnext",
            140,
        )

        assertTrue(output.contains("[URL]"))
        assertTrue(output.contains("Bearer [REDACTED]"))
        assertTrue(output.contains("[MAGNET]"))
        assertFalse(output.contains("private.example"))
        assertFalse(output.contains("token=private"))
        assertFalse(output.contains("secret"))
        assertFalse(output.contains("a".repeat(40)))
        assertTrue(output.length <= 140)
    }
}
