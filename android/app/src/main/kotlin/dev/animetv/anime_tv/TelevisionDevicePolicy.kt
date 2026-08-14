package dev.animetv.anime_tv

import android.content.res.Configuration

/**
 * Classifies TV devices without relying on a single inconsistent Android flag.
 *
 * Older Fire OS releases commonly report a normal UI mode and omit Leanback,
 * while their model identifier still uses Amazon's documented AFT family.
 * Treating those devices as phones launches mobile OAuth in a browser that is
 * difficult to operate with a remote, so keep the checks centralized here.
 */
internal object TelevisionDevicePolicy {
    fun isTelevision(
        uiMode: Int,
        hasLeanback: Boolean,
        hasTelevisionFeature: Boolean,
        manufacturer: String,
        model: String,
    ): Boolean {
        val uiModeType = uiMode and Configuration.UI_MODE_TYPE_MASK
        val isAmazonFireTv =
            manufacturer.equals("Amazon", ignoreCase = true) &&
                model.startsWith("AFT", ignoreCase = true)
        return uiModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            hasLeanback ||
            hasTelevisionFeature ||
            isAmazonFireTv
    }
}
