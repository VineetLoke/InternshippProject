package com.example.focus_lock.services

import android.content.Context
import android.content.SharedPreferences

/**
 * The sole authority for FocusLock enforcement state.  Flutter may display this
 * state, but all lock and temporary-unlock decisions are made here.
 */
object NativeLockState {
    private const val PREFS_NAME = "focus_lock_authoritative_state"
    private const val KEY_ACTIVE = "lock_active"
    private const val KEY_START = "lock_start_epoch"
    private const val KEY_DURATION_DAYS = "lock_duration_days"
    private const val DEFAULT_DURATION_DAYS = 30
    const val TEMP_UNLOCK_MS = 10L * 60L * 1000L

    const val INSTAGRAM = "com.instagram.android"
    const val REDDIT = "com.reddit.frontpage"
    const val TWITTER = "com.twitter.android"
    const val CHROME = "com.android.chrome"
    const val CHROME_BETA = "com.chrome.beta"
    const val CHROME_DEV = "com.chrome.dev"
    const val CHROME_CANARY = "com.chrome.canary"

    val chromePackages = setOf(CHROME, CHROME_BETA, CHROME_DEV, CHROME_CANARY)
    // Known limitation: package coverage is intentionally limited to the
    // declared targets; alternate social apps and browsers are out of scope.
    val socialPackages = setOf(INSTAGRAM, REDDIT, TWITTER)
    val protectedPackages = socialPackages + chromePackages

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** Called only when the user completes initial setup. Never rewrites an active lock. */
    fun activateIfNeeded(context: Context): Boolean {
        val p = prefs(context)
        if (isLockActive(context)) return true
        return p.edit()
            .putBoolean(KEY_ACTIVE, true)
            .putLong(KEY_START, System.currentTimeMillis())
            .putInt(KEY_DURATION_DAYS, DEFAULT_DURATION_DAYS)
            .commit()
    }

    fun isLockActive(context: Context): Boolean {
        val p = prefs(context)
        if (!p.getBoolean(KEY_ACTIVE, false)) return false
        val start = p.getLong(KEY_START, 0L)
        val duration = p.getInt(KEY_DURATION_DAYS, DEFAULT_DURATION_DAYS)
        return start > 0L && System.currentTimeMillis() - start < duration * 24L * 60L * 60L * 1000L
    }

    fun isTargetBlocked(context: Context, packageName: String): Boolean =
        packageName in protectedPackages && isLockActive(context) && !isTempUnlockActive(context, packageName)

    fun isTempUnlockActive(context: Context, packageName: String): Boolean {
        val expiry = prefs(context).getLong(unlockKey(packageName), 0L)
        return expiry > System.currentTimeMillis()
    }

    fun getTempUnlockRemainingSeconds(context: Context, packageName: String): Long {
        val remaining = prefs(context).getLong(unlockKey(packageName), 0L) - System.currentTimeMillis()
        return if (remaining > 0L) remaining / 1000L else 0L
    }

    fun grantTemporaryUnlock(context: Context, packageName: String): Boolean {
        if (packageName !in protectedPackages || !isLockActive(context)) return false
        return prefs(context).edit()
            .putLong(unlockKey(packageName), System.currentTimeMillis() + TEMP_UNLOCK_MS)
            .commit()
    }

    fun getRemainingDays(context: Context): Int {
        val p = prefs(context)
        val end = p.getLong(KEY_START, 0L) + p.getInt(KEY_DURATION_DAYS, DEFAULT_DURATION_DAYS) * 24L * 60L * 60L * 1000L
        val remaining = end - System.currentTimeMillis()
        return if (isLockActive(context) && remaining > 0L) (remaining / (24L * 60L * 60L * 1000L)).toInt() + 1 else 0
    }

    fun status(context: Context): Map<String, Any> = mapOf(
        "locked" to isLockActive(context),
        "remainingDays" to getRemainingDays(context)
    )

    private fun unlockKey(packageName: String) = "temp_unlock_expiry_$packageName"
}
