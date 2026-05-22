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
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Instagram blocker backed by the shared Flutter lock state.
 *
 * Flutter owns the canonical lock window. This module only tracks
 * app-specific temp unlocks and attempt counts.
 */
object InstagramBlocker {
    private const val TAG = "InstagramBlocker"
    const val INSTAGRAM_PACKAGE = "com.instagram.android"

    private const val MODULE_PREFS_NAME = "instagram_blocker_prefs"
    private const val LOCK_PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_TEMP_UNLOCK_START = "ig_temp_unlock_start"
    private const val KEY_ATTEMPT_COUNT = "ig_attempt_count"
    private const val LOCK_START_KEY = "flutter.lock_start_time"
    private const val LOCK_DURATION_KEY = "flutter.lock_duration_days"

    private const val DEFAULT_LOCK_DURATION_DAYS = 30
    private const val TEMP_UNLOCK_DURATION_MS = 15L * 60 * 1000
    private const val OVERLAY_DISPLAY_MS = 5000L
    private const val BACK_PRESS_COUNT = 6
    private const val BACK_PRESS_INTERVAL_MS = 250L
    private const val BLOCK_DEBOUNCE_MS = 3000L

    @Volatile private var initialized = false
    private lateinit var modulePrefs: SharedPreferences
    private lateinit var lockPrefs: SharedPreferences
    private lateinit var appContext: Context
    private val handler = Handler(Looper.getMainLooper())
    private val dbExecutor = Executors.newSingleThreadExecutor()

    private var lastBlockTime = 0L

    var onForceCloseInstagram: (() -> Unit)? = null

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
        val start = modulePrefs.getLong(KEY_TEMP_UNLOCK_START, 0L)
        if (start == 0L) return 0L
        val remaining = TEMP_UNLOCK_DURATION_MS - (System.currentTimeMillis() - start)
        return if (remaining > 0) remaining / 1000 else 0L
    }

    fun getRemainingDays(): Int {
        val start = parseLockStartMillis()
        if (start <= 0L) return 0
        val durationMs = getLockDurationDays().toLong() * 24L * 60L * 60L * 1000L
        val remaining = durationMs - (System.currentTimeMillis() - start)
        return if (remaining > 0) (remaining / (24L * 60L * 60L * 1000L)).toInt() + 1 else 0
    }

    fun getAttemptCount(): Int = modulePrefs.getInt(KEY_ATTEMPT_COUNT, 0)

    fun onInstagramDetected(): Boolean {
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

        Log.d(TAG, "Instagram BLOCKED - attempt #$count")
        return true
    }

    private fun showBlockingOverlay() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(appContext)
            ) {
                Log.w(TAG, "No overlay permission - force-closing immediately")
                scheduleForceClose()
                return
            }
            val intent = Intent(appContext, BlockingOverlayScreen::class.java)
            appContext.startService(intent)
            handler.postDelayed({ scheduleForceClose() }, OVERLAY_DISPLAY_MS)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}")
            scheduleForceClose()
        }
    }

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

    fun dismissOverlay() {
        try {
            appContext.stopService(Intent(appContext, BlockingOverlayScreen::class.java))
        } catch (e: Exception) {
            Log.e(TAG, "Error dismissing overlay: ${e.message}")
        }
    }

    fun grantTempUnlock() {
        val now = System.currentTimeMillis()
        modulePrefs.edit().putLong(KEY_TEMP_UNLOCK_START, now).apply()
        dismissOverlay()
        handler.removeCallbacks(tempUnlockExpiryRunnable)
        handler.postDelayed(tempUnlockExpiryRunnable, TEMP_UNLOCK_DURATION_MS)
        Log.d(TAG, "Temp unlock GRANTED - 15 minutes starting now")
    }

    private fun onTempUnlockExpired() {
        modulePrefs.edit().remove(KEY_TEMP_UNLOCK_START).apply()
        Log.d(TAG, "Temp unlock EXPIRED - Instagram re-locked")
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

    fun getStatus(): Map<String, Any> = mapOf(
        "isLocked" to isLocked(),
        "isTempUnlockActive" to isTempUnlockActive(),
        "tempUnlockRemainingSeconds" to getTempUnlockRemainingSeconds(),
        "remainingDays" to getRemainingDays(),
        "attemptCount" to getAttemptCount(),
        "lockDurationDays" to getLockDurationDays()
    )
}
