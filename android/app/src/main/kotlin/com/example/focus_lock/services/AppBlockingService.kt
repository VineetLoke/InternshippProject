package com.example.focus_lock.services

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import com.example.focus_lock.blockers.InstagramBlocker
import com.example.focus_lock.blockers.RedditBlocker
import com.example.focus_lock.blockers.TwitterBlocker
import java.time.Instant
import java.util.Timer
import java.util.TimerTask

/**
 * Background monitoring service.
 * The actual Instagram blocking is done by AccessibilityMonitor.
 * This service keeps a lightweight watchdog alive using a foreground notification.
 */
class AppBlockingService : Service() {
    companion object {
        const val TAG = "AppBlockingService"
        private const val CHANNEL_ID = "focus_lock_service"
        private const val NOTIFICATION_ID = 1001
        private const val LOCK_PREFS_NAME = "focus_lock_native"
        private const val LOCK_START_KEY = "lock_start_time"
        private const val LOCK_DURATION_KEY = "lock_duration_days"
        private const val DEFAULT_LOCK_DURATION_DAYS = 30
    }

    private var timer: Timer? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "AppBlockingService created")
        initializeBlockers()
        startForegroundNotification()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "AppBlockingService started")
        startMonitoring()
        return START_STICKY
    }

    private fun startForegroundNotification() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                CHANNEL_ID,
                "FocusLock Service",
                android.app.NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps FocusLock protection active"
            }
            val manager = getSystemService(android.app.NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
        val notification = android.app.Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("FocusLock")
            .setContentText("Protection active")
            .setSmallIcon(com.example.focus_lock.R.mipmap.ic_launcher)
            .build()
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID, 
                notification, 
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun startMonitoring() {
        // Cancel any existing timer before creating new one (prevents duplication)
        timer?.cancel()
        timer = Timer()
        timer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                Log.d(TAG, "Watchdog tick")
            }
        }, 0, 60_000L)
    }

    override fun onDestroy() {
        super.onDestroy()
        timer?.cancel()
        if (isLockActive()) {
            scheduleRestart()
        }
        Log.d(TAG, "AppBlockingService destroyed")
    }

    private fun initializeBlockers() {
        try {
            InstagramBlocker.init(applicationContext)
            RedditBlocker.init(applicationContext)
            TwitterBlocker.init(applicationContext)
        } catch (e: Exception) {
            Log.e(TAG, "Could not initialize blockers: ${e.message}")
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        if (isLockActive()) {
            scheduleRestart()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun scheduleRestart() {
        try {
            val restartIntent = Intent(applicationContext, AppBlockingService::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
            val pendingIntent = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                PendingIntent.getForegroundService(applicationContext, 2001, restartIntent, flags)
            } else {
                PendingIntent.getService(applicationContext, 2001, restartIntent, flags)
            }
            val alarmManager = getSystemService(AlarmManager::class.java)
            alarmManager.set(
                AlarmManager.RTC_WAKEUP,
                System.currentTimeMillis() + 1000L,
                pendingIntent
            )
            Log.d(TAG, "Scheduled monitoring service restart")
        } catch (e: Exception) {
            Log.e(TAG, "Could not schedule restart: ${e.message}")
        }
    }

    private fun isLockActive(): Boolean {
        val prefs = getSharedPreferences(LOCK_PREFS_NAME, MODE_PRIVATE)
        val startRaw = prefs.getString(LOCK_START_KEY, null) ?: return false
        val startMs = try {
            Instant.parse(startRaw).toEpochMilli()
        } catch (e: Exception) {
            return false
        }
        val durationDays = prefs.getInt(LOCK_DURATION_KEY, DEFAULT_LOCK_DURATION_DAYS)
        val durationMs = durationDays.toLong() * 24L * 60L * 60L * 1000L
        return System.currentTimeMillis() - startMs < durationMs
    }
}
