package com.example.focus_lock

import android.Manifest
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
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
import com.example.focus_lock.database.AppDatabase
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate
import java.util.Calendar

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

                    // ── Screen time (UsageStatsManager) ──────────
                    "getScreenTimeData" -> {
                        if (hasUsageStatsPermission()) {
                            result.success(getScreenTimeData())
                        } else {
                            result.success(mapOf<String, Any>())
                        }
                    }
                    "hasUsageStatsPermission" -> {
                        result.success(hasUsageStatsPermission())
                    }
                    "openUsageStatsSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            })
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("OPEN_SETTINGS_FAILED", e.message, null)
                        }
                    }

                    // ── App open logs (Room DB) ───────────────────
                    "getAppOpenLogs" -> {
                        result.success(getAppOpenLogs())
                    }
                    "getAppOpenCount" -> {
                        val pkg = call.argument<String>("packageName") ?: ""
                        result.success(getAppOpenCount(pkg))
                    }
                    "getAllAppOpenCounts" -> {
                        result.success(getAllAppOpenCounts())
                    }

                    // ── Chrome filter ─────────────────────────────
                    "getChromeFilterStatus" -> {
                        result.success(mapOf(
                            "isActive" to AppBlockingAccessibilityService.isRunning,
                            "blockedKeywordCount" to AppBlockingAccessibilityService.BLOCKED_KEYWORDS.size
                        ))
                    }

                    // ── Discipline state machine ──────────────────
                    "getDisciplineState" -> {
                        result.success(AppBlockingAccessibilityService.currentState.name)
                    }
                    "getRedditTempUnlockRemaining" -> {
                        val remainingMs = AppBlockingAccessibilityService.instance
                            ?.getRedditTempUnlockRemainingMs() ?: 0L
                        result.success(remainingMs / 1000)
                    }

                    // ── Instagram blocker (deterministic module) ──
                    "getInstagramBlockStatus" -> {
                        InstagramBlocker.init(applicationContext)
                        result.success(InstagramBlocker.getStatus())
                    }
                    "getInstagramAttemptCount" -> {
                        InstagramBlocker.init(applicationContext)
                        result.success(InstagramBlocker.getAttemptCount())
                    }
                    "getInstagramTempUnlockRemaining" -> {
                        InstagramBlocker.init(applicationContext)
                        result.success(InstagramBlocker.getTempUnlockRemainingSeconds())
                    }
                    "completeInstagramEmergencyChallenge" -> {
                        InstagramBlocker.init(applicationContext)
                        InstagramBlocker.grantTempUnlock()
                        Log.d(TAG, "Instagram emergency challenge completed — 15min unlock")
                        result.success(true)
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
            val enabledServices = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false

            Log.d(TAG, "Expected component: ${expected.flattenToString()}")
            Log.d(TAG, "Enabled services: $enabledServices")

            TextUtils.SimpleStringSplitter(':').apply { setString(enabledServices) }
                .any { componentString ->
                    val component = ComponentName.unflattenFromString(componentString)
                    component == expected
                }
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
        pushupDetector?.reset()

        // Trigger the accessibility service state machine for 10-min temp unlock
        val svc = AppBlockingAccessibilityService.instance
        if (svc != null) {
            svc.onRedditChallengeCompleted()
            Log.d(TAG, "Redeemed $PUSHUPS_REQUIRED pushups → Reddit temp unlock for 10 min")
        } else {
            Log.w(TAG, "Accessibility service not running — granting extra time via prefs")
            resetIfNewDay()
            val currentExtra = prefs.getLong(REDDIT_EXTRA_MS_KEY, 0L)
            prefs.edit().putLong(REDDIT_EXTRA_MS_KEY, currentExtra + PUSHUP_REWARD_MS).apply()
        }
        return true
    }

    // ── Usage stats helpers ────────────────────────────────────────

    private fun hasUsageStatsPermission(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.e(TAG, "Error checking usage stats permission: ${e.message}")
            false
        }
    }

    private fun getScreenTimeData(): Map<String, Any> {
        val trackedApps = mapOf(
            "com.instagram.android" to "Instagram",
            "com.reddit.frontpage" to "Reddit",
            "com.twitter.android" to "Twitter/X"
        )

        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val calendar = Calendar.getInstance()
        val endTime = calendar.timeInMillis
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startTime = calendar.timeInMillis

        val usageStatsList = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY, startTime, endTime
        )

        val result = mutableMapOf<String, Any>()
        for ((pkg, name) in trackedApps) {
            var screenTimeMs = 0L
            for (stats in usageStatsList) {
                if (stats.packageName == pkg) {
                    screenTimeMs = stats.totalTimeInForeground
                    break
                }
            }
            result[pkg] = mapOf(
                "name" to name,
                "screenTimeMs" to screenTimeMs
            )
        }
        return result
    }

    // ── App open log helpers ───────────────────────────────────────

    private fun getAppOpenLogs(): List<Map<String, String>> {
        return try {
            val db = AppDatabase.getDatabase(applicationContext)
            val today = LocalDate.now().toString()
            val logs = db.appOpenLogDao().getLogsForDate(today)
            logs.map { log ->
                mapOf(
                    "appName" to log.appName,
                    "packageName" to log.packageName,
                    "timestamp" to log.timestamp
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting app open logs: ${e.message}")
            emptyList()
        }
    }

    private fun getAppOpenCount(packageName: String): Int {
        return try {
            val db = AppDatabase.getDatabase(applicationContext)
            val today = LocalDate.now().toString()
            db.appOpenLogDao().getOpenCountForDate(today, packageName)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting open count: ${e.message}")
            0
        }
    }

    private fun getAllAppOpenCounts(): Map<String, Int> {
        return try {
            val db = AppDatabase.getDatabase(applicationContext)
            val today = LocalDate.now().toString()
            val packages = listOf(
                "com.instagram.android",
                "com.reddit.frontpage",
                "com.twitter.android"
            )
            packages.associateWith { pkg ->
                db.appOpenLogDao().getOpenCountForDate(today, pkg)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting all open counts: ${e.message}")
            emptyMap()
        }
    }
}
