package com.example.focus_lock

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import com.example.focus_lock.database.AppDatabase
import com.example.focus_lock.database.AppOpenLog
import java.text.SimpleDateFormat
import java.time.LocalDate
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.regex.Pattern

class AppBlockingAccessibilityService : AccessibilityService() {
    companion object {
        const val TAG = "AppBlockingA11y"
        const val INSTAGRAM_PACKAGE = "com.instagram.android"
        const val REDDIT_PACKAGE = "com.reddit.frontpage"
        const val TWITTER_PACKAGE = "com.twitter.android"
        const val CHROME_PACKAGE = "com.android.chrome"
        const val FOCUS_LOCK_PACKAGE = "com.example.focus_lock"

        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val LOCK_START_KEY = "flutter.lock_start_time"
        private const val LOCK_DURATION_KEY = "flutter.lock_duration_days"

        // Reddit usage tracking keys
        private const val REDDIT_USAGE_DATE_KEY = "flutter.reddit_usage_date"
        private const val REDDIT_USAGE_MS_KEY = "flutter.reddit_usage_ms"
        private const val REDDIT_EXTRA_MS_KEY = "flutter.reddit_extra_ms"
        private const val REDDIT_DAILY_LIMIT_MS = 60L * 60L * 1000L  // 1 hour

        // Reddit temporary unlock keys
        private const val REDDIT_TEMP_UNLOCK_START_KEY = "flutter.reddit_temp_unlock_start"
        private const val REDDIT_TEMP_UNLOCK_DURATION_MS = 10L * 60L * 1000L  // 10 minutes

        // Chrome keyword blocking
        private const val CHROME_DEBOUNCE_MS = 3000L
        private const val WARNING_DURATION_MS = 3000L

        // App open logging deduplication
        private const val APP_LOG_DEBOUNCE_MS = 5000L

        // Overlay safety: auto-remove if stuck
        private const val OVERLAY_MAX_STUCK_MS = 10_000L

        // Emergency bypass: volume up 3x within 2 seconds
        private const val EMERGENCY_VOLUME_PRESSES = 3
        private const val EMERGENCY_WINDOW_MS = 2000L

        // ── Comprehensive blocked keyword list ────────────────────
        // Core explicit terms
        private val EXACT_KEYWORDS = listOf(
            "porn", "pornhub", "pornography", "pornographic",
            "xxx", "xvideos", "xnxx", "redtube", "youporn", "tube8",
            "hentai", "nsfw", "adultvideo", "adultvideos", "adultcontent",
            "sexvideo", "sexvideos", "pornvideo", "pornvideos",
            // Platform related
            "onlyfans", "fansly", "chaturbate", "camgirl", "camgirls",
            "camshow", "webcamgirls", "camsite", "adultcams", "livecams",
            // Explicit action terms
            "blowjob", "handjob", "anal", "milf", "threesome",
            "orgy", "deepthroat", "cumshot", "creampie", "hardcore", "softcore",
            // Adult industry terms
            "escort", "escorts", "escortservice", "adultdating",
            "hookup", "adultchat", "sexchat", "dirtychat", "adultstream",
            // Fetish / category terms
            "bdsm", "fetish", "kink", "kinky", "dominatrix", "submissive",
            "latex", "leatherfetish", "roleplaysex", "erotic", "rule34"
        )

        // Terms that need word-boundary matching to avoid false positives
        // (e.g., "sex" should not match "Sussex", "Sexton", "Asexual", "Essex")
        private val BOUNDARY_KEYWORDS = listOf(
            "sex", "sexual", "sexy", "fuck", "fucking", "fucked"
        )

        // Compile regex patterns for matching
        // Word boundary patterns: match only when surrounded by non-word chars
        private val BOUNDARY_REGEX: Pattern = run {
            val joined = BOUNDARY_KEYWORDS.joinToString("|") { Pattern.quote(it) }
            Pattern.compile("(?:^|\\W)($joined)(?:\\W|$)", Pattern.CASE_INSENSITIVE)
        }

        // Exact keyword matching (substring match is fine for these long terms)
        private val EXACT_REGEX: Pattern = run {
            val joined = EXACT_KEYWORDS.joinToString("|") { Pattern.quote(it) }
            Pattern.compile("($joined)", Pattern.CASE_INSENSITIVE)
        }

        // Pattern-based detection for prefix patterns
        private val PATTERN_REGEX: Pattern = Pattern.compile(
            "(?:^|\\W)(porn\\w*|sex(?!ton|tant|tet|tile|tup)\\w+|xxx\\w*|hentai\\w*|cam(?:girl|boy|show|site|model|live|stream)\\w*)(?:\\W|$)",
            Pattern.CASE_INSENSITIVE
        )

        // All keywords combined for getChromeFilterStatus
        val BLOCKED_KEYWORDS: List<String> = EXACT_KEYWORDS + BOUNDARY_KEYWORDS

        val TRACKED_PACKAGES = setOf(
            INSTAGRAM_PACKAGE,
            REDDIT_PACKAGE,
            TWITTER_PACKAGE
        )

        @Volatile var isRunning = false

        // State machine — shared so Flutter can read it
        @Volatile var currentState: DisciplineState = DisciplineState.IDLE

        // Singleton reference for inter-service communication
        @Volatile var instance: AppBlockingAccessibilityService? = null
    }

