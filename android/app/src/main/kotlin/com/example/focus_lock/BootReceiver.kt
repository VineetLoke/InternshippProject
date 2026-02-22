package com.example.focus_lock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d(TAG, "Device booted, starting app blocking service")

            // Start the foreground service
            val serviceIntent = Intent(context, AppBlockingService::class.java)
            
            try {
                context.startForegroundService(serviceIntent)
                Log.d(TAG, "App blocking service started successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Error starting service: ${e.message}")
            }
        }
    }
}
