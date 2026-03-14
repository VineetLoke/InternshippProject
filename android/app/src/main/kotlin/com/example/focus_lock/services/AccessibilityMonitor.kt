package com.example.focus_lock.services

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
import com.example.focus_lock.blockers.InstagramBlocker
import com.example.focus_lock.blockers.RedditBlocker
import com.example.focus_lock.blockers.ChromeIncognitoBlocker
import com.example.focus_lock.blockers.TwitterBlocker
import com.example.focus_lock.controllers.DisciplineState
import com.example.focus_lock.storage.database.AppDatabase
import com.example.focus_lock.storage.database.AppOpenLog
import com.example.focus_lock.ui.DisciplineWarningOverlay
import com.example.focus_lock.ui.LockScreenOverlay
import java.text.SimpleDateFormat
import java.time.LocalDate
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class AccessibilityMonitor : AccessibilityService() {
    companion object {
        const val TAG = "AppBlockingA11y"

        // ── Strict app block list (PART 1) ───────────────────────────
        const val INSTAGRAM_PACKAGE = "com.instagram.android"
        const val REDDIT_PACKAGE = "com.reddit.frontpage"
        const val TWITTER_PACKAGE = "com.twitter.android"
        const val CHROME_PACKAGE = "com.android.chrome"
        const val FOCUS_LOCK_PACKAGE = "com.example.focus_lock"

        // Only these packages are blocked outright (immediate block on open)
        val BLOCKED_PACKAGES = setOf(INSTAGRAM_PACKAGE, REDDIT_PACKAGE, TWITTER_PACKAGE)

        // Monitored packages = blocked + Chrome (incognito keyword detection)
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

        // Chrome incognito keyword blocking
        private const val CHROME_EVENT_DEBOUNCE_MS = 1500L
        private const val CHROME_WARNING_DURATION_MS = 3000L

        @Volatile var isRunning = false
        @Volatile var currentState: DisciplineState = DisciplineState.IDLE
        @Volatile var instance: AccessibilityMonitor? = null
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

    // Chrome incognito keyword tracking
    private var lastChromeCheckTime = 0L
    private val chromeWarningDismissRunnable = Runnable { dismissChromeWarning() }

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
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        }
        serviceInfo = info
        restoreRedditTempUnlock()

        // ── Deterministic blocker modules (clean, isolated) ───────
        InstagramBlocker.init(applicationContext)
        InstagramBlocker.onForceCloseInstagram = {
            performGlobalAction(GLOBAL_ACTION_BACK)
        }
        RedditBlocker.init(applicationContext)
        RedditBlocker.onForceClose = {
            performGlobalAction(GLOBAL_ACTION_BACK)
        }
        TwitterBlocker.init(applicationContext)
        TwitterBlocker.onForceClose = {
            performGlobalAction(GLOBAL_ACTION_BACK)
        }

        // Chrome incognito keyword blocker — monitors search text in incognito tabs
        ChromeIncognitoBlocker.resetDebounce()

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
        ChromeIncognitoBlocker.resetDebounce()
        stopOverlayService(DisciplineWarningOverlay::class.java)
        stopOverlayService(LockScreenOverlay::class.java)
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
                    if (pkg == lastEventPackage && now - lastEventTime < EVENT_DEBOUNCE_MS) {
                        // Still update foreground package even when debounced,
                        // so BACK press guards use fresh data
                        currentForegroundPackage = pkg
                        return
                    }
                    lastEventTime = now
                    lastEventPackage = pkg
                    handleWindowStateChanged(pkg)
                }
                AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                    // Chrome incognito typing detection — any typing in incognito triggers block
                    if (pkg == ChromeIncognitoBlocker.CHROME_PACKAGE) {
                        handleChromeTypingEvent()
                    }
                }
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                    // Content changes are not monitored for Chrome incognito blocking
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
            // ── Uninstall guard: detect Settings app showing FocusLock info ──
            if (packageName == "com.android.settings" || packageName == "com.google.android.packageinstaller") {
                handlePossibleUninstallAttempt()
            }
            handleUserLeftBlockedContext()
            return
        }

        // ── Log app opens: deterministic blockers log their own attempts ──
        // Instagram, Reddit, Twitter are all handled by their own blocker modules
        // Only log if the blocker module didn't handle it
        if (packageName in TRACKED_PACKAGES &&
            packageName != INSTAGRAM_PACKAGE &&
            packageName != REDDIT_PACKAGE &&
            packageName != TWITTER_PACKAGE) {
            logAppOpen(packageName)
        }

        // ── Handle each monitored package ───────────────────────
        when (packageName) {
            INSTAGRAM_PACKAGE -> {
                // Delegated to deterministic InstagramBlocker module.
                // Returns true if blocking was triggered; caller does nothing else.
                if (InstagramBlocker.onInstagramDetected()) return
            }
            TWITTER_PACKAGE -> {
                // Delegated to deterministic TwitterBlocker module.
                if (TwitterBlocker.onTwitterDetected()) return
            }
            REDDIT_PACKAGE -> {
                // Delegated to deterministic RedditBlocker module.
                if (RedditBlocker.onRedditDetected()) return
            }
            CHROME_PACKAGE -> {
                // Chrome: incognito blocking is handled by TYPE_VIEW_TEXT_CHANGED only
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
            DisciplineState.CHROME_INCOGNITO_BLOCKED -> {
                Log.d(TAG, "User left Chrome during incognito warning -> cleaning up")
                handler.removeCallbacks(chromeWarningDismissRunnable)
                cleanupAllOverlays()
                transitionTo(DisciplineState.IDLE)
                ChromeIncognitoBlocker.resetDebounce()
            }
            DisciplineState.REDDIT_CHALLENGE_ACTIVE -> {
                // User might be in FocusLock doing pushups — don't interfere
            }
            else -> { /* no-op */ }
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // Chrome incognito keyword blocking
    // Only activates when: incognito mode + blocked keyword in URL/search
    // Normal browsing is NEVER affected.
    // ══════════════════════════════════════════════════════════════════

    /**
     * Handle any typing event inside Chrome.
     * If incognito mode is active, block immediately — no keyword check.
     */
    private fun handleChromeTypingEvent() {
        if (currentState == DisciplineState.CHROME_INCOGNITO_BLOCKED) return

        val now = System.currentTimeMillis()
        if (now - lastChromeCheckTime < CHROME_EVENT_DEBOUNCE_MS) return
        lastChromeCheckTime = now

        val rootNode = rootInActiveWindow ?: return
        if (rootNode.packageName?.toString() != ChromeIncognitoBlocker.CHROME_PACKAGE) return

        if (ChromeIncognitoBlocker.shouldBlockTyping(rootNode)) {
            triggerChromeIncognitoBlock()
        }
    }

    private fun triggerChromeIncognitoBlock() {
        Log.d(TAG, "Chrome incognito keyword BLOCKED — showing warning")
        transitionTo(DisciplineState.CHROME_INCOGNITO_BLOCKED)

        // Show DisciplineWarningOverlay (3-second countdown)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(this)) {
                Log.w(TAG, "Overlay permission not granted")
                return
            }
            val intent = Intent(applicationContext, DisciplineWarningOverlay::class.java)
            startService(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing discipline warning: ${e.message}", e)
        }

        // After 3 seconds: dismiss overlay and close incognito tab
        handler.removeCallbacks(chromeWarningDismissRunnable)
        handler.postDelayed(chromeWarningDismissRunnable, CHROME_WARNING_DURATION_MS)
    }

    private fun dismissChromeWarning() {
        Log.d(TAG, "Chrome warning expired — closing incognito tab")
        stopOverlayService(DisciplineWarningOverlay::class.java)
        performGlobalAction(GLOBAL_ACTION_BACK)
        transitionTo(DisciplineState.IDLE)
    }

    // ══════════════════════════════════════════════════════════════════
    // Uninstall guard — detect navigation to FocusLock app info/uninstall
    // ══════════════════════════════════════════════════════════════════

    private var lastUninstallGuardTime = 0L

    private fun handlePossibleUninstallAttempt() {
        // Debounce: only check every 3 seconds
        val now = System.currentTimeMillis()
        if (now - lastUninstallGuardTime < 3000L) return
        lastUninstallGuardTime = now

        UninstallProtectionManager.init(applicationContext)
        if (!UninstallProtectionManager.isProtectionEnabled()) return
        if (UninstallProtectionManager.isUninstallAllowed()) return

        // Scan for our app name in the current window content
        try {
            val rootNode = rootInActiveWindow ?: return
            val focusLockNodes = rootNode.findAccessibilityNodeInfosByText("FocusLock")
            val uninstallNodes = rootNode.findAccessibilityNodeInfosByText("Uninstall")

            if (focusLockNodes.isNotEmpty() && uninstallNodes.isNotEmpty()) {
                Log.d(TAG, "Uninstall attempt detected — launching challenge overlay")
                val intent = Intent(this, com.example.focus_lock.ui.UninstallChallengeOverlay::class.java)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startService(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking uninstall attempt: ${e.message}")
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
            val intent = Intent(applicationContext, LockScreenOverlay::class.java)
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
     * Called by LockScreenOverlay when user taps "Earn access" for Reddit.
     */
    fun onRedditChallengeStarted() {
        if (currentState == DisciplineState.APP_BLOCKED && blockedPackage == REDDIT_PACKAGE) {
            transitionTo(DisciplineState.REDDIT_CHALLENGE_ACTIVE)
            stopOverlayService(LockScreenOverlay::class.java)
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
            // Close Reddit automatically — blockReddit() already fires BACK
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

        stopOverlayService(DisciplineWarningOverlay::class.java)
        stopOverlayService(LockScreenOverlay::class.java)

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
        CHROME_PACKAGE -> "Chrome"
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
