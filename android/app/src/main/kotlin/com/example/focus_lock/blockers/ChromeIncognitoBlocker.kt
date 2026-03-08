package com.example.focus_lock.blockers

import android.content.Context
import android.util.Log
import com.example.focus_lock.services.ChromeIncognitoPolicy

/**
 * Chrome incognito mode blocker — policy-based approach.
 *
 * Uses Chrome's managed configuration policy (IncognitoModeAvailability: 1)
 * via DevicePolicyManager.setApplicationRestrictions() to completely disable
 * incognito mode in Chrome. No Accessibility tree scanning required.
 *
 * Requires the app to be Device Owner or Profile Owner.
 *
 * Design rules:
 *  • Completely isolated from Instagram, Reddit, Twitter blockers.
 *  • No UI overlays — Chrome itself shows "disabled by administrator".
 *  • Normal browsing is never affected.
 */
object ChromeIncognitoBlocker {
    private const val TAG = "ChromeIncognitoBlocker"
    const val CHROME_PACKAGE = "com.android.chrome"

    @Volatile private var initialized = false
    private lateinit var appContext: Context

    fun init(context: Context) {
        if (initialized) return
        appContext = context.applicationContext
        initialized = true

        // Auto-apply the incognito policy on init
        val applied = ChromeIncognitoPolicy.applyIncognitoPolicy(appContext)
        Log.d(TAG, "Initialized. Policy applied=$applied")
    }

    /** Status map for Flutter method channel. */
    fun getStatus(): Map<String, Any> {
        if (!initialized) {
            return mapOf(
                "isActive" to false,
                "isDeviceOwner" to false,
                "policyApplied" to false
            )
        }
        return ChromeIncognitoPolicy.getStatus(appContext)
    }
}