    private lateinit var prefs: SharedPreferences
    private val handler = Handler(Looper.getMainLooper())
    private val dbExecutor = Executors.newSingleThreadExecutor()

    // Reddit time tracking state
    private var redditForegroundSince: Long = 0L
    private var currentForegroundPackage: String? = null

    // Chrome keyword blocking state
    private var lastChromeBlockTime = 0L

    // App open logging deduplication
    private var lastLoggedPackage: String? = null
    private var lastLogTime = 0L

    // Overlay safety watchdog
    private var overlayShownAt = 0L
    private val overlayWatchdog = Runnable { checkOverlaySafety() }

    // Emergency bypass — volume up tracking
    private var volumeUpTimes = mutableListOf<Long>()

    // Reddit temp unlock timer
    private val redditLockRunnable = Runnable { onRedditTempUnlockExpired() }

    // ── Lifecycle ─────────────────────────────────────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        isRunning = true
        instance = this
        currentState = DisciplineState.IDLE
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

        // Check if Reddit temp unlock is still active from a previous session
        restoreRedditTempUnlock()

        Log.d(TAG, "ServiceInfo applied — listening for window/content/text changes")
    }

    override fun onInterrupt() {
        Log.w(TAG, "Accessibility service interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        instance = null
        currentState = DisciplineState.IDLE
        flushRedditUsage()
        handler.removeCallbacksAndMessages(null)
        dbExecutor.shutdown()
        Log.d(TAG, "Accessibility service destroyed")
    }

    // ── Emergency bypass via hardware key ─────────────────────────────

    override fun onKeyEvent(event: KeyEvent?): Boolean {
        if (event == null) return super.onKeyEvent(event)

        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP && event.action == KeyEvent.ACTION_DOWN) {
            val now = System.currentTimeMillis()
            volumeUpTimes.add(now)
            // Remove presses older than the window
            volumeUpTimes.removeAll { now - it > EMERGENCY_WINDOW_MS }

            if (volumeUpTimes.size >= EMERGENCY_VOLUME_PRESSES) {
                Log.d(TAG, "EMERGENCY BYPASS triggered — Volume Up x$EMERGENCY_VOLUME_PRESSES")
                volumeUpTimes.clear()
                emergencyReset()
            }
        }
        return super.onKeyEvent(event)
    }

    /**
     * Emergency reset: remove all overlays and return to IDLE.
     * This prevents the device from ever becoming unusable.
     */
    private fun emergencyReset() {
        Log.w(TAG, "Emergency reset — removing all overlays, state → IDLE")
        handler.removeCallbacksAndMessages(null)
        currentState = DisciplineState.IDLE

        try { stopService(Intent(applicationContext, DisciplineWarningOverlayService::class.java)) } catch (_: Exception) {}
        try { stopService(Intent(applicationContext, ChromeLockOverlayService::class.java)) } catch (_: Exception) {}
        try { stopService(Intent(applicationContext, LockScreenOverlayService::class.java)) } catch (_: Exception) {}

        overlayShownAt = 0L
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
        Log.d(TAG, "Window changed → $packageName (state=$currentState)")

        // ── Track Reddit foreground time ──────────────────────────
        if (currentForegroundPackage == REDDIT_PACKAGE && packageName != REDDIT_PACKAGE) {
            flushRedditUsage()
        }
        if (packageName == REDDIT_PACKAGE && currentForegroundPackage != REDDIT_PACKAGE) {
            redditForegroundSince = System.currentTimeMillis()
            Log.d(TAG, "Reddit timer started")
        }

        // ── Overlay safety: auto-remove when leaving blocked app ──
        if (packageName != CHROME_PACKAGE && packageName != REDDIT_PACKAGE && packageName != FOCUS_LOCK_PACKAGE) {
            when (currentState) {
                DisciplineState.WARNING_DISPLAYED,
                DisciplineState.LOCK_ACTIVE -> {
                    Log.d(TAG, "User left blocked app — cleaning up overlays, state → IDLE")
                    cleanupAllOverlays()
                    transitionTo(DisciplineState.IDLE)
                }
                DisciplineState.REDDIT_LOCKED -> {
                    Log.d(TAG, "User left Reddit context — cleaning up Reddit overlay, state → IDLE")
                    try { stopService(Intent(applicationContext, LockScreenOverlayService::class.java)) } catch (_: Exception) {}
                    transitionTo(DisciplineState.IDLE)
                }
                else -> { /* no-op */ }
            }
        }

        // ── Chrome lock: remove overlay when user exits Chrome ────
        if (currentState == DisciplineState.LOCK_ACTIVE &&
            currentForegroundPackage == CHROME_PACKAGE &&
            packageName != CHROME_PACKAGE
        ) {
            Log.d(TAG, "User left Chrome — removing lock overlay")
            cleanupAllOverlays()
            transitionTo(DisciplineState.IDLE)
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

        // ── Reddit: FULL BLOCK with pushup challenge unlock ───────
        if (packageName == REDDIT_PACKAGE) {
            handleRedditForeground()
        }
    }

    // ── Reddit full blocking logic ────────────────────────────────────

    /**
     * Reddit is fully blocked. User must complete 100 pushups to earn
     * 10 minutes of temporary access. Once the timer expires, it re-locks.
     */
    private fun handleRedditForeground() {
        when (currentState) {
            DisciplineState.REDDIT_TEMP_UNLOCK -> {
                // Check if temp unlock has expired
                val start = prefs.getLong(REDDIT_TEMP_UNLOCK_START_KEY, 0L)
                val elapsed = System.currentTimeMillis() - start
                if (elapsed >= REDDIT_TEMP_UNLOCK_DURATION_MS) {
                    Log.d(TAG, "Reddit temp unlock EXPIRED — re-locking")
                    onRedditTempUnlockExpired()
                } else {
                    Log.d(TAG, "Reddit temp unlock active — ${(REDDIT_TEMP_UNLOCK_DURATION_MS - elapsed) / 1000}s remaining")
                }
            }
            DisciplineState.REDDIT_CHALLENGE_ACTIVE -> {
                // User switched back to Reddit during challenge — re-block
                Log.d(TAG, "Reddit opened during challenge — blocking")
                blockReddit()
            }
            DisciplineState.REDDIT_LOCKED -> {
                // Already locked, ensure overlay is showing
                Log.d(TAG, "Reddit locked — ensuring overlay")
                blockReddit()
            }
            else -> {
                // Any other state: lock Reddit
                Log.d(TAG, "Reddit opened — blocking (full block active)")
                blockReddit()
            }
        }
    }

    private fun blockReddit() {
        transitionTo(DisciplineState.REDDIT_LOCKED)
        try {
            performGlobalAction(GLOBAL_ACTION_HOME)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(this)
            ) {
                Log.w(TAG, "Overlay permission not granted")
                return
            }

            val intent = Intent(applicationContext, LockScreenOverlayService::class.java)
            intent.putExtra("source", "reddit")
            startService(intent)
            overlayShownAt = System.currentTimeMillis()
            startOverlayWatchdog()
            Log.d(TAG, "Reddit lock overlay shown")
        } catch (e: Exception) {
            Log.e(TAG, "Error blocking Reddit: ${e.message}", e)
        }
    }

    /**
     * Called by MainActivity when user starts the pushup challenge.
     */
    fun onRedditChallengeStarted() {
        if (currentState == DisciplineState.REDDIT_LOCKED) {
            transitionTo(DisciplineState.REDDIT_CHALLENGE_ACTIVE)
            try { stopService(Intent(applicationContext, LockScreenOverlayService::class.java)) } catch (_: Exception) {}
            Log.d(TAG, "Reddit challenge started — overlay removed")
        }
    }

    /**
     * Called by MainActivity when user completes 100 pushups.
     * Grants 10 minutes of Reddit access.
     */
    fun onRedditChallengeCompleted() {
        transitionTo(DisciplineState.REDDIT_TEMP_UNLOCK)
        val now = System.currentTimeMillis()
        prefs.edit().putLong(REDDIT_TEMP_UNLOCK_START_KEY, now).apply()

        // Schedule re-lock after 10 minutes
        handler.removeCallbacks(redditLockRunnable)
        handler.postDelayed(redditLockRunnable, REDDIT_TEMP_UNLOCK_DURATION_MS)

        Log.d(TAG, "Reddit temp unlock granted — 10 minutes starting now")
    }

    /**
     * Called when the 10-minute Reddit access window expires.
     */
    private fun onRedditTempUnlockExpired() {
        Log.d(TAG, "Reddit temp unlock expired")
        prefs.edit().remove(REDDIT_TEMP_UNLOCK_START_KEY).apply()
        handler.removeCallbacks(redditLockRunnable)

        // If Reddit is currently in foreground, block it
        if (currentForegroundPackage == REDDIT_PACKAGE) {
            blockReddit()
        } else {
            transitionTo(DisciplineState.IDLE)
        }
    }

    /**
     * Restore Reddit temp unlock if it was active before service restart.
     */
    private fun restoreRedditTempUnlock() {
        val start = prefs.getLong(REDDIT_TEMP_UNLOCK_START_KEY, 0L)
        if (start > 0L) {
            val elapsed = System.currentTimeMillis() - start
            if (elapsed < REDDIT_TEMP_UNLOCK_DURATION_MS) {
                transitionTo(DisciplineState.REDDIT_TEMP_UNLOCK)
                val remaining = REDDIT_TEMP_UNLOCK_DURATION_MS - elapsed
                handler.postDelayed(redditLockRunnable, remaining)
                Log.d(TAG, "Restored Reddit temp unlock — ${remaining / 1000}s remaining")
            } else {
                prefs.edit().remove(REDDIT_TEMP_UNLOCK_START_KEY).apply()
            }
        }
    }

    /**
     * Check remaining Reddit temp unlock seconds. Called from Flutter.
     */
    fun getRedditTempUnlockRemainingMs(): Long {
        val start = prefs.getLong(REDDIT_TEMP_UNLOCK_START_KEY, 0L)
        if (start <= 0L) return 0L
        val elapsed = System.currentTimeMillis() - start
        val remaining = REDDIT_TEMP_UNLOCK_DURATION_MS - elapsed
        return if (remaining > 0) remaining else 0L
    }

    // ── Chrome content monitoring (keyword detection) ─────────────────

    private fun handleChromeContentChanged(event: AccessibilityEvent) {
        // Skip if in a blocking state already
        if (currentState == DisciplineState.WARNING_DISPLAYED ||
            currentState == DisciplineState.LOCK_ACTIVE) return

        // Debounce: 3 seconds minimum between triggers
        val now = System.currentTimeMillis()
        if (now - lastChromeBlockTime < CHROME_DEBOUNCE_MS) return

        var keywordFound = false

        // 1. Check event text directly (fast path)
        for (cs in event.text) {
            val text = cs?.toString() ?: continue
            if (matchesBlockedContent(text)) {
                keywordFound = true
                break
            }
        }

        // 2. Check content description
        if (!keywordFound) {
            val desc = event.contentDescription?.toString()
            if (desc != null && matchesBlockedContent(desc)) {
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
     * Check text against blocked content patterns using regex with word boundaries.
     * Avoids false positives like Sussex, Sexton, Asexual, Essex.
     */
    private fun matchesBlockedContent(text: String): Boolean {
        if (text.isBlank()) return false

        // Check exact keywords (substring match — these are long enough to be unambiguous)
        if (EXACT_REGEX.matcher(text).find()) return true

        // Check boundary keywords with word boundaries to avoid false positives
        if (BOUNDARY_REGEX.matcher(text).find()) return true

        // Check pattern prefixes
        if (PATTERN_REGEX.matcher(text).find()) return true

        return false
    }

    /**
     * Recursively scan an AccessibilityNodeInfo tree for blocked keywords.
     * Limited to depth 4 to avoid performance issues.
     */
    private fun containsBlockedKeyword(node: AccessibilityNodeInfo?, depth: Int): Boolean {
        if (node == null || depth > 4) return false

        val text = node.text?.toString() ?: ""
        val desc = node.contentDescription?.toString() ?: ""

        if (text.isNotEmpty() && matchesBlockedContent(text)) return true
        if (desc.isNotEmpty() && matchesBlockedContent(desc)) return true

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
     *  1. Transition to WARNING_DISPLAYED, show discipline warning for 3 seconds.
     *  2. After 3 seconds, perform GLOBAL_ACTION_BACK, show persistent lock overlay.
     *  3. Transition to LOCK_ACTIVE. Lock stays until the user leaves Chrome.
     */
    private fun triggerChromeBlock() {
        if (currentState == DisciplineState.WARNING_DISPLAYED ||
            currentState == DisciplineState.LOCK_ACTIVE) return

        lastChromeBlockTime = System.currentTimeMillis()
        transitionTo(DisciplineState.WARNING_DISPLAYED)

        // Step 1: Show discipline warning overlay
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(this)
            ) {
                Log.w(TAG, "Overlay permission not granted — performing back only")
                performGlobalAction(GLOBAL_ACTION_BACK)
                transitionTo(DisciplineState.IDLE)
                return
            }

            val warningIntent = Intent(applicationContext, DisciplineWarningOverlayService::class.java)
            startService(warningIntent)
            overlayShownAt = System.currentTimeMillis()
            startOverlayWatchdog()
            Log.d(TAG, "Discipline warning overlay shown")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing warning overlay: ${e.message}")
            performGlobalAction(GLOBAL_ACTION_BACK)
            transitionTo(DisciplineState.IDLE)
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

                transitionTo(DisciplineState.LOCK_ACTIVE)

                // Show persistent lock overlay
                val lockIntent = Intent(applicationContext, ChromeLockOverlayService::class.java)
                startService(lockIntent)
                overlayShownAt = System.currentTimeMillis()
                startOverlayWatchdog()
                Log.d(TAG, "Chrome lock overlay shown — will remain until Chrome exits")
            } catch (e: Exception) {
                Log.e(TAG, "Error in post-warning handler: ${e.message}")
                transitionTo(DisciplineState.IDLE)
            }
        }, WARNING_DURATION_MS)
    }

    // ── Blocking logic (Instagram) ────────────────────────────────────

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
            overlayShownAt = System.currentTimeMillis()
            startOverlayWatchdog()
            Log.d(TAG, "LockScreenOverlayService started (source=$source)")
        } catch (e: Exception) {
            Log.e(TAG, "Error blocking app: ${e.message}", e)
        }
    }

    // ── State machine transitions ─────────────────────────────────────

    private fun transitionTo(newState: DisciplineState) {
        val prev = currentState
        currentState = newState
        Log.d(TAG, "State transition: $prev → $newState")
    }

    // ── Overlay safety watchdog ───────────────────────────────────────

    /**
     * Start a watchdog that auto-removes overlays if stuck longer than threshold
     * and the blocked app is no longer in the foreground.
     */
    private fun startOverlayWatchdog() {
        handler.removeCallbacks(overlayWatchdog)
        handler.postDelayed(overlayWatchdog, OVERLAY_MAX_STUCK_MS)
    }

    private fun checkOverlaySafety() {
        if (currentState == DisciplineState.IDLE) return
        if (overlayShownAt <= 0L) return

        val elapsed = System.currentTimeMillis() - overlayShownAt
        val fg = currentForegroundPackage

        // If overlay has been up for > 10s and the blocked app is not in foreground
        if (elapsed > OVERLAY_MAX_STUCK_MS &&
            fg != CHROME_PACKAGE && fg != REDDIT_PACKAGE && fg != FOCUS_LOCK_PACKAGE
        ) {
            Log.w(TAG, "Overlay stuck for ${elapsed}ms with fg=$fg — auto-removing")
            cleanupAllOverlays()
            transitionTo(DisciplineState.IDLE)
        } else if (currentState != DisciplineState.IDLE) {
            // Re-schedule watchdog
            handler.postDelayed(overlayWatchdog, OVERLAY_MAX_STUCK_MS)
        }
    }

    /**
     * Clean up all overlays using removeViewImmediate-safe approach.
     */
    private fun cleanupAllOverlays() {
        handler.removeCallbacksAndMessages(null)
        overlayShownAt = 0L

        try { stopService(Intent(applicationContext, DisciplineWarningOverlayService::class.java)) } catch (_: Exception) {}
        try { stopService(Intent(applicationContext, ChromeLockOverlayService::class.java)) } catch (_: Exception) {}
        try { stopService(Intent(applicationContext, LockScreenOverlayService::class.java)) } catch (_: Exception) {}

        // Re-schedule the Reddit lock runnable if in temp unlock
        if (currentState == DisciplineState.REDDIT_TEMP_UNLOCK) {
            val start = prefs.getLong(REDDIT_TEMP_UNLOCK_START_KEY, 0L)
            if (start > 0L) {
                val remaining = REDDIT_TEMP_UNLOCK_DURATION_MS - (System.currentTimeMillis() - start)
                if (remaining > 0) {
                    handler.postDelayed(redditLockRunnable, remaining)
                }
            }
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
