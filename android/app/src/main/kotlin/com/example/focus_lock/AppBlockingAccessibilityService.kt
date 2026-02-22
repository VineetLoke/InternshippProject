package com.example.focus_lock

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.util.Log
import android.app.ActivityManager
import android.content.Context
import android.os.Build

class AppBlockingAccessibilityService : AccessibilityService() {
    companion object {
        const val TAG = "AppBlockingService"
        const val INSTAGRAM_PACKAGE = "com.instagram.android"
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                val packageName = event.packageName?.toString()
                
                if (packageName == INSTAGRAM_PACKAGE) {
                    Log.d(TAG, "Instagram detected! Package: $packageName")
                    blockInstagram()
                }
            }
        }
    }

    private fun blockInstagram() {
        try {
            // Get the activity manager
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            
            // Force stop Instagram
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activityManager.killBackgroundProcesses(INSTAGRAM_PACKAGE)
            } else {
                @Suppress("DEPRECATION")
                activityManager.killBackgroundProcesses(INSTAGRAM_PACKAGE)
            }

            Log.d(TAG, "Instagram blocked successfully")

            // Send broadcast to show lock screen overlay
            val intent = Intent(applicationContext, LockScreenOverlayService::class.java)
            startService(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Error blocking Instagram: ${e.message}")
        }
    }

    override fun onInterrupt() {
        Log.d(TAG, "Accessibility service interrupted")
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "Accessibility service connected")

        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_ALL_MASK
            notificationTimeout = 100
        }
        setServiceInfo(info)
    }
}
