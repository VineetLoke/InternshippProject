package com.example.focus_lock.services

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Device Administrator receiver for FocusLock.
 * Prevents easy uninstall by requiring device admin deactivation first,
 * which triggers a warning and the pushup challenge.
 */
class FocusLockDeviceAdminReceiver : DeviceAdminReceiver() {
    companion object {
        const val TAG = "FLDeviceAdmin"
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.d(TAG, "Device admin ENABLED — uninstall protection active")
    }

    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        Log.d(TAG, "Device admin disable REQUESTED — launching challenge")

        // Check if the user has completed the challenge within the cooldown window
        val manager = UninstallProtectionManager
        manager.init(context)

        if (manager.isUninstallAllowed()) {
            Log.d(TAG, "Challenge completed within cooldown — allowing disable")
            return "FocusLock protection will be removed."
        }

        // Launch the uninstall challenge overlay
        try {
            val overlayIntent = Intent(context, com.example.focus_lock.ui.UninstallChallengeOverlay::class.java)
            overlayIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startService(overlayIntent)
        } catch (e: Exception) {
            Log.e(TAG, "Error launching challenge overlay: ${e.message}")
        }

        return "Discipline protects you from your weaker self.\n\nComplete 200 pushups to remove FocusLock protection."
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.w(TAG, "Device admin DISABLED")
    }
}
