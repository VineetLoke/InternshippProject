package com.example.focus_lock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.example.focus_lock.services.AppIconManager

/**
 * Receives secret dialer codes to restore FocusLock access.
 *
 * Dial *#*#1717#*#* on the phone dialer to trigger this receiver.
 * It temporarily re-enables the launcher icon for 30 seconds.
 */
class SecretCodeReceiver : BroadcastReceiver() {
    companion object {
        const val TAG = "SecretCodeReceiver"
        const val SECRET_CODE = "1717"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Secret code received — restoring app access")
        // Temporarily show the icon for 30 seconds
        AppIconManager.temporaryShow(context, 30_000L)

        // Also launch the app directly
        try {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                context.startActivity(launchIntent)
            } else {
                // If launcher intent is null (icon disabled), use explicit intent
                val explicitIntent = Intent(context, MainActivity::class.java)
                explicitIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                // Temporarily re-enable the component so activity can start
                AppIconManager.showIcon(context)
                context.startActivity(explicitIntent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error launching app: ${e.message}")
        }
    }
}
