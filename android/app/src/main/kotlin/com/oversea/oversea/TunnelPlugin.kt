package com.oversea.oversea

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import libv2ray.Libv2ray
import java.util.concurrent.Executors

/** Flutter <-> native bridge for the tunnel. All heavy work happens in [OverseaVpnService]. */
class TunnelPlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {

    // Delay tests block for up to ~12 s each, so they never run on the UI thread.
    private val testPool = Executors.newFixedThreadPool(3)
    private val ui = android.os.Handler(android.os.Looper.getMainLooper())

    private var pendingPrepare: MethodChannel.Result? = null
    private var pendingNotif: MethodChannel.Result? = null

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "oversea/tunnel").setMethodCallHandler(this)
        EventChannel(engine.dartExecutor.binaryMessenger, "oversea/tunnel/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) = TunnelBridge.attach(sink)
                override fun onCancel(args: Any?) = TunnelBridge.attach(null)
            }
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> prepare(result)
            "requestNotifications" -> requestNotifications(result)
            "start" -> start(call, result)
            "stop" -> {
                activity.startService(
                    Intent(activity, OverseaVpnService::class.java).setAction(OverseaVpnService.ACTION_STOP)
                )
                result.success(null)
            }
            "status" -> result.success(TunnelBridge.snapshot())
            "testDelay" -> testDelay(call, result)
            "integrity" -> result.success(
                mapOf(
                    "cert" to IntegrityCheck.signingCertSha256(activity),
                    "flags" to IntegrityCheck.flags(),
                )
            )
            "listApps" -> result.success(listApps())
            "openVpnSettings" -> {
                activity.startActivity(Intent(Settings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ---- permissions -------------------------------------------------------

    private fun prepare(result: MethodChannel.Result) {
        val intent = VpnService.prepare(activity)
        if (intent == null) {
            result.success(true)
            return
        }
        pendingPrepare?.success(false)
        pendingPrepare = result
        activity.startActivityForResult(intent, REQ_VPN)
    }

    private fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingNotif?.success(false)
        pendingNotif = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQ_VPN) return false
        pendingPrepare?.success(resultCode == Activity.RESULT_OK)
        pendingPrepare = null
        return true
    }

    fun onPermissionResult(requestCode: Int, granted: Boolean): Boolean {
        if (requestCode != REQ_NOTIF) return false
        pendingNotif?.success(granted)
        pendingNotif = null
        return true
    }

    /** Measures round-trip through the config's outbound; -1 on failure. */
    private fun testDelay(call: MethodCall, result: MethodChannel.Result) {
        val config = call.argument<String>("config")
        val url = call.argument<String>("url") ?: "https://www.google.com/generate_204"
        if (config.isNullOrEmpty()) {
            result.success(-1L)
            return
        }
        testPool.execute {
            val ms = try {
                Libv2ray.measureOutboundDelay(config, url)
            } catch (e: Throwable) {
                -1L
            }
            ui.post { result.success(ms) }
        }
    }

    // ---- start / apps ------------------------------------------------------

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val config = call.argument<String>("config")
        if (config.isNullOrEmpty()) {
            result.error("bad_args", "config missing", null)
            return
        }
        if (VpnService.prepare(activity) != null) {
            result.error("no_permission", "VPN permission not granted", null)
            return
        }
        TunnelBridge.pending = StartRequest(
            configJson = config,
            label = call.argument<String>("label") ?: "",
            mode = call.argument<String>("mode") ?: "all",
            apps = call.argument<List<String>>("apps") ?: emptyList(),
            ipv6 = call.argument<Boolean>("ipv6") ?: false,
            mtu = call.argument<Int>("mtu") ?: 1500,
            killSwitch = call.argument<Boolean>("killSwitch") ?: false,
        )
        ContextCompat.startForegroundService(activity, Intent(activity, OverseaVpnService::class.java))
        result.success(null)
    }

    /** Launchable apps (needs the LAUNCHER <queries> entry; no QUERY_ALL_PACKAGES). */
    private fun listApps(): List<Map<String, String>> {
        val pm = activity.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(intent, 0)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != activity.packageName }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase() }
            .map { mapOf("package" to it.first, "label" to it.second) }
    }

    companion object {
        const val REQ_VPN = 4101
        const val REQ_NOTIF = 4102
    }
}
