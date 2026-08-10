package dev.animetv.anime_tv.security

import java.net.InetAddress
import java.net.Inet6Address
import java.net.UnknownHostException
import okhttp3.Dns
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NetworkRequestPolicyTest {
    @Test
    fun `accepts only well formed https origins`() {
        assertEquals(
            NetworkRequestPolicy.Origin("https", "stream.example", 443),
            NetworkRequestPolicy.httpsOrigin("HTTPS://Stream.Example/video.mkv"),
        )
        assertEquals(
            NetworkRequestPolicy.Origin("https", "stream.example", 8443),
            NetworkRequestPolicy.httpsOrigin("https://stream.example:8443/video.mkv"),
        )
        assertNull(NetworkRequestPolicy.httpsOrigin("http://stream.example/video.mkv"))
        assertNull(NetworkRequestPolicy.httpsOrigin("file:///data/user/0/app/secrets"))
        assertNull(NetworkRequestPolicy.httpsOrigin("https:///missing-host"))
    }

    @Test
    fun `sanitizes malformed and transport controlled headers`() {
        val result = NetworkRequestPolicy.sanitizeRequestHeaders(
            linkedMapOf(
                "Authorization" to "Bearer safe-value",
                "authorization" to "Bearer replacement",
                "Range" to "bytes=0-10",
                "Host" to "attacker.example",
                "Bad Header" to "value",
                "X-Line" to "safe\r\nInjected: value",
                "Referer" to "https://catalog.example/",
            ),
        )

        assertEquals("Bearer replacement", result["authorization"])
        assertEquals("https://catalog.example/", result["Referer"])
        assertFalse(result.keys.any { it.equals("Range", ignoreCase = true) })
        assertFalse(result.keys.any { it.equals("Host", ignoreCase = true) })
        assertFalse(result.keys.any { it.equals("X-Line", ignoreCase = true) })
    }

    @Test
    fun `credentials are scoped to the original stream origin`() {
        val source = NetworkRequestPolicy.Origin("https", "stream.example", 443)
        val sameOrigin = NetworkRequestPolicy.Origin("https", "stream.example", 443)
        val subtitleOrigin = NetworkRequestPolicy.Origin("https", "subtitles.example", 443)

        assertTrue(
            NetworkRequestPolicy.shouldForwardHeader("Authorization", source, sameOrigin),
        )
        assertFalse(
            NetworkRequestPolicy.shouldForwardHeader("Authorization", source, subtitleOrigin),
        )
        assertFalse(NetworkRequestPolicy.shouldForwardHeader("Cookie", source, subtitleOrigin))
        assertTrue(NetworkRequestPolicy.shouldForwardHeader("Referer", source, subtitleOrigin))
        assertTrue(NetworkRequestPolicy.shouldForwardHeader("User-Agent", source, subtitleOrigin))
    }

    @Test
    fun `redacts urls and credentials from playback diagnostics`() {
        val result = NetworkRequestPolicy.redactNetworkDiagnostic(
            "Failed https://cdn.example/d/account-token/file.mkv?auth=secret " +
                "Authorization: Bearer secret-value, cookie=session-value",
        ).orEmpty()

        assertFalse(result.contains("account-token"))
        assertFalse(result.contains("secret-value"))
        assertFalse(result.contains("session-value"))
        assertTrue(result.contains("https://[redacted]"))
        assertTrue(result.contains("Authorization=[redacted]"))
    }

    @Test
    fun `rejects private special and local network addresses`() {
        listOf(
            "0.0.0.0",
            "10.2.3.4",
            "100.64.0.1",
            "100.127.255.254",
            "127.0.0.1",
            "169.254.10.20",
            "172.16.0.1",
            "172.31.255.254",
            "192.168.1.1",
            "192.0.2.1",
            "198.18.0.1",
            "198.51.100.1",
            "203.0.113.1",
            "224.0.0.1",
            "255.255.255.255",
            "::",
            "::1",
            "fc00::1",
            "fd12:3456::1",
            "fe80::1",
            "fec0::1",
            "ff02::1",
        ).forEach { value ->
            assertFalse(value, NetworkRequestPolicy.isPublicNetworkAddress(numericAddress(value)))
        }

        val mappedLoopbackBytes = ByteArray(16).apply {
            this[10] = 0xFF.toByte()
            this[11] = 0xFF.toByte()
            this[12] = 127
            this[15] = 1
        }
        val mappedLoopback = Inet6Address.getByAddress(null, mappedLoopbackBytes, -1)
        assertFalse(
            "IPv4-mapped IPv6 must not bypass the address policy",
            NetworkRequestPolicy.isPublicNetworkAddress(mappedLoopback),
        )
    }

    @Test
    fun `accepts globally routable ipv4 and ipv6 addresses`() {
        listOf(
            "1.1.1.1",
            "8.8.8.8",
            "93.184.216.34",
            "2001:4860:4860::8888",
            "2606:4700:4700::1111",
        ).forEach { value ->
            assertTrue(value, NetworkRequestPolicy.isPublicNetworkAddress(numericAddress(value)))
        }
    }

    @Test
    fun `dns wrapper removes unsafe answers and fails closed`() {
        val mixedDns = PublicNetworkDns(
            object : Dns {
                override fun lookup(hostname: String): List<InetAddress> = listOf(
                    numericAddress("192.168.1.10"),
                    numericAddress("1.1.1.1"),
                    numericAddress("::1"),
                )
            },
        )
        assertEquals(listOf(numericAddress("1.1.1.1")), mixedDns.lookup("stream.example"))

        val localOnlyDns = PublicNetworkDns(
            object : Dns {
                override fun lookup(hostname: String): List<InetAddress> = listOf(
                    numericAddress("127.0.0.1"),
                    numericAddress("fd00::1"),
                )
            },
        )
        try {
            localOnlyDns.lookup("stream.example")
            throw AssertionError("Expected an unsafe DNS answer to fail closed")
        } catch (_: UnknownHostException) {
            // Expected.
        }
    }

    private fun numericAddress(value: String): InetAddress = InetAddress.getByName(value)
}
