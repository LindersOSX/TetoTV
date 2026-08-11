package dev.animetv.anime_tv

import android.content.res.Configuration

/** Selects Discord's limited-input flow on Android TV and Fire TV devices. */
internal object DiscordAuthFlowPolicy {
    fun shouldUseDeviceFlow(uiMode: Int, hasLeanback: Boolean): Boolean {
        val mode = uiMode and Configuration.UI_MODE_TYPE_MASK
        return mode == Configuration.UI_MODE_TYPE_TELEVISION || hasLeanback
    }
}
