package com.example.focus_lock

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class AppBlockingAccessibilityService : AccessibilityService() {
    companion object {
        const val TAG = "AppBlockingA11y"
        const val INSTAGRAM_PACKAGE = "com.instagram.android"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val LOCK_START_KEY = "flutter.lock_start_time"
        private const val LOCK_DURATION_KEY = "flutter.lock_duration_days"
        @Volatile var isRunning = false
    }

    private lateinit var prefs: SharedPreferences

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
            // Monitor all packages so we catch Instagram launches
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
        Log.d(TAG, "Accessibility service destroyed")
    }

    // ── Event handling ────────────────────────────────────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val packageName = event.packageName?.toString() ?: return
            Log.d(TAG, "Window changed → package: $packageName")

            if (packageName == INSTAGRAM_PACKAGE) {
                Log.d(TAG, "🔍 Instagram detected in foreground!")
                if (isLockActive()) {
                    Log.d(TAG, "🔒 Lock is ACTIVE — blocking Instagram")
                    blockInstagram()
                } else {
                    Log.d(TAG, "🔓 Lock is NOT active — allowing Instagram")
                }
            }
        }
    }

    // ── Blocking logic ────────────────────────────────────────────────

    private fun blockInstagram() {
        try {
            // 1) Navigate the user to the home screen immediately.
            //    This is the reliable way to move the user away from Instagram.
            val wentHome = performGlobalAction(GLOBAL_ACTION_HOME)
            Log.d(TAG, "performGlobalAction(HOME) = $wentHome")

            // 2) Show a full-screen overlay that blocks touch input.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(this)
            ) {
                Log.w(TAG, "⚠️ Overlay permission not granted — cannot show overlay")
            } else {
                val intent = Intent(applicationContext, LockScreenOverlayService::class.java)
                startService(intent)
                Log.d(TAG, "✅ LockScreenOverlayService started")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error blocking Instagram: ${e.message}", e)
        }
    }

    // ── Lock state read from SharedPreferences (same store as Flutter) ─

    private fun isLockActive(): Boolean {
        return try {
            val lockStartStr = prefs.getString(LOCK_START_KEY, null)
            if (lockStartStr == null) {
                Log.d(TAG, "No lock_start_time in prefs — lock inactive")
                return false
            }
            // Handle both UTC ("...Z") and local ("...") ISO-8601 strings
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
            // Fail-safe: assume locked so Instagram stays blocked
            true
        }
    }
}
