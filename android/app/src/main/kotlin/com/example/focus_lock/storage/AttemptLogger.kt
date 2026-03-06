package com.example.focus_lock.storage

import android.content.Context
import android.util.Log
import com.example.focus_lock.storage.database.AppDatabase
import com.example.focus_lock.storage.database.AppOpenLog
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Centralized attempt/app-open logger backed by Room database.
 *
 * Used by blocker modules and the accessibility monitor to record
 * every blocked attempt and app open event.
 */
object AttemptLogger {
    private const val TAG = "AttemptLogger"
    private val dbExecutor = Executors.newSingleThreadExecutor()

    /**
     * Log an app open or block attempt.
     *
     * @param context  Application context for database access.
     * @param appName  Human-readable app name (e.g. "Instagram").
     * @param packageName  Package name (e.g. "com.instagram.android").
     */
    fun logAppOpen(context: Context, appName: String, packageName: String) {
        val now = Date()
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(now)
        val date = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(now)

        dbExecutor.execute {
            try {
                val db = AppDatabase.getDatabase(context)
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
}
