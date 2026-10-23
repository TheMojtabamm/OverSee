package com.oversea.oversea

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val tunnel = TunnelPlugin(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Blocks screenshots, screen recording and the Recents thumbnail so a
        // config on screen (or an unlocked QR) cannot be captured by other apps.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tunnel.register(flutterEngine)
    }

    @Deprecated("Needed for VpnService.prepare()")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!tunnel.onActivityResult(requestCode, resultCode)) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        val granted = grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!tunnel.onPermissionResult(requestCode, granted)) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}
