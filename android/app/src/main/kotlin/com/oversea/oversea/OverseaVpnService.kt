package com.oversea.oversea

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Runs Xray-core behind an Android TUN interface.
 *
 * Xray's `tun` inbound reads/writes packets on the TUN file descriptor itself
 * (it duplicates the fd, so this service keeps ownership and closes it).
 * This app is excluded from its own VPN, so the core's outbound sockets reach the
 * real network instead of looping back into the tunnel.
 */
class OverseaVpnService : VpnService() {

    private val worker = Executors.newSingleThreadExecutor()
    private var stats: ScheduledExecutorService? = null
    private var tun: ParcelFileDescriptor? = null
    private var core: CoreController? = null
    private var killSwitch = false
    @Volatile private var userStop = false
    private var lastLabel = ""

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            userStop = true
            worker.execute { teardown(); stopSelf() }
            return START_NOT_STICKY
        }

        enterForeground(getString(R.string.tunnel_starting))

        val req = TunnelBridge.takePending()
        if (req == null) {
            // Started by the system (Always-on VPN / after a crash) without a config:
            // never leak. Hold a blocking interface until the user reconnects.
            worker.execute { holdBlocked(getString(R.string.tunnel_open_app)) }
            return START_NOT_STICKY
        }
        userStop = false
        worker.execute { start(req) }
        return START_NOT_STICKY
    }

    private fun start(req: StartRequest) {
        TunnelBridge.setState("connecting")
        killSwitch = req.killSwitch
        lastLabel = req.label
        try {
            teardown()
            val pfd = buildTun(req) ?: run {
                fail("VPN permission was revoked")
                return
            }
            tun = pfd

            Libv2ray.initCoreEnv(filesDir.absolutePath, "")
            val c = Libv2ray.newCoreController(object : CoreCallbackHandler {
                override fun startup(): Long = 0
                override fun shutdown(): Long {
                    onCoreStopped()
                    return 0
                }
                override fun onEmitStatus(code: Long, msg: String?): Long = 0
            })
            core = c
            c.startLoop(req.configJson, pfd.fd)

            TunnelBridge.setState("connected")
            updateNotification(getString(R.string.tunnel_connected, req.label))
            startStats()
        } catch (e: Throwable) {
            // Do not echo e.message: it may contain parts of the config.
            fail("Could not start the tunnel (${e.javaClass.simpleName})")
        }
    }

    private fun buildTun(req: StartRequest): ParcelFileDescriptor? {
        val b = Builder()
            .setSession("Oversea")
            .setMtu(req.mtu)
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("1.1.1.1")
            .addDnsServer("1.0.0.1")
            // IPv6 is always routed into the tunnel; with ipv6=false Xray drops it
            // there, so nothing can leak around the VPN over IPv6.
            .addAddress("fdfe:dcba:9876::1", 126)
            .addRoute("::", 0)
        if (req.ipv6) b.addDnsServer("2606:4700:4700::1111")

        val self = packageName
        when {
            req.mode == "allow" && req.apps.any { it != self } ->
                req.apps.filter { it != self }.forEach { runCatching { b.addAllowedApplication(it) } }
            req.mode == "deny" -> {
                req.apps.forEach { runCatching { b.addDisallowedApplication(it) } }
                runCatching { b.addDisallowedApplication(self) }
            }
            else -> runCatching { b.addDisallowedApplication(self) }
        }
        return b.establish()
    }

    /** The core stopped. If the user did not ask for it, that is a dropped connection. */
    private fun onCoreStopped() {
        if (userStop) return
        stopStats()
        if (killSwitch) {
            // Keep the TUN interface up with nothing reading it: all traffic is blackholed.
            TunnelBridge.setState("blocked", "Connection lost — traffic is blocked")
            updateNotification(getString(R.string.tunnel_blocked))
        } else {
            worker.execute { teardown(); stopSelf() }
            TunnelBridge.setState("disconnected", "Connection lost")
        }
    }

    private fun holdBlocked(text: String) {
        try {
            teardown()
            val b = Builder().setSession("Oversea").setMtu(1500)
                .addAddress("172.19.0.1", 30).addRoute("0.0.0.0", 0)
                .addAddress("fdfe:dcba:9876::1", 126).addRoute("::", 0)
            runCatching { b.addDisallowedApplication(packageName) }
            tun = b.establish()
            TunnelBridge.setState("blocked", text)
            updateNotification(text)
        } catch (e: Throwable) {
            fail("Could not hold the kill-switch")
        }
    }

    private fun fail(msg: String) {
        teardown()
        TunnelBridge.setState("error", msg)
        stopSelf()
    }

    private fun teardown() {
        stopStats()
        runCatching { core?.stopLoop() }
        core = null
        runCatching { tun?.close() }
        tun = null
        if (userStop) TunnelBridge.setState("disconnected")
    }

    private fun startStats() {
        val ex = Executors.newSingleThreadScheduledExecutor()
        stats = ex
        ex.scheduleWithFixedDelay({
            val c = core ?: return@scheduleWithFixedDelay
            runCatching {
                var u = 0L
                var d = 0L
                // Format: tag,direction,value;tag,direction,value;  (counters reset on read)
                c.queryAllOutboundTrafficStats().split(";").forEach { row ->
                    val p = row.split(",")
                    if (p.size == 3 && p[0] == "proxy") {
                        val v = p[2].toLongOrNull() ?: 0L
                        if (p[1] == "uplink") u += v else if (p[1] == "downlink") d += v
                    }
                }
                TunnelBridge.addTraffic(u, d, 1.0)
            }
        }, 1, 1, TimeUnit.SECONDS)
    }

    private fun stopStats() {
        stats?.shutdownNow()
        stats = null
    }

    override fun onRevoke() {
        // Another VPN took over, or the user revoked permission in system settings.
        userStop = true
        worker.execute { teardown(); stopSelf() }
    }

    override fun onDestroy() {
        userStop = true
        stopStats()
        runCatching { core?.stopLoop() }
        runCatching { tun?.close() }
        worker.shutdown()
        TunnelBridge.setState("disconnected")
        super.onDestroy()
    }

    // ---- notification ------------------------------------------------------

    private fun enterForeground(text: String) {
        val n = notification(text)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notification(text))
    }

    private fun notification(text: String): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, getString(R.string.tunnel_channel), NotificationManager.IMPORTANCE_LOW)
            )
        }
        val stop = PendingIntent.getService(
            this, 0, Intent(this, OverseaVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val open = PendingIntent.getActivity(
            this, 1, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return b.setSmallIcon(R.drawable.ic_stat_vpn)
            .setContentTitle("Oversea")
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, getString(R.string.tunnel_disconnect), stop).build())
            .build()
    }

    companion object {
        const val ACTION_STOP = "com.oversea.oversea.STOP"
        private const val CHANNEL = "tunnel"
        private const val NOTIF_ID = 1
    }
}
