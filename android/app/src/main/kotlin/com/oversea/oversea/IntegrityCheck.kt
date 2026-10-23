package com.oversea.oversea

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest

/**
 * Cheap runtime signals that the app is being tampered with or analysed. None of
 * these is a gate by itself (a determined attacker can hook any single check); the
 * result is mixed into the lock's key derivation and the gate token, so a tainted
 * environment doesn't get an error message to patch out — it just derives the wrong
 * key and is refused by the server.
 */
object IntegrityCheck {
    const val DEBUGGER = 1
    const val FRIDA = 2
    const val XPOSED = 4
    const val ROOT_HINT = 8

    fun signingCertSha256(ctx: Context): String? = runCatching {
        val pm = ctx.packageManager
        val certs = if (Build.VERSION.SDK_INT >= 28) {
            val info = pm.getPackageInfo(ctx.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            val si = info.signingInfo ?: return null
            if (si.hasMultipleSigners()) si.apkContentsSigners else si.signingCertificateHistory
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(ctx.packageName, PackageManager.GET_SIGNATURES).signatures
        }
        val c = certs?.firstOrNull() ?: return null
        MessageDigest.getInstance("SHA-256").digest(c.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }.getOrNull()

    fun flags(): Int {
        var f = 0
        if (debugger()) f = f or DEBUGGER
        if (frida()) f = f or FRIDA
        if (xposed()) f = f or XPOSED
        if (rootHint()) f = f or ROOT_HINT
        return f
    }

    private fun debugger(): Boolean {
        if (Debug.isDebuggerConnected() || Debug.waitingForDebugger()) return true
        return runCatching {
            File("/proc/self/status").readLines()
                .firstOrNull { it.startsWith("TracerPid:") }
                ?.substringAfter(":")?.trim()?.toIntOrNull()?.let { it != 0 } ?: false
        }.getOrDefault(false)
    }

    private fun frida(): Boolean {
        // Libraries / threads that frida-gum injects into the process.
        val inMaps = runCatching {
            File("/proc/self/maps").useLines { lines ->
                lines.any { it.contains("frida", ignoreCase = true) || it.contains("gum-js-loop", ignoreCase = true) }
            }
        }.getOrDefault(false)
        if (inMaps) return true
        val thread = runCatching {
            File("/proc/self/task").listFiles()?.any { t ->
                File(t, "comm").readText().trim().let { it == "gum-js-loop" || it.startsWith("frida") }
            } ?: false
        }.getOrDefault(false)
        if (thread) return true
        // frida-server's default TCP port, reachable only if it is running.
        return runCatching {
            Socket().use { it.connect(InetSocketAddress("127.0.0.1", 27042), 120); true }
        }.getOrDefault(false)
    }

    private fun xposed(): Boolean = runCatching {
        Class.forName("de.robv.android.xposed.XposedBridge"); true
    }.getOrDefault(false) || runCatching {
        File("/proc/self/maps").useLines { l -> l.any { it.contains("XposedBridge", true) || it.contains("lsposed", true) } }
    }.getOrDefault(false)

    /** Weak signal only (many legitimate custom ROMs trip it); it is reported, never enforced alone. */
    private fun rootHint(): Boolean = listOf("/system/bin/su", "/system/xbin/su", "/sbin/su", "/system/app/Superuser.apk")
        .any { File(it).exists() }
}
