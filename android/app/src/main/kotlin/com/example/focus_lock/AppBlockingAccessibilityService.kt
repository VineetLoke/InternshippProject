package com.example.focus_lock

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import java.time.LocalDate

class AppBlockingAccessibilityService : AccessibilityService() {
    companion object {
        const val TAG = "AppBlockingA11y"
        const val INSTAGRAM_PACKAGE = "com.instagram.android"
        const val REDDIT_PACKAGE = "com.reddit.frontpage"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val LOCK_START_KEY = "flutter.lock_start_time"
        private const val LOCK_DURATION_KEY = "flutter.lock_duration_days"

        // Reddit usage tracking keys
        private const val REDDIT_USAGE_DATE_KEY = "flutter.reddit_usage_date"
        private const val REDDIT_USAGE_MS_KEY = "flutter.reddit_usage_ms"
        private const val REDDIT_EXTRA_MS_KEY = "flutter.reddit_extra_ms"
        private const val REDDIT_DAILY_LIMIT_MS = 60L * 60L * 1000L  // 1 hour

        @Volatile var isRunning = false
    }

    private lateinit var prefs: SharedPreferences

    // Reddit time tracking state
    private var redditForegroundSince: Long = 0L
    private var currentForegroundPackage: String? = null

    // ── Lifecycle ─────────────────────────────────────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        isRunning = true
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        Log.d(TAG, "✅ Accessibility service CONNECTED")

        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_ALL_MASK
            notificationTimeout = 100
            packageNames = null
        }
        serviceInfo = info
        Log.d(TAG, "ServiceInfo applied – listening for TYPE_WINDOW_STATE_CHANGED")
    }

    override fun onInterrupt() {
        Log.w(TAG, "Accessibility service interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        // Flush any pending Reddit usage
        flushRedditUsage()
        Log.d(TAG, "Accessibility service destroyed")
    }

    // ── Event handling ────────────────────────────────────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val packageName = event.packageName?.toString() ?: return
            Log.d(TAG, "Window changed → package: $packageName")

            // ── Track Reddit foreground time ──────────────────────────
            if (currentForegroundPackage == REDDIT_PACKAGE && packageName != REDDIT_PACKAGE) {
                // User left Reddit — flush accumulated time
                flushRedditUsage()
            }
            if (packageName == REDDIT_PACKAGE && currentForegroundPackage != REDDIT_PACKAGE) {
                // User entered Reddit — start timer
                redditForegroundSince = System.currentTimeMillis()
                Log.d(TAG, "⏱ Reddit timer started")
            }
            currentForegroundPackage = packageName

            // ── Instagram: full block during lock period ──────────────
            if (packageName == INSTAGRAM_PACKAGE) {
                Log.d(TAG, "🔍 Instagram detected in foreground!")
                if (isLockActive()) {
                    Log.d(TAG, "🔒 Lock is ACTIVE — blocking Instagram")
                    blockApp("instagram")
                } else {
                    Log.d(TAG, "🔓 Lock is NOT active — allowing Instagram")
                }
            }

            // ── Reddit: block after daily limit exceeded ──────────────
            if (packageName == REDDIT_PACKAGE) {
                Log.d(TAG, "🔍 Reddit detected in foreground!")
                if (isRedditLimitExceeded()) {
                    Log.d(TAG, "🔒 Reddit daily limit EXCEEDED — blocking Reddit")
                    blockApp("reddit")
                } else {
                    val remainMs = getRedditRemainingMs()
                    Log.d(TAG, "🔓 Reddit allowed — ${remainMs / 1000}s remaining today")
                }
            }
        }
    }

    // ── Blocking logic ────────────────────────────────────────────────

    private fun blockApp(source: String) {
        try {
            val wentHome = performGlobalAction(GLOBAL_ACTION_HOME)
            Log.d(TAG, "performGlobalAction(HOME) = $wentHome")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(this)
            ) {
                Log.w(TAG, "⚠️ Overlay permission not granted — cannot show overlay")
            } else {
                val intent = Intent(applicationContext, LockScreenOverlayService::class.java)
                intent.putExtra("source", source)
                startService(intent)
                Log.d(TAG, "✅ LockScreenOverlayService started (source=$source)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error blocking app: ${e.message}", e)
        }
    }

    // ── Reddit usage tracking ─────────────────────────────────────────

    private fun flushRedditUsage() {
        if (redditForegroundSince <= 0L) return
        val elapsed = System.currentTimeMillis() - redditForegroundSince
        redditForegroundSince = 0L
        if (elapsed <= 0) return

        resetIfNewDay()
        val prev = prefs.getLong(REDDIT_USAGE_MS_KEY, 0L)
        prefs.edit().putLong(REDDIT_USAGE_MS_KEY, prev + elapsed).apply()
        Log.d(TAG, "⏱ Reddit usage flushed: +${elapsed}ms → total ${prev + elapsed}ms")
    }

    private fun resetIfNewDay() {
        val today = LocalDate.now().toString()
        val storedDate = prefs.getString(REDDIT_USAGE_DATE_KEY, null)
        if (storedDate != today) {
            prefs.edit()
                .putString(REDDIT_USAGE_DATE_KEY, today)
                .putLong(REDDIT_USAGE_MS_KEY, 0L)
                .putLong(REDDIT_EXTRA_MS_KEY, 0L)
                .apply()
            Log.d(TAG, "📅 New day detected — Reddit usage reset")
        }
    }

    private fun getRedditUsedMs(): Long {
        resetIfNewDay()
        var total = prefs.getLong(REDDIT_USAGE_MS_KEY, 0L)
        // Add currently-running session if Reddit is open right now
        if (redditForegroundSince > 0L) {
            total += System.currentTimeMillis() - redditForegroundSince
        }
        return total
    }

    private fun getRedditRemainingMs(): Long {
        val extra = prefs.getLong(REDDIT_EXTRA_MS_KEY, 0L)
        val limit = REDDIT_DAILY_LIMIT_MS + extra
        val remaining = limit - getRedditUsedMs()
        return if (remaining > 0) remaining else 0
    }

    private fun isRedditLimitExceeded(): Boolean {
        val extra = prefs.getLong(REDDIT_EXTRA_MS_KEY, 0L)
        val limit = REDDIT_DAILY_LIMIT_MS + extra
        val used = getRedditUsedMs()
        Log.d(TAG, "Reddit limit check: used=${used}ms, limit=${limit}ms (base=60min + extra=${extra}ms)")
        return used >= limit
    }

    // ── Instagram lock state ──────────────────────────────────────────

    private fun isLockActive(): Boolean {
        return try {
            val lockStartStr = prefs.getString(LOCK_START_KEY, null)
            if (lockStartStr == null) {
                Log.d(TAG, "No lock_start_time in prefs — lock inactive")
                return false
            }
            val normalized = if (lockStartStr.endsWith("Z")) lockStartStr
                             else lockStartStr + "Z"
            val lockStart = java.time.Instant.parse(normalized).toEpochMilli()
            val lockDays = prefs.getLong(LOCK_DURATION_KEY, 30L)
            val lockEndMillis = lockStart + lockDays * 86_400_000L
            val now = System.currentTimeMillis()
            val active = now < lockEndMillis
            Log.d(TAG, "Lock check: start=$lockStartStr, days=$lockDays, active=$active")
            active
        } catch (e: Exception) {
            Log.e(TAG, "Error reading lock state: ${e.message}", e)
            true
        }
    }
}
