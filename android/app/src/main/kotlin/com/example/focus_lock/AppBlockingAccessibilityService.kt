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

        // ── Strict app block list (PART 1) ───────────────────────────
        const val INSTAGRAM_PACKAGE = "com.instagram.android"
        const val REDDIT_PACKAGE = "com.reddit.frontpage"
        const val TWITTER_PACKAGE = "com.twitter.android"
        const val CHROME_PACKAGE = "com.android.chrome"
        const val FOCUS_LOCK_PACKAGE = "com.example.focus_lock"

        // Only these packages are blocked outright
        val BLOCKED_PACKAGES = setOf(INSTAGRAM_PACKAGE, REDDIT_PACKAGE, TWITTER_PACKAGE)

        // Chrome is monitored for incognito keyword filtering only
        val MONITORED_PACKAGES = BLOCKED_PACKAGES + CHROME_PACKAGE

        // Packages tracked for open-count logging
        val TRACKED_PACKAGES = BLOCKED_PACKAGES

        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val LOCK_START_KEY = "flutter.lock_start_time"
        private const val LOCK_DURATION_KEY = "flutter.lock_duration_days"

        // Reddit usage tracking keys (kept for Flutter stats display)
        private const val REDDIT_USAGE_DATE_KEY = "flutter.reddit_usage_date"
        private const val REDDIT_USAGE_MS_KEY = "flutter.reddit_usage_ms"
        private const val REDDIT_EXTRA_MS_KEY = "flutter.reddit_extra_ms"
        private const val REDDIT_DAILY_LIMIT_MS = 60L * 60L * 1000L

        // Reddit temporary unlock (PART 4)
        private const val REDDIT_TEMP_UNLOCK_START_KEY = "flutter.reddit_temp_unlock_start"
        private const val REDDIT_TEMP_UNLOCK_DURATION_MS = 10L * 60L * 1000L  // 10 minutes

        // Debounce: ignore duplicate events within 2 seconds (PART 9)
        private const val EVENT_DEBOUNCE_MS = 2000L

        // Chrome keyword debounce
        private const val CHROME_DEBOUNCE_MS = 3000L

        // Warning overlay shows for exactly 3 seconds (PART 5)
        private const val WARNING_DURATION_MS = 3000L

        // App open logging deduplication
        private const val APP_LOG_DEBOUNCE_MS = 5000L

        // Overlay safety: auto-remove if stuck (PART 8)
        private const val OVERLAY_MAX_STUCK_MS = 10_000L

        // Emergency bypass: volume up 3x within 2 seconds (PART 10)
        private const val EMERGENCY_VOLUME_PRESSES = 3
        private const val EMERGENCY_WINDOW_MS = 2000L

        // Max BACK presses to close a blocked app (PART 3)
        private const val MAX_BACK_ATTEMPTS = 5
        private const val BACK_PRESS_INTERVAL_MS = 300L

        // ── Blocked keyword list for Chrome filter (PART 5) ──────────
        private val EXACT_KEYWORDS = listOf(
            "porn", "pornhub", "pornography", "pornographic",
            "xxx", "xvideos", "xnxx", "redtube", "youporn", "tube8",
            "hentai", "nsfw", "adultvideo", "adultvideos", "adultcontent",
            "sexvideo", "sexvideos", "pornvideo", "pornvideos",
            "onlyfans", "fansly", "chaturbate", "camgirl", "camgirls",
            "camshow", "webcamgirls", "camsite", "adultcams", "livecams",
            "blowjob", "handjob", "anal", "milf", "threesome",
            "orgy", "deepthroat", "cumshot", "creampie", "hardcore", "softcore",
            "escort", "escorts", "escortservice", "adultdating",
            "hookup", "adultchat", "sexchat", "dirtychat", "adultstream",
            "bdsm", "fetish", "kink", "kinky", "dominatrix", "submissive",
            "latex", "leatherfetish", "roleplaysex", "erotic", "rule34"
        )
        private val BOUNDARY_KEYWORDS = listOf(
            "sex", "sexual", "sexy", "fuck", "fucking", "fucked"
        )
        private val BOUNDARY_REGEX: Pattern = run {
            val joined = BOUNDARY_KEYWORDS.joinToString("|") { Pattern.quote(it) }
            Pattern.compile("(?:^|\\W)($joined)(?:\\W|$)", Pattern.CASE_INSENSITIVE)
        }
        private val EXACT_REGEX: Pattern = run {
            val joined = EXACT_KEYWORDS.joinToString("|") { Pattern.quote(it) }
            Pattern.compile("($joined)", Pattern.CASE_INSENSITIVE)
        }
        private val PATTERN_REGEX: Pattern = Pattern.compile(
            "(?:^|\\W)(porn\\w*|sex(?!ton|tant|tet|tile|tup)\\w+|xxx\\w*|hentai\\w*|cam(?:girl|boy|show|site|model|live|stream)\\w*)(?:\\W|$)",
            Pattern.CASE_INSENSITIVE
        )
        val BLOCKED_KEYWORDS: List<String> = EXACT_KEYWORDS + BOUNDARY_KEYWORDS

        @Volatile var isRunning = false
        @Volatile var currentState: DisciplineState = DisciplineState.IDLE
        @Volatile var instance: AppBlockingAccessibilityService? = null
    }

    private lateinit var prefs: SharedPreferences
    private val handler = Handler(Looper.getMainLooper())
    private val dbExecutor = Executors.newSingleThreadExecutor()

    // Foreground app tracking
    private var currentForegroundPackage: String? = null
    private var blockedPackage: String? = null

    // Event debounce (PART 9)
    private var lastEventTime = 0L
    private var lastEventPackage: String? = null

    // Chrome keyword debounce
    private var lastChromeBlockTime = 0L

    // App open logging deduplication
    private var lastLoggedPackage: String? = null
    private var lastLogTime = 0L

    // Overlay safety watchdog (PART 8)
    private var overlayShownAt = 0L
    private val overlayWatchdog = Runnable { checkOverlaySafety() }

    // Emergency bypass (PART 10)
    private val volumeUpTimes = mutableListOf<Long>()

    // Reddit temp unlock timer
    private val redditLockRunnable = Runnable { onRedditTempUnlockExpired() }

    // Reddit foreground time tracking (for stats)
    private var redditForegroundSince = 0L

    // BACK press loop state
    private var backPressCount = 0

    // ══════════════════════════════════════════════════════════════════
    // Lifecycle
    // ══════════════════════════════════════════════════════════════════

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
            packageNames = null  // monitor ALL packages to detect foreground changes
            flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
        }
        serviceInfo = info
        restoreRedditTempUnlock()
        Log.d(TAG, "ServiceInfo applied — listening for events")
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

    // ══════════════════════════════════════════════════════════════════
    // Emergency bypass — Volume Up x3 within 2 seconds (PART 10)
    // ══════════════════════════════════════════════════════════════════

    override fun onKeyEvent(event: KeyEvent?): Boolean {
        if (event == null) return super.onKeyEvent(event)
        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP && event.action == KeyEvent.ACTION_DOWN) {
            val now = System.currentTimeMillis()
            volumeUpTimes.add(now)
            volumeUpTimes.removeAll { now - it > EMERGENCY_WINDOW_MS }
            if (volumeUpTimes.size >= EMERGENCY_VOLUME_PRESSES) {
                Log.d(TAG, "EMERGENCY BYPASS triggered — Volume Up x$EMERGENCY_VOLUME_PRESSES")
                volumeUpTimes.clear()
                emergencyReset()
            }
        }
        return super.onKeyEvent(event)
    }

    private fun emergencyReset() {
        Log.w(TAG, "Emergency reset — removing all overlays, state -> IDLE")
        handler.removeCallbacksAndMessages(null)
        transitionTo(DisciplineState.IDLE)
        blockedPackage = null
        overlayShownAt = 0L
        backPressCount = 0
        stopOverlayService(DisciplineWarningOverlayService::class.java)
        stopOverlayService(ChromeLockOverlayService::class.java)
        stopOverlayService(LockScreenOverlayService::class.java)
    }

    // ══════════════════════════════════════════════════════════════════
    // Event handling with debounce (PART 9)
    // ══════════════════════════════════════════════════════════════════

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        try {
            val pkg = event.packageName?.toString() ?: return

            when (event.eventType) {
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                    // Debounce: ignore same-package events within 2 seconds
                    val now = System.currentTimeMillis()
                    if (pkg == lastEventPackage && now - lastEventTime < EVENT_DEBOUNCE_MS) return
                    lastEventTime = now
                    lastEventPackage = pkg
                    handleWindowStateChanged(pkg)
                }
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
                AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                    // Only process Chrome content events — strict package check
                    if (pkg == CHROME_PACKAGE) {
                        handleChromeContentChanged(event)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onAccessibilityEvent: ${e.message}")
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // Window state changed — foreground app detection (PART 1, 2, 3)
    // ══════════════════════════════════════════════════════════════════

    private fun handleWindowStateChanged(packageName: String) {
        Log.d(TAG, "Window -> $packageName (state=$currentState)")

        // ── Track Reddit foreground time for stats ────────────────
        if (currentForegroundPackage == REDDIT_PACKAGE && packageName != REDDIT_PACKAGE) {
            flushRedditUsage()
        }
        if (packageName == REDDIT_PACKAGE && currentForegroundPackage != REDDIT_PACKAGE) {
            redditForegroundSince = System.currentTimeMillis()
        }

        currentForegroundPackage = packageName

        // ── STRICT PACKAGE VALIDATION (PART 1) ──────────────────
        // If foreground package is NOT in monitored packages: do nothing
        // except clean up overlays if user navigated away from a blocked app
        if (packageName !in MONITORED_PACKAGES && packageName != FOCUS_LOCK_PACKAGE) {
            handleUserLeftBlockedContext()
            return
        }

        // ── Log app opens for tracked packages ──────────────────
        if (packageName in TRACKED_PACKAGES) {
            logAppOpen(packageName)
        }

        // ── Handle each monitored package ───────────────────────
        when (packageName) {
            INSTAGRAM_PACKAGE -> {
                handleBlockedApp(packageName, "instagram")
            }
            TWITTER_PACKAGE -> {
                handleBlockedApp(packageName, "twitter")
            }
            REDDIT_PACKAGE -> {
                handleRedditForeground()
            }
            CHROME_PACKAGE -> {
                // Chrome is handled by content monitoring (incognito keywords).
                // If user returns to Chrome from somewhere else while WARNING was shown,
                // the warning handler already scheduled cleanup.
            }
            FOCUS_LOCK_PACKAGE -> {
                // Never block ourselves
            }
        }
    }

    /**
     * When user navigates away from a blocked app to an unrelated app,
     * remove overlays and reset state. (PART 8)
     */
    private fun handleUserLeftBlockedContext() {
        when (currentState) {
            DisciplineState.APP_BLOCKED -> {
                Log.d(TAG, "User left blocked context -> cleaning overlays, state -> IDLE")
                cleanupAllOverlays()
                transitionTo(DisciplineState.IDLE)
                blockedPackage = null
            }
            DisciplineState.WARNING_DISPLAYED -> {
                Log.d(TAG, "User left Chrome during warning -> cleaning overlays")
                cleanupAllOverlays()
                transitionTo(DisciplineState.IDLE)
            }
            DisciplineState.REDDIT_CHALLENGE_ACTIVE -> {
                // User might be in FocusLock doing pushups — don't interfere
            }
            else -> { /* no-op */ }
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // Instagram / Twitter blocking (PART 3)
    // Uses GLOBAL_ACTION_BACK — never sends to home screen
    // ══════════════════════════════════════════════════════════════════

    private fun handleBlockedApp(packageName: String, source: String) {
        // If already blocking this package, perform another BACK press
        if (currentState == DisciplineState.APP_BLOCKED && blockedPackage == packageName) {
            if (backPressCount < MAX_BACK_ATTEMPTS) {
                performGlobalAction(GLOBAL_ACTION_BACK)
                backPressCount++
                Log.d(TAG, "$source still foreground — BACK press #$backPressCount")
            }
            return
        }

        Log.d(TAG, "$source opened -> APP_BLOCKED")
        blockedPackage = packageName
        backPressCount = 0
        transitionTo(DisciplineState.APP_BLOCKED)

        // PART 3: Perform GLOBAL_ACTION_BACK (NOT home)
        performGlobalAction(GLOBAL_ACTION_BACK)
        backPressCount++

        // Schedule additional BACK presses if needed
        for (i in 1 until MAX_BACK_ATTEMPTS) {
            handler.postDelayed({
                if (currentState == DisciplineState.APP_BLOCKED &&
                    blockedPackage == packageName &&
                    currentForegroundPackage == packageName) {
                    performGlobalAction(GLOBAL_ACTION_BACK)
                    backPressCount++
                    Log.d(TAG, "$source BACK press #$backPressCount")
                }
            }, BACK_PRESS_INTERVAL_MS * i)
        }

        // Show blocking overlay
        showBlockingOverlay(source)
    }

    // ══════════════════════════════════════════════════════════════════
    // Reddit blocking with pushup challenge (PART 4)
    // ══════════════════════════════════════════════════════════════════

    private fun handleRedditForeground() {
        when (currentState) {
            DisciplineState.REDDIT_TEMP_UNLOCK -> {
                // Check if temp unlock has expired
                val start = prefs.getLong(REDDIT_TEMP_UNLOCK_START_KEY, 0L)
                val elapsed = System.currentTimeMillis() - start
                if (elapsed >= REDDIT_TEMP_UNLOCK_DURATION_MS) {
                    Log.d(TAG, "Reddit temp unlock EXPIRED -> re-locking")
                    onRedditTempUnlockExpired()
                } else {
                    val remaining = (REDDIT_TEMP_UNLOCK_DURATION_MS - elapsed) / 1000
                    Log.d(TAG, "Reddit temp unlock active — ${remaining}s remaining")
                }
            }
            DisciplineState.REDDIT_CHALLENGE_ACTIVE -> {
                // User switched back to Reddit during challenge — re-block
                Log.d(TAG, "Reddit opened during challenge -> blocking")
                blockReddit()
            }
            DisciplineState.APP_BLOCKED -> {
                // Already blocked — if Reddit is the blocked app, ensure overlay
                if (blockedPackage == REDDIT_PACKAGE) {
                    performGlobalAction(GLOBAL_ACTION_BACK)
                    Log.d(TAG, "Reddit still foreground while blocked -> BACK")
                } else {
                    // Different app was blocked, now Reddit appeared
                    blockReddit()
                }
            }
            else -> {
                // IDLE or any other state: block Reddit
                Log.d(TAG, "Reddit opened -> blocking")
                blockReddit()
            }
        }
    }

    private fun blockReddit() {
        blockedPackage = REDDIT_PACKAGE
        backPressCount = 0
        transitionTo(DisciplineState.APP_BLOCKED)

        // PART 3: Use GLOBAL_ACTION_BACK, NOT home
        performGlobalAction(GLOBAL_ACTION_BACK)
        backPressCount++

        showBlockingOverlay("reddit")
    }

    private fun showBlockingOverlay(source: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(this)) {
                Log.w(TAG, "Overlay permission not granted — cannot show overlay")
                return
            }
            val intent = Intent(applicationContext, LockScreenOverlayService::class.java)
            intent.putExtra("source", source)
            startService(intent)
            overlayShownAt = System.currentTimeMillis()
            startOverlayWatchdog()
            Log.d(TAG, "Lock overlay shown (source=$source)")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}", e)
        }
    }

    /**
     * Called by LockScreenOverlayService when user taps "Earn access" for Reddit.
     */
    fun onRedditChallengeStarted() {
        if (currentState == DisciplineState.APP_BLOCKED && blockedPackage == REDDIT_PACKAGE) {
            transitionTo(DisciplineState.REDDIT_CHALLENGE_ACTIVE)
            stopOverlayService(LockScreenOverlayService::class.java)
            overlayShownAt = 0L
            Log.d(TAG, "Reddit challenge started — overlay removed")
        }
    }

    /**
     * Called by MainActivity when user completes 100 pushups.
     * Grants exactly 10 minutes of Reddit access. (PART 4)
     */
    fun onRedditChallengeCompleted() {
        transitionTo(DisciplineState.REDDIT_TEMP_UNLOCK)
        val now = System.currentTimeMillis()
        prefs.edit().putLong(REDDIT_TEMP_UNLOCK_START_KEY, now).apply()
        blockedPackage = null
        backPressCount = 0

        // Schedule re-lock after exactly 10 minutes
        handler.removeCallbacks(redditLockRunnable)
        handler.postDelayed(redditLockRunnable, REDDIT_TEMP_UNLOCK_DURATION_MS)
        Log.d(TAG, "Reddit temp unlock granted — 10 minutes starting now")
    }

    /** When the 10-minute Reddit access window expires (PART 4). */
    private fun onRedditTempUnlockExpired() {
        Log.d(TAG, "Reddit temp unlock expired — closing Reddit automatically")
        prefs.edit().remove(REDDIT_TEMP_UNLOCK_START_KEY).apply()
        handler.removeCallbacks(redditLockRunnable)

        if (currentForegroundPackage == REDDIT_PACKAGE) {
            // Close Reddit automatically via BACK
            performGlobalAction(GLOBAL_ACTION_BACK)
            blockReddit()
        } else {
            transitionTo(DisciplineState.IDLE)
            blockedPackage = null
        }
    }

    /** Restore Reddit temp unlock if active before service restart. */
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

    /** Check remaining Reddit temp unlock ms. Called from Flutter. */
    fun getRedditTempUnlockRemainingMs(): Long {
        val start = prefs.getLong(REDDIT_TEMP_UNLOCK_START_KEY, 0L)
        if (start <= 0L) return 0L
        val elapsed = System.currentTimeMillis() - start
        val remaining = REDDIT_TEMP_UNLOCK_DURATION_MS - elapsed
        return if (remaining > 0) remaining else 0L
    }

    // ══════════════════════════════════════════════════════════════════
    // Chrome incognito-only keyword filter (PART 5)
    // Triggers ONLY when: 1) Chrome is in incognito  2) Blocked keyword found
    // Never triggers during normal browsing.
    // ══════════════════════════════════════════════════════════════════

    private fun handleChromeContentChanged(event: AccessibilityEvent) {
        // Skip if already in a blocking/warning state
        if (currentState == DisciplineState.WARNING_DISPLAYED ||
            currentState == DisciplineState.APP_BLOCKED) return

        // Debounce: 3 seconds between Chrome triggers
        val now = System.currentTimeMillis()
        if (now - lastChromeBlockTime < CHROME_DEBOUNCE_MS) return

        // ── CRITICAL: Only check in incognito mode (PART 5) ─────
        val rootNode = try { rootInActiveWindow } catch (_: Exception) { null }
        if (rootNode == null) return

        try {
            if (!isChromeIncognito(rootNode)) {
                // Normal browsing — do absolutely nothing
                return
            }

            // In incognito mode — scan for blocked keywords
            var keywordFound = false

            // 1. Check event text
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

            // 3. Check source node tree (depth-limited)
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
                Log.d(TAG, "Blocked keyword detected in Chrome INCOGNITO")
                triggerChromeWarning()
            }
        } finally {
            try { rootNode.recycle() } catch (_: Exception) {}
        }
    }

    /**
     * Detect Chrome incognito mode by scanning for "incognito" in the
     * accessibility tree (tab switcher button, page content, etc.).
     */
    private fun isChromeIncognito(node: AccessibilityNodeInfo): Boolean {
        return scanForIncognito(node, 0)
    }

    private fun scanForIncognito(node: AccessibilityNodeInfo?, depth: Int): Boolean {
        if (node == null || depth > 3) return false

        val desc = node.contentDescription?.toString()?.lowercase(Locale.ROOT) ?: ""
        val text = node.text?.toString()?.lowercase(Locale.ROOT) ?: ""

        if ("incognito" in desc || "incognito" in text) return true

        for (i in 0 until node.childCount) {
            val child = try { node.getChild(i) } catch (_: Exception) { null }
            if (child != null) {
                val found = scanForIncognito(child, depth + 1)
                try { child.recycle() } catch (_: Exception) {}
                if (found) return true
            }
        }
        return false
    }

    /** Match text against blocked keywords using regex with word boundaries. */
    private fun matchesBlockedContent(text: String): Boolean {
        if (text.isBlank()) return false
        if (EXACT_REGEX.matcher(text).find()) return true
        if (BOUNDARY_REGEX.matcher(text).find()) return true
        if (PATTERN_REGEX.matcher(text).find()) return true
        return false
    }

    /** Recursively scan accessibility node tree for blocked keywords (max depth 4). */
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

    /**
     * Chrome incognito keyword detected (PART 5):
     * 1. Show quote screen for exactly 3 seconds (WARNING_DISPLAYED)
     * 2. Close tab via GLOBAL_ACTION_BACK
     * 3. Return to IDLE
     */
    private fun triggerChromeWarning() {
        if (currentState == DisciplineState.WARNING_DISPLAYED) return

        lastChromeBlockTime = System.currentTimeMillis()
        transitionTo(DisciplineState.WARNING_DISPLAYED)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(this)) {
                Log.w(TAG, "Overlay permission not granted — BACK only")
                performGlobalAction(GLOBAL_ACTION_BACK)
                transitionTo(DisciplineState.IDLE)
                return
            }

            // Show discipline warning overlay
            val warningIntent = Intent(applicationContext, DisciplineWarningOverlayService::class.java)
            startService(warningIntent)
            overlayShownAt = System.currentTimeMillis()
            startOverlayWatchdog()
            Log.d(TAG, "Discipline warning overlay shown")

            // After exactly 3 seconds: close tab and return to IDLE
            handler.postDelayed({
                try {
                    // Close the incognito tab
                    performGlobalAction(GLOBAL_ACTION_BACK)
                    Log.d(TAG, "Chrome incognito tab closed via GLOBAL_ACTION_BACK")

                    // Remove warning overlay
                    stopOverlayService(DisciplineWarningOverlayService::class.java)
                    overlayShownAt = 0L
                    transitionTo(DisciplineState.IDLE)
                } catch (e: Exception) {
                    Log.e(TAG, "Error in warning timer: ${e.message}")
                    transitionTo(DisciplineState.IDLE)
                }
            }, WARNING_DURATION_MS)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing warning: ${e.message}")
            performGlobalAction(GLOBAL_ACTION_BACK)
            transitionTo(DisciplineState.IDLE)
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // State machine transitions (PART 2)
    // ══════════════════════════════════════════════════════════════════

    private fun transitionTo(newState: DisciplineState) {
        val prev = currentState
        currentState = newState
        Log.d(TAG, "State: $prev -> $newState")
    }

    // ══════════════════════════════════════════════════════════════════
    // Overlay safety (PART 8)
    // Overlay must never remain stuck.
    // ══════════════════════════════════════════════════════════════════

    private fun startOverlayWatchdog() {
        handler.removeCallbacks(overlayWatchdog)
        handler.postDelayed(overlayWatchdog, OVERLAY_MAX_STUCK_MS)
    }

    private fun checkOverlaySafety() {
        if (currentState == DisciplineState.IDLE) return
        if (overlayShownAt <= 0L) return

        val elapsed = System.currentTimeMillis() - overlayShownAt
        val fg = currentForegroundPackage

        // If overlay stuck > 10s and blocked app is NOT in foreground: auto-remove
        if (elapsed > OVERLAY_MAX_STUCK_MS) {
            val blockedIsActive = when {
                blockedPackage != null -> fg == blockedPackage
                currentState == DisciplineState.WARNING_DISPLAYED -> fg == CHROME_PACKAGE
                else -> false
            }
            if (!blockedIsActive && fg != FOCUS_LOCK_PACKAGE) {
                Log.w(TAG, "Overlay stuck ${elapsed}ms with fg=$fg -> auto-removing")
                cleanupAllOverlays()
                transitionTo(DisciplineState.IDLE)
                blockedPackage = null
                return
            }
        }

        // Re-schedule watchdog if still in a blocking state
        if (currentState != DisciplineState.IDLE) {
            handler.postDelayed(overlayWatchdog, OVERLAY_MAX_STUCK_MS)
        }
    }

    /** Clean up all overlays using removeViewImmediate-safe approach (PART 8). */
    private fun cleanupAllOverlays() {
        handler.removeCallbacksAndMessages(null)
        overlayShownAt = 0L
        backPressCount = 0

        stopOverlayService(DisciplineWarningOverlayService::class.java)
        stopOverlayService(ChromeLockOverlayService::class.java)
        stopOverlayService(LockScreenOverlayService::class.java)

        // Re-schedule Reddit lock timer if in temp unlock
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

    private fun stopOverlayService(cls: Class<*>) {
        try { stopService(Intent(applicationContext, cls)) } catch (_: Exception) {}
    }

    // ══════════════════════════════════════════════════════════════════
    // App open logging (Room database)
    // ══════════════════════════════════════════════════════════════════

    private fun logAppOpen(packageName: String) {
        val now = System.currentTimeMillis()
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

    private fun getAppName(packageName: String): String = when (packageName) {
        INSTAGRAM_PACKAGE -> "Instagram"
        REDDIT_PACKAGE -> "Reddit"
        TWITTER_PACKAGE -> "Twitter/X"
        else -> packageName
    }

    // ══════════════════════════════════════════════════════════════════
    // Reddit usage tracking (kept for Flutter stats display)
    // ══════════════════════════════════════════════════════════════════

    private fun flushRedditUsage() {
        if (redditForegroundSince <= 0L) return
        val elapsed = System.currentTimeMillis() - redditForegroundSince
        redditForegroundSince = 0L
        if (elapsed <= 0) return

        resetIfNewDay()
        val prev = prefs.getLong(REDDIT_USAGE_MS_KEY, 0L)
        prefs.edit().putLong(REDDIT_USAGE_MS_KEY, prev + elapsed).apply()
        Log.d(TAG, "Reddit usage flushed: +${elapsed}ms -> total ${prev + elapsed}ms")
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
}
