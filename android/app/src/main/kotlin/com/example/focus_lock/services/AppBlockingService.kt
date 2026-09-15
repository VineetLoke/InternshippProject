package com.example.focus_lock.services

import android.app.Service
import android.content.Intent
import android.provider.Settings
import android.text.TextUtils
import android.os.IBinder
import android.util.Log
import java.util.Timer
import java.util.TimerTask

/**
 * Background monitoring service.
 * The actual Instagram blocking is done by AccessibilityMonitor.
 * This service only keeps a lightweight watchdog alive.
 * It does NOT use startForeground() to avoid notification / permission crashes.
 */
class AppBlockingService : Service() {
    companion object {
        const val TAG = "AppBlockingService"
    }

    private var timer: Timer? = null

    override fun onCreate() {
        super.onCreate()
        FocusForeground.promote(this, 1101, "FocusLock active", "Verifying lock enforcement")
        Log.d(TAG, "AppBlockingService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "AppBlockingService started")
        startMonitoring()
        return START_STICKY
    }

    private fun startMonitoring() {
        // Cancel any existing timer before creating new one (prevents duplication)
        timer?.cancel()
        timer = Timer()
        timer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                verifyEnforcement()
            }
        }, 0, 5_000L)
    }

    private fun verifyEnforcement() {
        if (!NativeLockState.isLockActive(applicationContext)) return
        val monitor = AccessibilityMonitor.instance
        if (monitor != null && AccessibilityMonitor.isRunning) {
            monitor.reconcileNow()
            FocusForeground.postHealth(applicationContext, "FocusLock active", "Lock enforcement is running", false)
        } else {
            val enabled = isAccessibilityEnabled()
            val message = if (enabled) "Accessibility service is reconnecting" else "Accessibility is disabled — blocking is paused"
            Log.w(TAG, message)
            FocusForeground.postHealth(applicationContext, "FocusLock needs attention", message, !enabled)
        }
    }

    private fun isAccessibilityEnabled(): Boolean {
        val expected = android.content.ComponentName(this, AccessibilityMonitor::class.java)
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        return TextUtils.SimpleStringSplitter(':').apply { setString(enabled) }
            .any { android.content.ComponentName.unflattenFromString(it) == expected }
    }

    override fun onDestroy() {
        super.onDestroy()
        timer?.cancel()
        Log.d(TAG, "AppBlockingService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
