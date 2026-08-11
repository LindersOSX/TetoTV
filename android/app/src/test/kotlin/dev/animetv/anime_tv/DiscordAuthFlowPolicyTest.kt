package dev.animetv.anime_tv

import android.content.res.Configuration
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DiscordAuthFlowPolicyTest {
    @Test
    fun televisionModeUsesDeviceFlow() {
        assertTrue(
            DiscordAuthFlowPolicy.shouldUseDeviceFlow(
                Configuration.UI_MODE_TYPE_TELEVISION,
                hasLeanback = false,
            ),
        )
    }

    @Test
    fun leanbackDeviceUsesDeviceFlowEvenWithNormalUiMode() {
        assertTrue(
            DiscordAuthFlowPolicy.shouldUseDeviceFlow(
                Configuration.UI_MODE_TYPE_NORMAL,
                hasLeanback = true,
            ),
        )
    }

    @Test
    fun phoneKeepsMobileAuthorizationFlow() {
        assertFalse(
            DiscordAuthFlowPolicy.shouldUseDeviceFlow(
                Configuration.UI_MODE_TYPE_NORMAL,
                hasLeanback = false,
            ),
        )
    }
}
