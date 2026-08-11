package dev.animetv.anime_tv.player

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerHudResourceParityTest {
    @Test
    fun media3UsesOwnedIconsAndTetoFocusRing() {
        val layout = resource("layout/tetotv_player_controls.xml").readText()
        val activity = source("main/kotlin/dev/animetv/anime_tv/player/Media3PlayerActivity.kt").readText()
        assertFalse(layout.contains("@android:drawable/ic_menu_"))
        listOf("picture", "player", "options").forEach { name ->
            assertTrue(layout.contains("@drawable/tetotv_ic_$name"))
            val vector = resource("drawable/tetotv_ic_$name.xml").readText()
            assertTrue(vector.contains("<vector"))
            assertTrue(vector.contains("android:strokeLineCap=\"round\""))
        }

        listOf(
            "tetotv_player_control_pill_background.xml",
            "tetotv_player_control_primary_background.xml",
        ).forEach { name ->
            val selector = resource("drawable/$name").readText()
            assertTrue(selector.contains("android:state_activated=\"true\""))
            assertTrue(selector.contains("android:width=\"3dp\""))
            assertTrue(selector.contains("android:color=\"#FFFF5C78\""))
            assertTrue(selector.contains("android:color=\"#E6000000\""))
            assertFalse(selector.contains("android:color=\"#FFFFFFFF\""))
        }
        assertTrue(activity.contains("control.setOnFocusChangeListener"))
        assertTrue(activity.contains("container.isActivated = hasFocus"))
    }

    @Test
    fun shortcutsCleanUpBeforeDialogsAndUsePlaybackIntent() {
        val activity = source("main/kotlin/dev/animetv/anime_tv/player/Media3PlayerActivity.kt").readText()
        val dispatch = activity.substringAfter("override fun dispatchKeyEvent")
            .substringBefore("/** Keyboard/gamepad shortcuts")
        val cleanup = dispatch.indexOf("consumedNavigationKeyUp?.let")
        val modalGuard = dispatch.indexOf("exitDialog?.isShowing == true")
        assertTrue(cleanup >= 0)
        assertTrue(cleanup < modalGuard)
        assertTrue(dispatch.contains("if (event.keyCode !in MODAL_CHROME_SHORTCUT_KEYS)"))
        listOf("KEYCODE_S", "KEYCODE_C", "KEYCODE_M", "KEYCODE_MENU", "KEYCODE_BUTTON_Y")
            .forEach { assertTrue(activity.contains(it)) }
        assertTrue(activity.contains("consumedNavigationKeyUp = null"))
        assertTrue(
            activity.contains(
                "player.playWhenReady && player.playbackState != Player.STATE_ENDED",
            ),
        )
        assertTrue(
            activity.contains(
                "KeyEvent.KEYCODE_K -> if (isPlaybackIntended()) player.pause() else player.play()",
            ),
        )
        assertTrue(activity.contains("playing = isPlaybackIntended()"))
    }

    private fun resource(path: String): File {
        val relative = "src/main/res/$path"
        return listOf(File(relative), File("app/$relative"), File("android/app/$relative"))
            .firstOrNull(File::isFile)
            ?: error("Could not locate Android resource $relative from ${File(".").absolutePath}")
    }

    private fun source(path: String): File {
        val relative = "src/$path"
        return listOf(File(relative), File("app/$relative"), File("android/app/$relative"))
            .firstOrNull(File::isFile)
            ?: error("Could not locate Android source $relative from ${File(".").absolutePath}")
    }
}
