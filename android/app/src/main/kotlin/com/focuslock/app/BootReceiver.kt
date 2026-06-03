package com.focuslock.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * BootReceiver — placeholder for future use.
 * Ensures FocusLock state is initialized after device reboot.
 * The Accessibility Service auto-restarts on boot if enabled by the user.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // Load SharedPreferences state so accessibility service
            // picks up the correct blocking configuration
            val prefs = context.getSharedPreferences("focuslock_prefs", Context.MODE_PRIVATE)
            AppBlockerAccessibilityService.isBlockingEnabled =
                prefs.getBoolean("instagram_blocked", true)
            AppBlockerAccessibilityService.tempUnlockUntil =
                prefs.getLong("temp_unlock_timestamp", 0L)
        }
    }
}
