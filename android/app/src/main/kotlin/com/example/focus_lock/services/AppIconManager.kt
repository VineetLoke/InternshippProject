package com.example.focus_lock.services

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import com.example.focus_lock.MainActivity

/**
 * Manages hiding/showing the FocusLock launcher icon.
 * Disabling the launcher alias hides the icon from the app drawer
 * while all services continue running in the background.
 */
object AppIconManager {
    private const val TAG = "AppIconManager"
    private const val PREFS_NAME = "focuslock_icon_prefs"
    private const val KEY_ICON_HIDDEN = "icon_hidden"

    /**
     * Hide the app icon from the launcher by disabling the main activity's
     * launcher intent filter via an alias component.
     */
    fun hideIcon(context: Context) {
        try {
            val pm = context.packageManager
            val componentName = ComponentName(context, MainActivity::class.java)
            pm.setComponentEnabledSetting(
                componentName,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_ICON_HIDDEN, true).apply()
            Log.d(TAG, "App icon HIDDEN from launcher")
        } catch (e: Exception) {
            Log.e(TAG, "Error hiding icon: ${e.message}")
        }
    }

    /**
     * Show the app icon in the launcher by re-enabling the main activity component.
     */
    fun showIcon(context: Context) {
        try {
            val pm = context.packageManager
            val componentName = ComponentName(context, MainActivity::class.java)
            pm.setComponentEnabledSetting(
                componentName,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_ICON_HIDDEN, false).apply()
            Log.d(TAG, "App icon SHOWN in launcher")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing icon: ${e.message}")
        }
    }

    /**
     * Check if the app icon is currently hidden.
     */
    fun isIconHidden(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_ICON_HIDDEN, false)
    }

    /**
     * Temporarily show the icon for access, then re-hide after a delay.
     */
    fun temporaryShow(context: Context, durationMs: Long = 30_000L) {
        showIcon(context)
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            hideIcon(context)
            Log.d(TAG, "Temporary icon access expired — icon re-hidden")
        }, durationMs)
    }
}
