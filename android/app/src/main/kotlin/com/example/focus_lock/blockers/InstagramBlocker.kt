package com.example.focus_lock.blockers

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.example.focus_lock.storage.database.AppDatabase
import com.example.focus_lock.storage.database.AppOpenLog
import com.example.focus_lock.ui.BlockingOverlayScreen
import com.example.focus_lock.services.NativeLockState
import com.example.focus_lock.services.FocusForeground
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Deterministic Instagram blocker — completely isolated module.
 *
 * Design rules:
 * Enforcement state is owned by [NativeLockState], shared by every target.
 */
object InstagramBlocker {
    private const val TAG = "InstagramBlocker"
    const val INSTAGRAM_PACKAGE = "com.instagram.android"

    // Dedicated prefs file — isolated from Flutter "Reset Focus"
    private const val PREFS_NAME = "instagram_blocker_prefs"
    private const val KEY_LOCK_START = "ig_lock_start_epoch"
    private const val KEY_TEMP_UNLOCK_START = "ig_temp_unlock_start"
    private const val KEY_ATTEMPT_COUNT = "ig_attempt_count"

    private const val LOCK_DURATION_DAYS = 17
    private const val LOCK_DURATION_MS = LOCK_DURATION_DAYS.toLong() * 24 * 60 * 60 * 1000
    private const val TEMP_UNLOCK_DURATION_MS = 10L * 60 * 1000  // 10 minutes
    private const val OVERLAY_DISPLAY_MS = 5000L                 // 5 seconds before force close
    private const val BACK_PRESS_COUNT = 6
    private const val BACK_PRESS_INTERVAL_MS = 250L
    private const val BLOCK_DEBOUNCE_MS = 3000L

    @Volatile private var initialized = false
    private lateinit var prefs: SharedPreferences
    private lateinit var appContext: Context
    private val handler = Handler(Looper.getMainLooper())
    private val dbExecutor = Executors.newSingleThreadExecutor()

    // Debounce: ignore rapid duplicate detections
    private var lastBlockTime = 0L

    // Callback for the AccessibilityService to fire GLOBAL_ACTION_BACK
    var onForceCloseInstagram: (() -> Unit)? = null

    // Temp unlock expiry runnable
    private val tempUnlockExpiryRunnable = Runnable { onTempUnlockExpired() }

    fun init(context: Context) {
        if (initialized) return
        appContext = context.applicationContext
        prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        initialized = true
        Log.d(TAG, "Initialized. locked=${isLocked()}, tempUnlock=${isTempUnlockActive()}")
    }

    fun isLocked(): Boolean {
        return NativeLockState.isLockActive(appContext)
    }

    /** True during a 15-minute emergency temp unlock. */
    fun isTempUnlockActive(): Boolean {
        return NativeLockState.isTempUnlockActive(appContext, INSTAGRAM_PACKAGE)
    }

    /** Remaining seconds of active temp unlock, or 0. */
    fun getTempUnlockRemainingSeconds(): Long {
        return NativeLockState.getTempUnlockRemainingSeconds(appContext, INSTAGRAM_PACKAGE)
    }

    /** Remaining full lock days. */
    fun getRemainingDays(): Int {
        return NativeLockState.getRemainingDays(appContext)
    }

    /** Total attempt count across all time. */
    fun getAttemptCount(): Int = prefs.getInt(KEY_ATTEMPT_COUNT, 0)

    /**
     * Called by the AccessibilityService when Instagram enters the foreground.
     * Returns true if blocking was triggered (caller should NOT run its own blocking).
     */
    fun onInstagramDetected(): Boolean {
        if (!initialized) return false
        if (!NativeLockState.isTargetBlocked(appContext, INSTAGRAM_PACKAGE)) {
            if (isTempUnlockActive()) {
            Log.d(TAG, "Temp unlock active (${getTempUnlockRemainingSeconds()}s left) — allowing")
            }
            return false
        }

        val now = System.currentTimeMillis()
        if (now - lastBlockTime < BLOCK_DEBOUNCE_MS) return true
        lastBlockTime = now

        val count = prefs.getInt(KEY_ATTEMPT_COUNT, 0) + 1
        prefs.edit().putInt(KEY_ATTEMPT_COUNT, count).apply()
        logAttempt(count)
        showBlockingOverlay()

        Log.d(TAG, "Instagram BLOCKED — attempt #$count")
        return true
    }

