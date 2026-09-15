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
 * Deterministic Reddit blocker — completely isolated module.
 *
 * Architecture mirrors [InstagramBlocker] exactly:
 * Enforcement state is owned by [NativeLockState], shared by every target.
 */
object RedditBlocker {
    private const val TAG = "RedditBlocker"
    const val REDDIT_PACKAGE = "com.reddit.frontpage"

    private const val PREFS_NAME = "reddit_blocker_prefs"
    private const val KEY_LOCK_START = "rd_lock_start_epoch"
    private const val KEY_TEMP_UNLOCK_START = "rd_temp_unlock_start"
    private const val KEY_ATTEMPT_COUNT = "rd_attempt_count"

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

    private var lastBlockTime = 0L

    var onForceClose: (() -> Unit)? = null

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

    fun isTempUnlockActive(): Boolean {
        return NativeLockState.isTempUnlockActive(appContext, REDDIT_PACKAGE)
    }

    fun getTempUnlockRemainingSeconds(): Long {
        return NativeLockState.getTempUnlockRemainingSeconds(appContext, REDDIT_PACKAGE)
    }

    fun getRemainingDays(): Int {
        return NativeLockState.getRemainingDays(appContext)
    }

    fun getAttemptCount(): Int = prefs.getInt(KEY_ATTEMPT_COUNT, 0)

    fun onRedditDetected(): Boolean {
        if (!initialized) return false
        if (!NativeLockState.isTargetBlocked(appContext, REDDIT_PACKAGE)) {
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

        Log.d(TAG, "Reddit BLOCKED — attempt #$count")
        return true
    }

    private fun showBlockingOverlay() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(appContext)
            ) {
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

    private fun scheduleForceClose() {
        Log.d(TAG, "Force-closing Reddit ($BACK_PRESS_COUNT BACK presses)")
        for (i in 0 until BACK_PRESS_COUNT) {
            handler.postDelayed({ onForceClose?.invoke() }, BACK_PRESS_INTERVAL_MS * i)
        }
        handler.postDelayed(
            { dismissOverlay() },
            BACK_PRESS_INTERVAL_MS * BACK_PRESS_COUNT + 500
        )
    }

    fun dismissOverlay() {
        try {
            appContext.stopService(Intent(appContext, BlockingOverlayScreen::class.java))
        } catch (e: Exception) {
            Log.e(TAG, "Error dismissing overlay: ${e.message}")
        }
    }

    fun grantTempUnlock() {
        NativeLockState.grantTemporaryUnlock(appContext, REDDIT_PACKAGE)
        dismissOverlay()
        handler.removeCallbacks(tempUnlockExpiryRunnable)
        handler.postDelayed(tempUnlockExpiryRunnable, TEMP_UNLOCK_DURATION_MS)
        Log.d(TAG, "Temp unlock GRANTED — 10 minutes starting now")
    }

    private fun onTempUnlockExpired() {
        Log.d(TAG, "Temp unlock EXPIRED — Reddit re-locked")
    }


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
                        appName = "Reddit",
                        packageName = REDDIT_PACKAGE,
                        timestamp = timestamp,
                        date = date
                    )
                )
                Log.d(TAG, """Logged: {"app":"reddit","time":"$time","date":"$date","attempt_count":$attemptCount}""")
            } catch (e: Exception) {
                Log.e(TAG, "Error logging attempt: ${e.message}")
            }
        }
    }

    fun getStatus(): Map<String, Any> = mapOf(
        "isLocked" to isLocked(),
        "isTempUnlockActive" to isTempUnlockActive(),
        "tempUnlockRemainingSeconds" to getTempUnlockRemainingSeconds(),
        "remainingDays" to getRemainingDays(),
        "attemptCount" to getAttemptCount(),
        "lockDurationDays" to LOCK_DURATION_DAYS
    )
}
