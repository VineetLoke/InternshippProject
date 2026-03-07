package com.example.focus_lock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.example.focus_lock.services.AppBlockingService
import com.example.focus_lock.services.AppIconManager
import com.example.focus_lock.services.UninstallProtectionManager

class BootReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d(TAG, "Device booted — starting monitoring service")
            try {
                // Use plain startService (not startForegroundService) to avoid
                // ForegroundServiceStartNotAllowedException when launched from
                // a background broadcast context on Android 12+.
                val serviceIntent = Intent(context, AppBlockingService::class.java)
                context.startService(serviceIntent)
                Log.d(TAG, "Monitoring service started after boot")
            } catch (e: Exception) {
                Log.e(TAG, "Error starting service on boot: ${e.message}")
            }

            // Re-hide icon if it was hidden before reboot
            if (AppIconManager.isIconHidden(context)) {
                AppIconManager.hideIcon(context)
                Log.d(TAG, "App icon re-hidden after boot")
            }

            // Reset any expired cooldown windows
            UninstallProtectionManager.init(context)
            if (!UninstallProtectionManager.isUninstallAllowed()) {
                UninstallProtectionManager.resetChallenge()
            }
        }
    }
}
