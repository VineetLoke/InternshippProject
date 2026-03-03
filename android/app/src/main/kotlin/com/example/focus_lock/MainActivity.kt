package com.example.focus_lock

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate

class MainActivity : FlutterActivity() {
    companion object {
        const val TAG = "MainActivity"
        const val CHANNEL = "com.example.focus_lock/app_block"
        const val PUSHUP_EVENT_CHANNEL = "com.example.focus_lock/pushup_events"
        const val REQUEST_NOTIFICATION_PERMISSION = 1001
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val REDDIT_USAGE_DATE_KEY = "flutter.reddit_usage_date"
        private const val REDDIT_USAGE_MS_KEY = "flutter.reddit_usage_ms"
        private const val REDDIT_EXTRA_MS_KEY = "flutter.reddit_extra_ms"
        private const val REDDIT_DAILY_LIMIT_MS = 60L * 60L * 1000L
        private const val PUSHUP_REWARD_MS = 10L * 60L * 1000L  // 10 minutes
        private const val PUSHUPS_REQUIRED = 100
    }

    private var serviceStarted = false
    private var pushupDetector: PushupDetectorService? = null
    private var pushupEventSink: EventChannel.EventSink? = null
    private lateinit var prefs: SharedPreferences

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // ── Method channel ────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // ── Accessibility ──────────────────────────────────
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

                    // ── Reddit usage ──────────────────────────────────
                    "getRedditUsageStatus" -> {
                        result.success(getRedditUsageStatus())
                    }
                    "getRedditRemainingSeconds" -> {
                        result.success(getRedditRemainingSeconds())
                    }

                    // ── Pushup detection ──────────────────────────────
                    "startPushupDetection" -> {
                        val started = startPushupDetection()
                        result.success(started)
                    }
                    "stopPushupDetection" -> {
                        stopPushupDetection()
                        result.success(null)
                    }
                    "getPushupCount" -> {
                        result.success(pushupDetector?.getCount() ?: 0)
                    }
                    "resetPushupCount" -> {
                        pushupDetector?.reset()
                        result.success(null)
                    }
                    "redeemPushups" -> {
                        val redeemed = redeemPushupsForRedditTime()
                        result.success(redeemed)
                    }

                    else -> result.notImplemented()
                }
            }

        // ── Event channel for live pushup count stream ────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PUSHUP_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    pushupEventSink = events
                    Log.d(TAG, "Pushup event stream LISTEN")
                }
                override fun onCancel(arguments: Any?) {
                    pushupEventSink = null
                    Log.d(TAG, "Pushup event stream CANCEL")
                }
            })
    }

    override fun onStart() {
        super.onStart()
        if (!serviceStarted) {
            requestNotificationPermissionThenStart()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopPushupDetection()
    }

    // ── Service startup ───────────────────────────────────────────────

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

    // ── Accessibility check ───────────────────────────────────────────

    private fun isOurAccessibilityServiceEnabled(): Boolean {
        return try {
            val expected = ComponentName(this, AppBlockingAccessibilityService::class.java)
                .flattenToString()
            val enabledServices = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            TextUtils.SimpleStringSplitter(':').apply { setString(enabledServices) }
                .any { ComponentName.unflattenFromString(it)?.equals(expected) == true }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking accessibility: ${e.message}")
            false
        }
    }

    // ── Reddit usage helpers ──────────────────────────────────────────

    private fun resetIfNewDay() {
        val today = LocalDate.now().toString()
        val stored = prefs.getString(REDDIT_USAGE_DATE_KEY, null)
        if (stored != today) {
            prefs.edit()
                .putString(REDDIT_USAGE_DATE_KEY, today)
                .putLong(REDDIT_USAGE_MS_KEY, 0L)
                .putLong(REDDIT_EXTRA_MS_KEY, 0L)
                .apply()
        }
    }

    private fun getRedditRemainingSeconds(): Long {
        resetIfNewDay()
        val used = prefs.getLong(REDDIT_USAGE_MS_KEY, 0L)
        val extra = prefs.getLong(REDDIT_EXTRA_MS_KEY, 0L)
        val limit = REDDIT_DAILY_LIMIT_MS + extra
        val remaining = limit - used
        return if (remaining > 0) remaining / 1000 else 0
    }

    private fun getRedditUsageStatus(): Map<String, Any> {
        resetIfNewDay()
        val used = prefs.getLong(REDDIT_USAGE_MS_KEY, 0L)
        val extra = prefs.getLong(REDDIT_EXTRA_MS_KEY, 0L)
        val limit = REDDIT_DAILY_LIMIT_MS + extra
        return mapOf(
            "usedSeconds" to (used / 1000),
            "limitSeconds" to (limit / 1000),
            "remainingSeconds" to (if (limit > used) (limit - used) / 1000 else 0),
            "isLimitReached" to (used >= limit),
            "extraMinutesEarned" to (extra / 60000)
        )
    }

    // ── Pushup detection ──────────────────────────────────────────────

    private fun startPushupDetection(): Boolean {
        if (pushupDetector == null) {
            pushupDetector = PushupDetectorService(this)
        }
        pushupDetector!!.reset()
        pushupDetector!!.onPushupCount = { count ->
            Log.d(TAG, "💪 Pushup count update: $count")
            runOnUiThread {
                pushupEventSink?.success(count)
            }
        }
        pushupDetector!!.onError = { error ->
            runOnUiThread {
                pushupEventSink?.error("SENSOR_ERROR", error, null)
            }
        }
        val started = pushupDetector!!.start()
        Log.d(TAG, "Pushup detection start result: $started")
        return started
    }

    private fun stopPushupDetection() {
        pushupDetector?.stop()
        Log.d(TAG, "Pushup detection stopped")
    }

    private fun redeemPushupsForRedditTime(): Boolean {
        val count = pushupDetector?.getCount() ?: 0
        if (count < PUSHUPS_REQUIRED) {
            Log.d(TAG, "Cannot redeem — only $count/$PUSHUPS_REQUIRED pushups")
            return false
        }
        resetIfNewDay()
        val currentExtra = prefs.getLong(REDDIT_EXTRA_MS_KEY, 0L)
        prefs.edit().putLong(REDDIT_EXTRA_MS_KEY, currentExtra + PUSHUP_REWARD_MS).apply()
        pushupDetector?.reset()
        Log.d(TAG, "✅ Redeemed $PUSHUPS_REQUIRED pushups → +10 min Reddit time")
        return true
    }
}
