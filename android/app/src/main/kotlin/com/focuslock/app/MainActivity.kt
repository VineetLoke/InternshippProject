package com.focuslock.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.focuslock.app/methods"
        private const val PREFS_NAME = "focuslock_prefs"
    }

    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == "OPEN_PUSHUP_CHALLENGE") {
            Log.d("FocusLockMain", "Handling pushup challenge intent")
            methodChannel?.invokeMethod("navigateToPushupChallenge", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            when (call.method) {
                "isAccessibilityEnabled" -> {
                    result.success(isAccessibilityServiceEnabled())
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(null)
                }
                "canDrawOverlays" -> {
                    result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    })
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "isInstagramBlocked" -> {
                    result.success(prefs.getBoolean("instagram_blocked", true))
                }
                "setInstagramBlocked" -> {
                    val blocked = call.argument<Boolean>("blocked") ?: true
                    prefs.edit().putBoolean("instagram_blocked", blocked).apply()
                    result.success(null)
                }
                "grantTempUnlock" -> {
                    prefs.edit().putLong("temp_unlock_timestamp", System.currentTimeMillis()).apply()
                    result.success(null)
                }
                "getTempUnlockRemaining" -> {
                    val timestamp = prefs.getLong("temp_unlock_timestamp", 0L)
                    val current = System.currentTimeMillis()
                    val diff = (timestamp + 600000L) - current // 10 minutes = 600000ms
                    val remainingSeconds = if (diff > 0) (diff / 1000L).toInt() else 0
                    result.success(remainingSeconds)
                }
                "openPushupChallenge" -> {
                    val intent = Intent(this, MainActivity::class.java).apply {
                        action = "OPEN_PUSHUP_CHALLENGE"
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    }
                    startActivity(intent)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val colonSplitter = enabledServices.split(":")
        val expectedService = "$packageName/${AppBlockerAccessibilityService::class.java.canonicalName}"
        val expectedServiceAlt = "$packageName/.AppBlockerAccessibilityService"
        
        return colonSplitter.any {
            it.equals(expectedService, ignoreCase = true) || it.equals(expectedServiceAlt, ignoreCase = true)
        }
    }
}
