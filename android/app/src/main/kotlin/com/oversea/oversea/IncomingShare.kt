package com.oversea.oversea

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodChannel

/**
 * Reads a file/text another app handed to Oversea ("Open with" / Share) and passes the
 * text to Flutter. The content is only text, size-capped, and never executed: Flutter
 * shows a confirmation before importing anything.
 */
class IncomingShare(private val resolver: ContentResolver) {
    private var channel: MethodChannel? = null
    @Volatile private var pending: String? = null

    fun attach(c: MethodChannel) {
        channel = c
        c.setMethodCallHandler { call, result ->
            when (call.method) {
                "take" -> { result.success(pending); pending = null }
                else -> result.notImplemented()
            }
        }
    }

    /** Call from onCreate / onNewIntent. */
    fun handle(intent: Intent?) {
        val text = extract(intent) ?: return
        pending = text
        channel?.invokeMethod("onIncoming", null) // Flutter then calls "take"
    }

    private fun extract(intent: Intent?): String? {
        intent ?: return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let { read(it) }
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (stream != null) read(stream) else intent.getStringExtra(Intent.EXTRA_TEXT)?.take(MAX)
            }
            else -> null
        }
    }

    private fun read(uri: Uri): String? = runCatching {
        // Only content:// (and file:// for old file managers); never follow anything else.
        if (uri.scheme != "content" && uri.scheme != "file") return null
        resolver.openInputStream(uri)?.use { s ->
            val buf = ByteArray(MAX + 1)
            var n = 0
            while (n < buf.size) {
                val r = s.read(buf, n, buf.size - n)
                if (r < 0) break
                n += r
            }
            if (n > MAX) null else String(buf, 0, n, Charsets.UTF_8)
        }
    }.getOrNull()

    companion object {
        const val MAX = 200_000
    }
}
