package com.example.focus_lock.services

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
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
    }

    private var timer: Timer? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "AppBlockingService created")
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
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .build()
        startForeground(NOTIFICATION_ID, notification)
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
        Log.d(TAG, "AppBlockingService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
