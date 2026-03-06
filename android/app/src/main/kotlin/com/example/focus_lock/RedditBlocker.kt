package com.example.focus_lock

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.example.focus_lock.database.AppDatabase
import com.example.focus_lock.database.AppOpenLog
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Deterministic Reddit blocker — completely isolated module.
 *
 * Architecture mirrors [InstagramBlocker] exactly:
 *  • Own SharedPreferences file ("reddit_blocker_prefs")
 *  • Flutter "Reset Focus" has ZERO effect
 *  • Only [grantTempUnlock] allows temporary access (15 minutes)
 *  • Lock period: 17 days from first activation
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
    private const val TEMP_UNLOCK_DURATION_MS = 15L * 60 * 1000  // 15 minutes
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
        ensureLockStarted()
        restoreTempUnlockTimer()
        initialized = true
        Log.d(TAG, "Initialized. locked=${isLocked()}, tempUnlock=${isTempUnlockActive()}")
    }

    private fun ensureLockStarted() {
        if (prefs.getLong(KEY_LOCK_START, 0L) == 0L) {
            prefs.edit().putLong(KEY_LOCK_START, System.currentTimeMillis()).apply()
            Log.d(TAG, "Lock period started: $LOCK_DURATION_DAYS days from now")
        }
    }

    fun isLocked(): Boolean {
        val start = prefs.getLong(KEY_LOCK_START, 0L)
        if (start == 0L) return false
        return System.currentTimeMillis() - start < LOCK_DURATION_MS
    }

    fun isTempUnlockActive(): Boolean {
        val start = prefs.getLong(KEY_TEMP_UNLOCK_START, 0L)
        if (start == 0L) return false
        return System.currentTimeMillis() - start < TEMP_UNLOCK_DURATION_MS
    }

    fun getTempUnlockRemainingSeconds(): Long {
        val start = prefs.getLong(KEY_TEMP_UNLOCK_START, 0L)
        if (start == 0L) return 0L
        val remaining = TEMP_UNLOCK_DURATION_MS - (System.currentTimeMillis() - start)
        return if (remaining > 0) remaining / 1000 else 0L
    }

    fun getRemainingDays(): Int {
        val start = prefs.getLong(KEY_LOCK_START, 0L)
        if (start == 0L) return 0
        val remaining = LOCK_DURATION_MS - (System.currentTimeMillis() - start)
        return if (remaining > 0) (remaining / (24 * 60 * 60 * 1000)).toInt() + 1 else 0
    }

    fun getAttemptCount(): Int = prefs.getInt(KEY_ATTEMPT_COUNT, 0)

    fun onRedditDetected(): Boolean {
        if (!initialized) return false
        if (!isLocked()) return false
        if (isTempUnlockActive()) {
            Log.d(TAG, "Temp unlock active (${getTempUnlockRemainingSeconds()}s left) — allowing")
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
            val intent = Intent(appContext, AppBlockOverlayService::class.java)
            appContext.startService(intent)
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
            appContext.stopService(Intent(appContext, AppBlockOverlayService::class.java))
        } catch (e: Exception) {
            Log.e(TAG, "Error dismissing overlay: ${e.message}")
        }
    }

    fun grantTempUnlock() {
        val now = System.currentTimeMillis()
        prefs.edit().putLong(KEY_TEMP_UNLOCK_START, now).apply()
        dismissOverlay()
        handler.removeCallbacks(tempUnlockExpiryRunnable)
        handler.postDelayed(tempUnlockExpiryRunnable, TEMP_UNLOCK_DURATION_MS)
        Log.d(TAG, "Temp unlock GRANTED — 15 minutes starting now")
    }

    private fun onTempUnlockExpired() {
        prefs.edit().remove(KEY_TEMP_UNLOCK_START).apply()
        Log.d(TAG, "Temp unlock EXPIRED — Reddit re-locked")
    }

    private fun restoreTempUnlockTimer() {
        val start = prefs.getLong(KEY_TEMP_UNLOCK_START, 0L)
        if (start > 0L) {
            val remaining = TEMP_UNLOCK_DURATION_MS - (System.currentTimeMillis() - start)
            if (remaining > 0) {
                handler.postDelayed(tempUnlockExpiryRunnable, remaining)
                Log.d(TAG, "Restored temp unlock timer: ${remaining / 1000}s remaining")
            } else {
                prefs.edit().remove(KEY_TEMP_UNLOCK_START).apply()
            }
        }
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
