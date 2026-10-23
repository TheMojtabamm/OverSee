package com.oversea.oversea

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** What Flutter asks the service to start. Lives in memory only, never on disk. */
class StartRequest(
    val configJson: String,
    val label: String,
    /** "all", "allow" (only [apps] use the VPN) or "deny" ([apps] bypass it). */
    val mode: String,
    val apps: List<String>,
    val ipv6: Boolean,
    val mtu: Int,
    val killSwitch: Boolean,
)

/**
 * Process-wide tunnel state shared by the VpnService and the Flutter channel.
 * The config JSON is handed over through [pending] (not through an Intent extra)
 * and cleared as soon as the service takes it.
 */
object TunnelBridge {
    private val main = Handler(Looper.getMainLooper())

    @Volatile var pending: StartRequest? = null

    @Volatile var state: String = "disconnected"
        private set
    @Volatile var message: String? = null
        private set
    @Volatile var up: Long = 0
        private set
    @Volatile var down: Long = 0
        private set
    @Volatile var upRate: Long = 0
        private set
    @Volatile var downRate: Long = 0
        private set

    private var sink: EventChannel.EventSink? = null

    fun attach(s: EventChannel.EventSink?) {
        sink = s
        emit()
    }

    fun takePending(): StartRequest? {
        val p = pending
        pending = null
        return p
    }

    fun setState(s: String, msg: String? = null) {
        state = s
        message = msg
        if (s != "connected") {
            up = 0; down = 0; upRate = 0; downRate = 0
        }
        emit()
    }

    fun addTraffic(dUp: Long, dDown: Long, seconds: Double) {
        up += dUp
        down += dDown
        upRate = (dUp / seconds).toLong()
        downRate = (dDown / seconds).toLong()
        emit()
    }

    fun snapshot(): Map<String, Any?> = mapOf(
        "state" to state,
        "message" to message,
        "up" to up,
        "down" to down,
        "upRate" to upRate,
        "downRate" to downRate,
    )

    private fun emit() {
        val s = sink ?: return
        val snap = snapshot()
        main.post { s.success(snap) }
    }
}