    /** Display the full-screen "You don't need this." overlay. */
    private fun showBlockingOverlay() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(appContext)
            ) {
                Log.w(TAG, "No overlay permission — force-closing immediately")
                scheduleForceClose()
                return
            }
            val intent = Intent(appContext, BlockingOverlayScreen::class.java)
            FocusForeground.start(appContext, intent)
            handler.postDelayed({ scheduleForceClose() }, OVERLAY_DISPLAY_MS)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}")
            scheduleForceClose()
        }
    }

    /** Fire repeated GLOBAL_ACTION_BACK to eject the user from Instagram. */
    private fun scheduleForceClose() {
        Log.d(TAG, "Force-closing Instagram ($BACK_PRESS_COUNT BACK presses)")
        for (i in 0 until BACK_PRESS_COUNT) {
            handler.postDelayed({ onForceCloseInstagram?.invoke() }, BACK_PRESS_INTERVAL_MS * i)
        }
        handler.postDelayed(
            { dismissOverlay() },
            BACK_PRESS_INTERVAL_MS * BACK_PRESS_COUNT + 500
        )
    }

    /** Remove the blocking overlay. */
    fun dismissOverlay() {
        try {
            appContext.stopService(Intent(appContext, BlockingOverlayScreen::class.java))
        } catch (e: Exception) {
            Log.e(TAG, "Error dismissing overlay: ${e.message}")
        }
    }

    /**
     * Grant 15-minute temporary access.
     * Only called after the emergency pushup challenge is completed.
     */
    fun grantTempUnlock() {
        NativeLockState.grantTemporaryUnlock(appContext, INSTAGRAM_PACKAGE)
        dismissOverlay()
        handler.removeCallbacks(tempUnlockExpiryRunnable)
        handler.postDelayed(tempUnlockExpiryRunnable, TEMP_UNLOCK_DURATION_MS)
        Log.d(TAG, "Temp unlock GRANTED — 10 minutes starting now")
    }

    /** Clears temp unlock when 15 minutes expire. */
    private fun onTempUnlockExpired() {
        Log.d(TAG, "Temp unlock EXPIRED — Instagram re-locked")
    }


    /** Log every attempt to Room database. */
    private fun logAttempt(attemptCount: Int) {
        dbExecutor.execute {
            try {
                val db = AppDatabase.getDatabase(appContext)
                val now = Date()
                val time = SimpleDateFormat("HH:mm", Locale.getDefault()).format(now)
                val date = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(now)
                val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(now)

                db.appOpenLogDao().insert(
                    AppOpenLog(
                        appName = "Instagram",
                        packageName = INSTAGRAM_PACKAGE,
                        timestamp = timestamp,
                        date = date
                    )
                )
                Log.d(TAG, """Logged: {"app":"instagram","time":"$time","date":"$date","attempt_count":$attemptCount}""")
            } catch (e: Exception) {
                Log.e(TAG, "Error logging attempt: ${e.message}")
            }
        }
    }

    /** Status map for the Flutter layer. */
    fun getStatus(): Map<String, Any> = mapOf(
        "isLocked" to isLocked(),
        "isTempUnlockActive" to isTempUnlockActive(),
        "tempUnlockRemainingSeconds" to getTempUnlockRemainingSeconds(),
        "remainingDays" to getRemainingDays(),
        "attemptCount" to getAttemptCount(),
        "lockDurationDays" to LOCK_DURATION_DAYS
    )
}
