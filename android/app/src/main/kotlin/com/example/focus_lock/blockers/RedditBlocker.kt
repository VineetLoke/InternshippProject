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
import com.example.focus_lock.ui.LockScreenOverlay
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Reddit blocker backed by the shared Flutter lock state.
 */
object RedditBlocker {
    private const val TAG = "RedditBlocker"
    const val REDDIT_PACKAGE = "com.reddit.frontpage"

    private const val MODULE_PREFS_NAME = "reddit_blocker_prefs"
    private const val LOCK_PREFS_NAME = "focus_lock_native"
    private const val KEY_TEMP_UNLOCK_START = "rd_temp_unlock_start"
    private const val KEY_ATTEMPT_COUNT = "rd_attempt_count"
    private const val LOCK_START_KEY = "lock_start_time"
    private const val LOCK_DURATION_KEY = "lock_duration_days"

    private const val DEFAULT_LOCK_DURATION_DAYS = 30
    private const val TEMP_UNLOCK_DURATION_MS = 10L * 60 * 1000
    private const val OVERLAY_DISPLAY_MS = 5000L
    private const val BACK_PRESS_COUNT = 6
    private const val BACK_PRESS_INTERVAL_MS = 250L
    private const val BLOCK_DEBOUNCE_MS = 3000L

    @Volatile private var initialized = false
    private lateinit var modulePrefs: SharedPreferences
    private lateinit var lockPrefs: SharedPreferences
    private lateinit var appContext: Context
    private val handler = Handler(Looper.getMainLooper())
    private val dbExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "RedditBlocker-Db").apply { isDaemon = true }
    }

    private var lastBlockTime = 0L

    var onForceClose: (() -> Unit)? = null

    private val tempUnlockExpiryRunnable = Runnable { onTempUnlockExpired() }

    fun init(context: Context) {
        if (initialized) return
        appContext = context.applicationContext
        modulePrefs = appContext.getSharedPreferences(MODULE_PREFS_NAME, Context.MODE_PRIVATE)
        lockPrefs = appContext.getSharedPreferences(LOCK_PREFS_NAME, Context.MODE_PRIVATE)
        restoreTempUnlockTimer()
        initialized = true
        Log.d(TAG, "Initialized. locked=${isLocked()}, tempUnlock=${isTempUnlockActive()}")
    }

    fun isLocked(): Boolean {
        val start = parseLockStartMillis()
        if (start <= 0L) return false
        val durationMs = getLockDurationDays().toLong() * 24L * 60L * 60L * 1000L
        return System.currentTimeMillis() - start < durationMs
    }

    fun isTempUnlockActive(): Boolean {
        val start = modulePrefs.getLong(KEY_TEMP_UNLOCK_START, 0L)
        if (start == 0L) return false
        return System.currentTimeMillis() - start < TEMP_UNLOCK_DURATION_MS
    }

    fun getTempUnlockRemainingSeconds(): Long {
        return getTempUnlockRemainingMs() / 1000
    }

    private fun getTempUnlockRemainingMs(): Long {
        val start = modulePrefs.getLong(KEY_TEMP_UNLOCK_START, 0L)
        if (start == 0L) return 0L
        val remaining = TEMP_UNLOCK_DURATION_MS - (System.currentTimeMillis() - start)
        return if (remaining > 0) remaining else 0L
    }

    fun getRemainingDays(): Int {
        val start = parseLockStartMillis()
        if (start <= 0L) return 0
        val durationMs = getLockDurationDays().toLong() * 24L * 60L * 60L * 1000L
        val remaining = durationMs - (System.currentTimeMillis() - start)
        return if (remaining > 0) (remaining / (24L * 60L * 60L * 1000L)).toInt() + 1 else 0
    }

    fun getAttemptCount(): Int = modulePrefs.getInt(KEY_ATTEMPT_COUNT, 0)

    fun onRedditDetected(): Boolean {
        if (!initialized) return false
        if (!isLocked()) return false
        if (isTempUnlockActive()) {
            Log.d(TAG, "Temp unlock active (${getTempUnlockRemainingSeconds()}s left) - allowing")
            return false
        }

        val now = System.currentTimeMillis()
        if (now - lastBlockTime < BLOCK_DEBOUNCE_MS) return true
        lastBlockTime = now

        val count = modulePrefs.getInt(KEY_ATTEMPT_COUNT, 0) + 1
        modulePrefs.edit().putInt(KEY_ATTEMPT_COUNT, count).apply()
        logAttempt(count)
        showBlockingOverlay()

        Log.d(TAG, "Reddit BLOCKED - attempt #$count")
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
            val intent = Intent(appContext, LockScreenOverlay::class.java)
            intent.putExtra("source", "reddit")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                appContext.startForegroundService(intent)
            } else {
                appContext.startService(intent)
            }
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
        cancelPendingBlockActions()
        try {
            appContext.stopService(Intent(appContext, LockScreenOverlay::class.java))
        } catch (e: Exception) {
            Log.e(TAG, "Error dismissing overlay: ${e.message}")
        }
    }

    fun cancelPendingBlockActions() {
        handler.removeCallbacksAndMessages(null)
        restoreTempUnlockTimer()
    }

    fun grantTempUnlock() {
        val now = System.currentTimeMillis()
        val existingRemaining = getTempUnlockRemainingMs()
        val newRemaining = existingRemaining + TEMP_UNLOCK_DURATION_MS
        val syntheticStart = now - newRemaining
        modulePrefs.edit().putLong(KEY_TEMP_UNLOCK_START, syntheticStart).apply()
        dismissOverlay()
        handler.removeCallbacks(tempUnlockExpiryRunnable)
        handler.postDelayed(tempUnlockExpiryRunnable, newRemaining)
        Log.d(TAG, "Temp unlock GRANTED - ${newRemaining / 60000} minutes remaining")
    }

    private fun onTempUnlockExpired() {
        modulePrefs.edit().remove(KEY_TEMP_UNLOCK_START).apply()
        Log.d(TAG, "Temp unlock EXPIRED - Reddit re-locked")
    }

    private fun restoreTempUnlockTimer() {
        val start = modulePrefs.getLong(KEY_TEMP_UNLOCK_START, 0L)
        if (start > 0L) {
            val remaining = TEMP_UNLOCK_DURATION_MS - (System.currentTimeMillis() - start)
            if (remaining > 0) {
                handler.postDelayed(tempUnlockExpiryRunnable, remaining)
                Log.d(TAG, "Restored temp unlock timer: ${remaining / 1000}s remaining")
            } else {
                modulePrefs.edit().remove(KEY_TEMP_UNLOCK_START).apply()
            }
        }
    }

    private fun parseLockStartMillis(): Long {
        val raw = lockPrefs.getString(LOCK_START_KEY, null) ?: return 0L
        return try {
            Instant.parse(raw).toEpochMilli()
        } catch (e: Exception) {
            Log.e(TAG, "Invalid lock start value: $raw")
            0L
        }
    }

    private fun getLockDurationDays(): Int {
        return lockPrefs.getInt(LOCK_DURATION_KEY, DEFAULT_LOCK_DURATION_DAYS)
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
        "lockDurationDays" to getLockDurationDays()
    )
}
