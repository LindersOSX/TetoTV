package dev.animetv.anime_tv

import android.content.res.Configuration
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TelevisionDevicePolicyTest {
    @Test
    fun televisionUiModeIsTelevision() {
        assertTrue(
            TelevisionDevicePolicy.isTelevision(
                uiMode = Configuration.UI_MODE_TYPE_TELEVISION,
                hasLeanback = false,
                hasTelevisionFeature = false,
                manufacturer = "Google",
                model = "ADT-3",
            ),
        )
    }

    @Test
    fun leanbackFeatureIsTelevisionEvenWithNormalUiMode() {
        assertTrue(
            TelevisionDevicePolicy.isTelevision(
                uiMode = Configuration.UI_MODE_TYPE_NORMAL,
                hasLeanback = true,
                hasTelevisionFeature = false,
                manufacturer = "Example",
                model = "TV box",
            ),
        )
    }

    @Test
    fun olderFireTvAftModelIsTelevisionWithoutAndroidTvFlags() {
        assertTrue(
            TelevisionDevicePolicy.isTelevision(
                uiMode = Configuration.UI_MODE_TYPE_NORMAL,
                hasLeanback = false,
                hasTelevisionFeature = false,
                manufacturer = "Amazon",
                model = "AFTMM",
            ),
        )
    }

    @Test
    fun amazonTabletAndAndroidPhoneStayMobile() {
        assertFalse(
            TelevisionDevicePolicy.isTelevision(
                uiMode = Configuration.UI_MODE_TYPE_NORMAL,
                hasLeanback = false,
                hasTelevisionFeature = false,
                manufacturer = "Amazon",
                model = "KFMUWI",
            ),
        )
        assertFalse(
            TelevisionDevicePolicy.isTelevision(
                uiMode = Configuration.UI_MODE_TYPE_NORMAL,
                hasLeanback = false,
                hasTelevisionFeature = false,
                manufacturer = "Google",
                model = "Pixel 9",
            ),
        )
    }
}
