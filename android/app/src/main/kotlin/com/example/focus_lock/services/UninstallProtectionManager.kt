package com.example.focus_lock.services

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.util.Log

/**
 * Manages the uninstall protection state: cooldown window, challenge completion,
 * and device administrator activation.
 */
object UninstallProtectionManager {
    private const val TAG = "UninstallProtection"
    private const val PREFS_NAME = "uninstall_protection_prefs"
    private const val KEY_CHALLENGE_COMPLETED_AT = "challenge_completed_at"
    private const val KEY_PROTECTION_ENABLED = "protection_enabled"
    private const val COOLDOWN_WINDOW_MS = 5L * 60L * 1000L  // 5 minutes
    const val REQUIRED_PUSHUPS = 200

    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        if (!::prefs.isInitialized) {
            prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        }
    }

    /**
     * Check if device administrator is currently active for this app.
     */
    fun isDeviceAdminActive(context: Context): Boolean {
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val adminComponent = ComponentName(context, FocusLockDeviceAdminReceiver::class.java)
        return dpm.isAdminActive(adminComponent)
    }

    /**
     * Record that the pushup challenge has been completed.
     * Opens a 5-minute cooldown window where uninstall is allowed.
     */
    fun onChallengeCompleted() {
        prefs.edit()
            .putLong(KEY_CHALLENGE_COMPLETED_AT, System.currentTimeMillis())
            .apply()
        Log.d(TAG, "Challenge completed — 5-minute cooldown window started")
    }

    /**
     * Check if uninstall is currently allowed (within cooldown window).
     */
    fun isUninstallAllowed(): Boolean {
        val completedAt = prefs.getLong(KEY_CHALLENGE_COMPLETED_AT, 0L)
        if (completedAt == 0L) return false
        val elapsed = System.currentTimeMillis() - completedAt
        val allowed = elapsed < COOLDOWN_WINDOW_MS
        Log.d(TAG, "Uninstall allowed: $allowed (elapsed: ${elapsed / 1000}s of ${COOLDOWN_WINDOW_MS / 1000}s)")
        return allowed
    }

    /**
     * Get remaining seconds in the cooldown window.
     */
    fun getCooldownRemainingSeconds(): Long {
        val completedAt = prefs.getLong(KEY_CHALLENGE_COMPLETED_AT, 0L)
        if (completedAt == 0L) return 0L
        val elapsed = System.currentTimeMillis() - completedAt
        val remaining = COOLDOWN_WINDOW_MS - elapsed
        return if (remaining > 0) remaining / 1000 else 0L
    }

    /**
     * Reset the challenge completion (protection reactivates).
     */
    fun resetChallenge() {
        prefs.edit().remove(KEY_CHALLENGE_COMPLETED_AT).apply()
        Log.d(TAG, "Challenge reset — protection reactivated")
    }

    /**
     * Mark protection as enabled.
     */
    fun setProtectionEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_PROTECTION_ENABLED, enabled).apply()
    }

    /**
     * Check if protection is enabled.
     */
    fun isProtectionEnabled(): Boolean {
        return prefs.getBoolean(KEY_PROTECTION_ENABLED, false)
    }

    /**
     * Programmatically remove device admin (only during cooldown window).
     */
    fun removeDeviceAdmin(context: Context): Boolean {
        if (!isUninstallAllowed()) {
            Log.w(TAG, "Cannot remove device admin — challenge not completed or cooldown expired")
            return false
        }
        try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val adminComponent = ComponentName(context, FocusLockDeviceAdminReceiver::class.java)
            if (dpm.isAdminActive(adminComponent)) {
                dpm.removeActiveAdmin(adminComponent)
                Log.d(TAG, "Device admin removed — uninstall now possible")
            }
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error removing device admin: ${e.message}")
            return false
        }
    }

    /**
     * Get the full protection status as a map for Flutter.
     */
    fun getStatus(context: Context): Map<String, Any> {
        return mapOf(
            "isDeviceAdminActive" to isDeviceAdminActive(context),
            "isProtectionEnabled" to isProtectionEnabled(),
            "isUninstallAllowed" to isUninstallAllowed(),
            "cooldownRemainingSeconds" to getCooldownRemainingSeconds(),
            "requiredPushups" to REQUIRED_PUSHUPS,
            "isIconHidden" to AppIconManager.isIconHidden(context)
        )
    }
}
