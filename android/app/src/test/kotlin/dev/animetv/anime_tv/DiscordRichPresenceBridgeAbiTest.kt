package dev.animetv.anime_tv

import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DiscordRichPresenceBridgeAbiTest {
    @Test
    fun `native callbacks retain the void static JNI contract`() {
        val bridge = Class.forName(
            "dev.animetv.anime_tv.DiscordRichPresenceBridge",
            false,
            javaClass.classLoader,
        )
        val callbacks = listOf(
            bridge.getDeclaredMethod(
                "onAuthResult",
                Boolean::class.javaPrimitiveType,
                String::class.java,
                String::class.java,
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                String::class.java,
                String::class.java,
            ),
            bridge.getDeclaredMethod(
                "onRefreshResult",
                Boolean::class.javaPrimitiveType,
                String::class.java,
                String::class.java,
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                String::class.java,
                String::class.java,
            ),
            bridge.getDeclaredMethod(
                "onConnectionState",
                String::class.java,
                String::class.java,
            ),
            bridge.getDeclaredMethod(
                "onPresenceResult",
                Boolean::class.javaPrimitiveType,
                String::class.java,
            ),
            bridge.getDeclaredMethod(
                "onRevokeResult",
                Boolean::class.javaPrimitiveType,
                String::class.java,
            ),
            bridge.getDeclaredMethod("onTokenExpiring"),
        )

        callbacks.forEach { callback ->
            assertTrue("${callback.name} must remain static for JNI", Modifier.isStatic(callback.modifiers))
            assertEquals("${callback.name} must return void for JNI", Void.TYPE, callback.returnType)
        }
    }
}
