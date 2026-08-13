package dev.animetv.anime_tv.player

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerHudResourceParityTest {
    @Test
    fun media3MatchesMpvChromeGeometryPaletteAndReadOnlyProgress() {
        val layout = resource("layout/tetotv_player_controls.xml").readText()
        val playerLayout = resource("layout/activity_media3_player.xml").readText()
        val styles = resource("values/styles.xml").readText()
        val nightStyles = resource("values-night/styles.xml").readText()
        val card = resource("drawable/tetotv_player_card_background.xml").readText()
        val badge = resource("drawable/tetotv_player_badge_background.xml").readText()
        val normalControl =
            resource("drawable/tetotv_player_control_pill_background.xml").readText()
        val primaryControl =
            resource("drawable/tetotv_player_control_primary_background.xml").readText()
        val scrim = resource("drawable/tetotv_player_controls_scrim.xml").readText()

        listOf(
            "android:layout_marginStart=\"28dp\"",
            "android:layout_marginBottom=\"24dp\"",
            "android:paddingStart=\"18dp\"",
            "android:paddingTop=\"14dp\"",
            "android:paddingBottom=\"12dp\"",
            "android:textSize=\"24sp\"",
            "app:bar_height=\"4dp\"",
            "app:played_color=\"#FFFF496A\"",
            "app:unplayed_color=\"#3DFFFFFF\"",
            "android:textColor=\"#FFB7AEB1\"",
        ).forEach { assertTrue(layout.contains(it)) }
        listOf(styles, nightStyles).forEach { styleSource ->
            assertTrue(styleSource.contains("<item name=\"android:layout_height\">40dp</item>"))
            assertTrue(styleSource.contains("<item name=\"android:layout_height\">26dp</item>"))
            assertTrue(styleSource.contains("<item name=\"android:textColor\">#FFFF496A</item>"))
            assertFalse(styleSource.contains("<item name=\"android:layout_height\">44dp</item>"))
        }
        listOf("#D6080808", "16dp", "1.4dp", "#C7E52B50")
            .forEach { assertTrue(card.contains(it)) }
        listOf("#33E52B50", "#59E52B50").forEach { assertTrue(badge.contains(it)) }
        assertTrue(normalControl.contains("#8F242429"))
        assertFalse(normalControl.contains("#FF3A3A40"))
        assertTrue(primaryControl.contains("#FFE52B50"))
        assertTrue(scrim.contains("#00000000"))
        assertFalse(scrim.contains("<gradient"))

        val timeBar = layout.substringAfter("<androidx.media3.ui.DefaultTimeBar")
            .substringBefore("/>")
        listOf(
            "android:clickable=\"false\"",
            "android:focusable=\"false\"",
            "android:importantForAccessibility=\"no\"",
            "android:longClickable=\"false\"",
            "app:scrubber_disabled_size=\"0dp\"",
            "app:scrubber_dragged_size=\"0dp\"",
            "app:scrubber_enabled_size=\"0dp\"",
        ).forEach { assertTrue(timeBar.contains(it)) }
        assertTrue(playerLayout.contains("app:time_bar_scrubbing_enabled=\"false\""))
        listOf(
            "setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)",
            "cornerRadius = dp(12).toFloat()",
            "setTopMargin(dp(7))",
            "height = dp(3)",
            "setTopMargin(dp(15))",
            "setTopMargin(dp(6))",
            "setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)",
        ).forEach { assertTrue(activitySource().contains(it)) }
    }

    @Test
    fun media3UsesOwnedIconsAndTetoFocusRing() {
        val layout = resource("layout/tetotv_player_controls.xml").readText()
        val activity = source("main/kotlin/dev/animetv/anime_tv/player/Media3PlayerActivity.kt").readText()
        assertFalse(layout.contains("@android:drawable/ic_menu_"))
        listOf("picture", "player", "sources", "options").forEach { name ->
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
        assertTrue(activity.contains("container.requestRectangleOnScreen"))
        assertTrue(layout.contains("android:clipChildren=\"false\""))
        assertTrue(layout.contains("@+id/tetotv_sources_control"))
        assertTrue(activity.contains("STATUS_NEXT_STREAM"))
    }

    @Test
    fun media3ExitAndSkipControlsMatchTheMpvInteractionStyle() {
        val playerLayout = resource("layout/activity_media3_player.xml").readText()
        val skip = resource("drawable/tetotv_skip_button_background.xml").readText()
        val exitBackground =
            resource("drawable/tetotv_player_exit_dialog_background.xml").readText()
        val styles = resource("values/styles.xml").readText()
        val activity = activitySource()

        listOf(
            "android:layout_height=\"44dp\"",
            "android:drawableStart=\"@drawable/tetotv_ic_skip_next\"",
            "android:drawablePadding=\"8dp\"",
            "android:paddingStart=\"18dp\"",
            "android:textSize=\"14sp\"",
        ).forEach { assertTrue(playerLayout.contains(it)) }
        listOf("#B30B0B0D", "#D1FF496A", "#FFFF5C78", "3dp")
            .forEach { assertTrue(skip.contains(it)) }
        listOf("#FA09090B", "16dp", "#4DFFFFFF")
            .forEach { assertTrue(exitBackground.contains(it)) }
        assertTrue(styles.contains("<style name=\"NativePlayerExitDialogTheme\""))
        assertTrue(activity.contains("R.style.NativePlayerExitDialogTheme"))
        assertTrue(activity.contains("min(dp(520), resources.displayMetrics.widthPixels - dp(64))"))
        assertTrue(activity.contains("R.drawable.tetotv_ic_play"))
        assertTrue(activity.contains("R.drawable.tetotv_ic_exit"))
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

    private fun activitySource(): String =
        source("main/kotlin/dev/animetv/anime_tv/player/Media3PlayerActivity.kt").readText()
}
