package com.example.focus_lock.services

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.util.Log

/**
 * Manages Chrome incognito mode via enterprise policy (managed app restrictions).
 *
 * Uses DevicePolicyManager.setApplicationRestrictions() to push the
 * IncognitoModeAvailability policy to Chrome. Value 1 = incognito disabled.
 *
 * Requires the app to be a Device Owner or Profile Owner.
 * Falls back gracefully if the app only has basic device admin privileges.
 */
object ChromeIncognitoPolicy {
    private const val TAG = "ChromeIncognitoPolicy"
    const val CHROME_PACKAGE = "com.android.chrome"
    private const val POLICY_KEY = "IncognitoModeAvailability"
    private const val INCOGNITO_DISABLED = 1

    /**
     * Apply the Chrome managed configuration to disable incognito mode.
     *
     * @return true if the policy was applied successfully.
     */
    fun applyIncognitoPolicy(context: Context): Boolean {
        return try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val adminComponent = ComponentName(context, FocusLockDeviceAdminReceiver::class.java)

            if (!isDeviceOwnerOrProfileOwner(dpm, adminComponent, context)) {
                Log.w(TAG, "App is not device owner or profile owner — cannot set app restrictions")
                return false
            }

            val restrictions = Bundle().apply {
                putInt(POLICY_KEY, INCOGNITO_DISABLED)
            }
            dpm.setApplicationRestrictions(adminComponent, CHROME_PACKAGE, restrictions)
            Log.d(TAG, "Chrome incognito policy applied: $POLICY_KEY=$INCOGNITO_DISABLED")
            true
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException applying Chrome policy: ${e.message}")
            false
        } catch (e: Exception) {
            Log.e(TAG, "Error applying Chrome policy: ${e.message}")
            false
        }
    }

    /**
     * Remove the Chrome managed configuration (re-enable incognito mode).
     *
     * @return true if the policy was removed successfully.
     */
    fun removeIncognitoPolicy(context: Context): Boolean {
        return try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val adminComponent = ComponentName(context, FocusLockDeviceAdminReceiver::class.java)

            if (!isDeviceOwnerOrProfileOwner(dpm, adminComponent, context)) {
                Log.w(TAG, "App is not device owner or profile owner — cannot clear app restrictions")
                return false
            }

            dpm.setApplicationRestrictions(adminComponent, CHROME_PACKAGE, Bundle())
            Log.d(TAG, "Chrome incognito policy removed")
            true
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException removing Chrome policy: ${e.message}")
            false
        } catch (e: Exception) {
            Log.e(TAG, "Error removing Chrome policy: ${e.message}")
            false
        }
    }

    /**
     * Check whether incognito is currently disabled by policy.
     */
    fun isIncognitoDisabled(context: Context): Boolean {
        return try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val adminComponent = ComponentName(context, FocusLockDeviceAdminReceiver::class.java)

            if (!isDeviceOwnerOrProfileOwner(dpm, adminComponent, context)) {
                return false
            }

            val restrictions = dpm.getApplicationRestrictions(adminComponent, CHROME_PACKAGE)
            val value = restrictions.getInt(POLICY_KEY, 0)
            value == INCOGNITO_DISABLED
        } catch (e: Exception) {
            Log.e(TAG, "Error checking Chrome policy: ${e.message}")
            false
        }
    }

    /**
     * Check if this app is Device Owner or Profile Owner (required for setApplicationRestrictions).
     */
    fun isDeviceOwnerOrProfileOwner(context: Context): Boolean {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(context, FocusLockDeviceAdminReceiver::class.java)
        return isDeviceOwnerOrProfileOwner(dpm, adminComponent, context)
    }

    private fun isDeviceOwnerOrProfileOwner(
        dpm: DevicePolicyManager,
        adminComponent: ComponentName,
        context: Context
    ): Boolean {
        return dpm.isDeviceOwnerApp(context.packageName) ||
               dpm.isProfileOwnerApp(context.packageName)
    }

    /**
     * Get the full policy status as a map for Flutter method channel.
     */
    fun getStatus(context: Context): Map<String, Any> {
        val isOwner = isDeviceOwnerOrProfileOwner(context)
        val isDisabled = if (isOwner) isIncognitoDisabled(context) else false
        return mapOf(
            "isActive" to isDisabled,
            "isDeviceOwner" to isOwner,
            "policyApplied" to isDisabled
        )
    }
}
