package dev.animetv.anime_tv

import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppStoragePolicyTest {
    @Test
    fun `cache cleanup deletes only supplied roots`() {
        val appRoot = Files.createTempDirectory("tetotv-storage-policy").toFile()
        try {
            val cache = appRoot.resolve("cache").apply { mkdirs() }
            val nested = cache.resolve("updates").apply { mkdirs() }
            nested.resolve("update.apk").writeBytes(ByteArray(1_024))
            cache.resolve("poster.tmp").writeBytes(ByteArray(512))
            val databases = appRoot.resolve("databases").apply { mkdirs() }
            val history = databases.resolve("tetotv.db").apply {
                writeText("persistent history")
            }
            val preferences = appRoot.resolve("shared_prefs").apply { mkdirs() }
                .resolve("settings.xml").apply { writeText("persistent settings") }

            val bytes = AppStoragePolicy.clearCacheRoots(listOf(cache))

            assertEquals(1_536L, bytes)
            assertTrue(cache.exists())
            assertEquals(0, cache.listFiles()?.size ?: 0)
            assertTrue(history.exists())
            assertTrue(preferences.exists())
        } finally {
            appRoot.deleteRecursively()
        }
    }

    @Test
    fun `cache cleanup does not follow a root escaping canonical path`() {
        val appRoot = Files.createTempDirectory("tetotv-storage-boundary").toFile()
        try {
            val cache = appRoot.resolve("cache").apply { mkdirs() }
            val persistent = appRoot.resolve("persistent.txt").apply { writeText("keep") }
            // Only children discovered under cache are eligible. A sibling is
            // never traversed even though it shares the same application root.
            AppStoragePolicy.clearCacheRoots(listOf(cache))
            assertTrue(persistent.exists())
            assertFalse(cache.resolve("persistent.txt").exists())
        } finally {
            appRoot.deleteRecursively()
        }
    }
}
