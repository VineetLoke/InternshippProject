package com.example.focus_lock.services

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.util.Log

/**
 * Helper to manage Lock Task (kiosk) related operations for device-owner deployments.
 * Note: full kiosk behavior requires Device Owner privileges and calls from an Activity
 * to actually enter lock task with `Activity.startLockTask()`.
 */
object KioskManager {
    private const val TAG = "KioskManager"

    /**
     * Configure the list of packages allowed for Lock Task mode.
     * Requires device owner. Returns true if applied.
     */
    fun applyLockTaskPackages(context: Context, packages: Array<String>, enable: Boolean): Boolean {
        try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val adminComponent = ComponentName(context, FocusLockDeviceAdminReceiver::class.java)
            if (dpm.isDeviceOwnerApp(context.packageName)) {
                if (enable) {
                    dpm.setLockTaskPackages(adminComponent, packages)
                    Log.d(TAG, "LockTask packages set: ${packages.joinToString()}")
                } else {
                    dpm.setLockTaskPackages(adminComponent, arrayOf())
                    Log.d(TAG, "LockTask packages cleared")
                }
                return true
            } else {
                Log.w(TAG, "Not device owner — cannot configure Lock Task packages")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error configuring Lock Task packages: ${e.message}")
        }
        return false
    }
}
