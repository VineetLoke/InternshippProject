package com.example.focus_lock

import android.app.Service
import android.content.Intent
import android.content.Context
import android.os.Build
import android.os.IBinder
import android.util.Log
import java.util.Timer
import java.util.TimerTask

/**
 * Background monitoring service.
 * The actual Instagram blocking is done by AppBlockingAccessibilityService.
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
