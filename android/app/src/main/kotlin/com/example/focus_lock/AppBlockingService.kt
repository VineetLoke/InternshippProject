package com.example.focus_lock

import android.app.Service
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.Timer
import java.util.TimerTask

class AppBlockingService : Service() {
    companion object {
        const val TAG = "AppBlockingService"
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "focus_lock_channel"
    }

    private var timer: Timer? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "AppBlockingService created")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "AppBlockingService started")
        startMonitoring()
        return START_STICKY
    }

    private fun startMonitoring() {
        timer = Timer()
        timer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                // Check if lock is still active from SharedPreferences
                // This would be checked via platform channel to the Flutter app
                Log.d(TAG, "Monitoring active...")
            }
        }, 0, 60000) // Check every minute
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "FocusLock Service",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Instagram blocking service"
            }

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): androidx.core.app.Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FocusLock Active")
            .setContentText("Instagram is protected for your focus period")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        timer?.cancel()
        Log.d(TAG, "AppBlockingService destroyed")
    }

    override fun onBind(intent: Intent) = null
}
