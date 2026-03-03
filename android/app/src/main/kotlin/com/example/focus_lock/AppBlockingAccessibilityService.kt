package com.example.focus_lock

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.example.focus_lock.database.AppDatabase
import com.example.focus_lock.database.AppOpenLog
import java.text.SimpleDateFormat
import java.time.LocalDate
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class AppBlockingAccessibilityService : AccessibilityService() {
    companion object {
        const val TAG = "AppBlockingA11y"
        const val INSTAGRAM_PACKAGE = "com.instagram.android"
        const val REDDIT_PACKAGE = "com.reddit.frontpage"
        const val TWITTER_PACKAGE = "com.twitter.android"
        const val CHROME_PACKAGE = "com.android.chrome"

        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val LOCK_START_KEY = "flutter.lock_start_time"
        private const val LOCK_DURATION_KEY = "flutter.lock_duration_days"

        // Reddit usage tracking keys
        private const val REDDIT_USAGE_DATE_KEY = "flutter.reddit_usage_date"
        private const val REDDIT_USAGE_MS_KEY = "flutter.reddit_usage_ms"
        private const val REDDIT_EXTRA_MS_KEY = "flutter.reddit_extra_ms"
        private const val REDDIT_DAILY_LIMIT_MS = 60L * 60L * 1000L  // 1 hour

        // Chrome keyword blocking
        private const val CHROME_DEBOUNCE_MS = 3000L
        private const val WARNING_DURATION_MS = 3000L

        // App open logging deduplication
        private const val APP_LOG_DEBOUNCE_MS = 5000L

        val BLOCKED_KEYWORDS = listOf(
            "porn", "fucked", "bang", "onlyfans", "fansly",
            "sex", "nsfw", "xxx", "hentai"
        )

        val TRACKED_PACKAGES = setOf(
            INSTAGRAM_PACKAGE,
            REDDIT_PACKAGE,
            TWITTER_PACKAGE
        )

        @Volatile var isRunning = false
    }

    private lateinit var prefs: SharedPreferences
    private val handler = Handler(Looper.getMainLooper())
    private val dbExecutor = Executors.newSingleThreadExecutor()

    // Reddit time tracking state
    private var redditForegroundSince: Long = 0L
    private var currentForegroundPackage: String? = null

    // Chrome keyword blocking state
    private var lastChromeBlockTime = 0L
    private var isChromeBlocked = false
    private var isWarningShowing = false

    // App open logging deduplication
    private var lastLoggedPackage: String? = null
    private var lastLogTime = 0L

    // ── Lifecycle ─────────────────────────────────────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        isRunning = true
        prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        Log.d(TAG, "Accessibility service CONNECTED")

        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                         AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                         AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_ALL_MASK
            notificationTimeout = 100
            packageNames = null
            flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
        }
        serviceInfo = info
        Log.d(TAG, "ServiceInfo applied — listening for window/content/text changes")
    }

    override fun onInterrupt() {
        Log.w(TAG, "Accessibility service interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        flushRedditUsage()
        handler.removeCallbacksAndMessages(null)
        dbExecutor.shutdown()
        Log.d(TAG, "Accessibility service destroyed")
    }

    // ── Event handling ────────────────────────────────────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        try {
            when (event.eventType) {
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                    val pkg = event.packageName?.toString() ?: return
                    handleWindowStateChanged(pkg)
                }
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
                AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                    val pkg = event.packageName?.toString() ?: return
                    if (pkg == CHROME_PACKAGE) {
                        handleChromeContentChanged(event)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onAccessibilityEvent: ${e.message}")
        }
    }

    // ── Window state (foreground app change) ──────────────────────────

    private fun handleWindowStateChanged(packageName: String) {
        Log.d(TAG, "Window changed → $packageName")

        // ── Track Reddit foreground time ──────────────────────────
        if (currentForegroundPackage == REDDIT_PACKAGE && packageName != REDDIT_PACKAGE) {
            flushRedditUsage()
        }
        if (packageName == REDDIT_PACKAGE && currentForegroundPackage != REDDIT_PACKAGE) {
            redditForegroundSince = System.currentTimeMillis()
            Log.d(TAG, "Reddit timer started")
        }

        // ── Chrome lock: remove overlay when user exits Chrome ────
        if (isChromeBlocked && currentForegroundPackage == CHROME_PACKAGE && packageName != CHROME_PACKAGE) {
            Log.d(TAG, "User left Chrome — removing lock overlay")
            isChromeBlocked = false
            isWarningShowing = false
            handler.removeCallbacksAndMessages(null)
            try { stopService(Intent(applicationContext, DisciplineWarningOverlayService::class.java)) } catch (_: Exception) {}
            try { stopService(Intent(applicationContext, ChromeLockOverlayService::class.java)) } catch (_: Exception) {}
        }

        currentForegroundPackage = packageName

        // ── Log app opens for tracked packages ────────────────────
        if (packageName in TRACKED_PACKAGES) {
            logAppOpen(packageName)
        }

        // ── Instagram: full block during lock period ──────────────
        if (packageName == INSTAGRAM_PACKAGE && isLockActive()) {
            Log.d(TAG, "Instagram blocked — lock active")
            blockApp("instagram")
        }

        // ── Reddit: block after daily limit exceeded ──────────────
        if (packageName == REDDIT_PACKAGE) {
            if (isRedditLimitExceeded()) {
                Log.d(TAG, "Reddit daily limit exceeded — blocking")
                blockApp("reddit")
            }
        }
    }

    // ── Chrome content monitoring (keyword detection) ─────────────────

    private fun handleChromeContentChanged(event: AccessibilityEvent) {
        // Skip if already blocking or warning is showing
        if (isChromeBlocked || isWarningShowing) return

        // Debounce: 3 seconds minimum between triggers
        val now = System.currentTimeMillis()
        if (now - lastChromeBlockTime < CHROME_DEBOUNCE_MS) return

        var keywordFound = false

        // 1. Check event text directly (fast path)
        for (cs in event.text) {
            val text = cs?.toString()?.lowercase(Locale.ROOT) ?: continue
            if (BLOCKED_KEYWORDS.any { text.contains(it) }) {
                keywordFound = true
                break
            }
        }

        // 2. Check content description
        if (!keywordFound) {
            val desc = event.contentDescription?.toString()?.lowercase(Locale.ROOT)
            if (desc != null && BLOCKED_KEYWORDS.any { desc.contains(it) }) {
                keywordFound = true
            }
        }

        // 3. Check source node tree (limited depth for performance)
        if (!keywordFound) {
            val source = try { event.source } catch (_: Exception) { null }
            if (source != null) {
                try {
                    keywordFound = containsBlockedKeyword(source, 0)
                } finally {
                    try { source.recycle() } catch (_: Exception) {}
                }
            }
        }

        if (keywordFound) {
            Log.d(TAG, "Blocked keyword detected in Chrome!")
            triggerChromeBlock()
        }
    }

    /**
     * Recursively scan an AccessibilityNodeInfo tree for blocked keywords.
     * Limited to depth 4 to avoid performance issues.
     */
    private fun containsBlockedKeyword(node: AccessibilityNodeInfo?, depth: Int): Boolean {
        if (node == null || depth > 4) return false

        val text = node.text?.toString()?.lowercase(Locale.ROOT) ?: ""
        val desc = node.contentDescription?.toString()?.lowercase(Locale.ROOT) ?: ""

        if (text.isNotEmpty() && BLOCKED_KEYWORDS.any { text.contains(it) }) return true
        if (desc.isNotEmpty() && BLOCKED_KEYWORDS.any { desc.contains(it) }) return true

        for (i in 0 until node.childCount) {
            val child = try { node.getChild(i) } catch (_: Exception) { null }
            if (child != null) {
                val found = containsBlockedKeyword(child, depth + 1)
                try { child.recycle() } catch (_: Exception) {}
                if (found) return true
            }
        }
        return false
    }

    // ── Chrome blocking trigger ───────────────────────────────────────

    /**
     * When a blocked keyword is detected:
     *  1. Show the discipline warning overlay for 3 seconds.
     *  2. After 3 seconds, close the Chrome tab and show a persistent lock.
     *  3. The lock stays until the user leaves Chrome.
     */
    private fun triggerChromeBlock() {
        if (isWarningShowing || isChromeBlocked) return
        lastChromeBlockTime = System.currentTimeMillis()
        isWarningShowing = true

        // Step 1: Show discipline warning overlay
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(this)
            ) {
                Log.w(TAG, "Overlay permission not granted — performing back only")
                performGlobalAction(GLOBAL_ACTION_BACK)
                isWarningShowing = false
                return
            }

            val warningIntent = Intent(applicationContext, DisciplineWarningOverlayService::class.java)
            startService(warningIntent)
            Log.d(TAG, "Discipline warning overlay shown")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing warning overlay: ${e.message}")
            performGlobalAction(GLOBAL_ACTION_BACK)
            isWarningShowing = false
            return
        }

        // Step 2: After 3 seconds, close tab and show lock
        handler.postDelayed({
            try {
                // Close Chrome tab
                performGlobalAction(GLOBAL_ACTION_BACK)
                Log.d(TAG, "Chrome tab closed via GLOBAL_ACTION_BACK")

                // Dismiss warning overlay
                try {
                    stopService(Intent(applicationContext, DisciplineWarningOverlayService::class.java))
                } catch (_: Exception) {}

                isWarningShowing = false
                isChromeBlocked = true

                // Show persistent lock overlay
                val lockIntent = Intent(applicationContext, ChromeLockOverlayService::class.java)
                startService(lockIntent)
                Log.d(TAG, "Chrome lock overlay shown — will remain until Chrome exits")
            } catch (e: Exception) {
                Log.e(TAG, "Error in post-warning handler: ${e.message}")
                isWarningShowing = false
            }
        }, WARNING_DURATION_MS)
    }

    // ── Blocking logic (Instagram / Reddit) ───────────────────────────

    private fun blockApp(source: String) {
        try {
            performGlobalAction(GLOBAL_ACTION_HOME)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(this)
            ) {
                Log.w(TAG, "Overlay permission not granted — cannot show overlay")
                return
            }

            val intent = Intent(applicationContext, LockScreenOverlayService::class.java)
            intent.putExtra("source", source)
            startService(intent)
            Log.d(TAG, "LockScreenOverlayService started (source=$source)")
        } catch (e: Exception) {
            Log.e(TAG, "Error blocking app: ${e.message}", e)
        }
    }

    // ── App open logging (Room database) ──────────────────────────────

    private fun logAppOpen(packageName: String) {
        val now = System.currentTimeMillis()
        // Dedup: don't log the same app within 5 seconds
        if (packageName == lastLoggedPackage && now - lastLogTime < APP_LOG_DEBOUNCE_MS) return
        lastLoggedPackage = packageName
        lastLogTime = now

        val appName = getAppName(packageName)
        val sdfTimestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
        val sdfDate = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        val timestamp = sdfTimestamp.format(Date(now))
        val date = sdfDate.format(Date(now))

        dbExecutor.execute {
            try {
                val db = AppDatabase.getDatabase(applicationContext)
                db.appOpenLogDao().insert(
                    AppOpenLog(
                        appName = appName,
                        packageName = packageName,
                        timestamp = timestamp,
                        date = date
                    )
                )
                Log.d(TAG, "Logged app open: $appName at $timestamp")
            } catch (e: Exception) {
                Log.e(TAG, "Error logging app open: ${e.message}")
            }
        }
    }

    private fun getAppName(packageName: String): String {
        return when (packageName) {
            INSTAGRAM_PACKAGE -> "Instagram"
            REDDIT_PACKAGE -> "Reddit"
            TWITTER_PACKAGE -> "Twitter/X"
            else -> packageName
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
        Log.d(TAG, "Reddit usage flushed: +${elapsed}ms → total ${prev + elapsed}ms")
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
        }
    }

    private fun getRedditUsedMs(): Long {
        resetIfNewDay()
        var total = prefs.getLong(REDDIT_USAGE_MS_KEY, 0L)
        if (redditForegroundSince > 0L) {
            total += System.currentTimeMillis() - redditForegroundSince
        }
        return total
    }

    private fun isRedditLimitExceeded(): Boolean {
        val extra = prefs.getLong(REDDIT_EXTRA_MS_KEY, 0L)
        val limit = REDDIT_DAILY_LIMIT_MS + extra
        return getRedditUsedMs() >= limit
    }

    // ── Instagram lock state ──────────────────────────────────────────

    private fun isLockActive(): Boolean {
        return try {
            val lockStartStr = prefs.getString(LOCK_START_KEY, null) ?: return false
            val normalized = if (lockStartStr.endsWith("Z")) lockStartStr
                             else lockStartStr + "Z"
            val lockStart = java.time.Instant.parse(normalized).toEpochMilli()
            val lockDays = prefs.getLong(LOCK_DURATION_KEY, 30L)
            val lockEndMillis = lockStart + lockDays * 86_400_000L
            System.currentTimeMillis() < lockEndMillis
        } catch (e: Exception) {
            Log.e(TAG, "Error reading lock state: ${e.message}", e)
            true
        }
    }
}
