package com.example.focus_lock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.example.focus_lock.services.AppBlockingService
import com.example.focus_lock.services.AppIconManager
import com.example.focus_lock.services.UninstallProtectionManager
import com.example.focus_lock.blockers.InstagramBlocker
import com.example.focus_lock.blockers.RedditBlocker
import com.example.focus_lock.blockers.TwitterBlocker

class BootReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d(TAG, "Device booted — starting monitoring service")
            try {
                val serviceIntent = Intent(context, AppBlockingService::class.java)
                // Use startForegroundService on Android O+ (API 26+) to avoid
                // BackgroundServiceStartNotAllowedException on Android 12+.
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
                Log.d(TAG, "Monitoring service started after boot")
            } catch (e: Exception) {
                Log.e(TAG, "Error starting service on boot: ${e.message}")
            }

            // Re-hide icon if it was hidden before reboot
            if (AppIconManager.isIconHidden(context)) {
                AppIconManager.hideIcon(context)
                Log.d(TAG, "App icon re-hidden after boot")
            }

            // Initialize blockers with context so they can block immediately after boot
            try {
                InstagramBlocker.init(context)
                RedditBlocker.init(context)
                TwitterBlocker.init(context)
                Log.d(TAG, "Blockers initialized after boot")
            } catch (e: Exception) {
                Log.e(TAG, "Error initializing blockers on boot: ${e.message}")
            }

            // Reset any expired cooldown windows
            UninstallProtectionManager.init(context)
            if (!UninstallProtectionManager.isUninstallAllowed()) {
                UninstallProtectionManager.resetChallenge()
            }
        }
    }
}
