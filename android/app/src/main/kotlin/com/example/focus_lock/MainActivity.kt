package com.example.focus_lock

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val TAG = "MainActivity"
        const val CHANNEL = "com.example.focus_lock/app_block"
        const val REQUEST_NOTIFICATION_PERMISSION = 1001
    }

    private var serviceStarted = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessibilityEnabled" -> {
                        val enabled = isOurAccessibilityServiceEnabled()
                        Log.d(TAG, "isAccessibilityEnabled → $enabled")
                        result.success(enabled)
                    }
                    "openAccessibilitySettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("OPEN_SETTINGS_FAILED", e.message, null)
                        }
                    }
                    "startBlocking" -> {
                        Log.d(TAG, "startBlocking called from Flutter")
                        startMonitoringService()
                        result.success(isOurAccessibilityServiceEnabled())
                    }
                    "isServiceRunning" -> {
                        result.success(AppBlockingAccessibilityService.isRunning)
                    }
                    "hasOverlayPermission" -> {
                        val has = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                            Settings.canDrawOverlays(this) else true
                        result.success(has)
                    }
                    "openOverlaySettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    android.net.Uri.parse("package:$packageName")
                                )
                                startActivity(intent)
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("OPEN_OVERLAY_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onStart() {
        super.onStart()
        if (!serviceStarted) {
            requestNotificationPermissionThenStart()
        }
    }

    private fun requestNotificationPermissionThenStart() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this, Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                startMonitoringService()
            } else {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQUEST_NOTIFICATION_PERMISSION
                )
            }
        } else {
            startMonitoringService()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            startMonitoringService()
        }
    }

    private fun startMonitoringService() {
        if (serviceStarted) return
        serviceStarted = true
        try {
            val intent = Intent(this, AppBlockingService::class.java)
            startService(intent)
            Log.d(TAG, "✅ Monitoring service started")
        } catch (e: Exception) {
            Log.e(TAG, "Could not start monitoring service: ${e.message}")
        }
    }

    /**
     * Check whether *our* accessibility service is enabled (not just any).
     * Reads Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES and looks for our
     * component name in the colon-separated list.
     */
    private fun isOurAccessibilityServiceEnabled(): Boolean {
        return try {
            val expected = ComponentName(this, AppBlockingAccessibilityService::class.java)
                .flattenToString() // e.g. "com.example.focus_lock/.AppBlockingAccessibilityService"

            val enabledServices = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false

            Log.d(TAG, "Enabled accessibility services: $enabledServices")

            TextUtils.SimpleStringSplitter(':').apply { setString(enabledServices) }
                .any { componentStr ->
                    ComponentName.unflattenFromString(componentStr)
                        ?.equals(expected) == true
                }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking accessibility: ${e.message}")
            false
        }
    }
}
