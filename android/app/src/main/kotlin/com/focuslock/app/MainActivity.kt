package com.focuslock.app

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.focuslock.app/methods"
    private val PREFS_NAME = "focuslock_prefs"
    private val KEY_INSTAGRAM_BLOCKED = "instagram_blocked"
    private val KEY_UNLOCK_TIMESTAMP = "temp_unlock_timestamp"
    private val UNLOCK_DURATION_MS = 10 * 60 * 1000L // 10 minutes

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessibilityEnabled" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                "canDrawOverlays" -> {
                    result.success(canDrawOverlays())
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    }
                    result.success(true)
                }
                "isInstagramBlocked" -> {
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    result.success(prefs.getBoolean(KEY_INSTAGRAM_BLOCKED, true))
                }
                "setInstagramBlocked" -> {
                    val blocked = call.argument<Boolean>("blocked") ?: true
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    prefs.edit().putBoolean(KEY_INSTAGRAM_BLOCKED, blocked).apply()
                    // Update the accessibility service state
                    AppBlockerAccessibilityService.isBlockingEnabled = blocked
                    result.success(true)
                }
                "grantTempUnlock" -> {
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    val unlockUntil = System.currentTimeMillis() + UNLOCK_DURATION_MS
                    prefs.edit().putLong(KEY_UNLOCK_TIMESTAMP, unlockUntil).apply()
                    // Update the accessibility service state
                    AppBlockerAccessibilityService.tempUnlockUntil = unlockUntil
                    result.success(true)
                }
                "getTempUnlockRemaining" -> {
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    val unlockUntil = prefs.getLong(KEY_UNLOCK_TIMESTAMP, 0L)
                    val remaining = unlockUntil - System.currentTimeMillis()
                    result.success(if (remaining > 0) (remaining / 1000).toInt() else 0)
                }
                "getInitialRoute" -> {
                    // Check if opened via deep link for pushup challenge
                    val data = intent?.data
                    if (data != null && data.scheme == "focuslock" && data.host == "pushup-challenge") {
                        result.success("/pushup-challenge")
                    } else {
                        result.success(null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val service = "${packageName}/${packageName}.AppBlockerAccessibilityService"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabledServices.contains(service)
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true // Pre-Marshmallow doesn't need this permission
        }
    }

    override fun onResume() {
        super.onResume()
        // Sync SharedPreferences state to the service companion object
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        AppBlockerAccessibilityService.isBlockingEnabled = prefs.getBoolean(KEY_INSTAGRAM_BLOCKED, true)
        AppBlockerAccessibilityService.tempUnlockUntil = prefs.getLong(KEY_UNLOCK_TIMESTAMP, 0L)
    }
}
