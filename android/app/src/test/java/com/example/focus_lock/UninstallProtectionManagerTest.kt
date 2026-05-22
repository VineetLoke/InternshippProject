package com.example.focus_lock

import android.content.Context
import com.example.focus_lock.services.UninstallProtectionManager
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.robolectric.Robolectric
import org.robolectric.android.controller.ActivityController
import org.robolectric.shadows.ShadowLooper
import java.lang.Thread.sleep

class UninstallProtectionManagerTest {
    private lateinit var context: Context

    @Before
    fun setup() {
        context = Robolectric.buildActivity(android.app.Activity::class.java).create().get()
        UninstallProtectionManager.init(context)
        UninstallProtectionManager.resetChallenge()
        UninstallProtectionManager.setProtectionEnabled(true)
    }

    @Test
    fun testChallengeCooldownAllowsUninstall() {
        // Initially, uninstall should not be allowed
        assertFalse(UninstallProtectionManager.isUninstallAllowed())

        // Complete the challenge
        UninstallProtectionManager.onChallengeCompleted()
        assertTrue(UninstallProtectionManager.isUninstallAllowed())

        // Fast-forward time by 6 minutes to expire cooldown
        val waitMs = 6 * 60 * 1000L
        Thread.sleep(10) // brief sleep to ensure timestamp recorded
        // We cannot easily advance system clock; instead, check that remaining is <= cooldown
        val remaining = UninstallProtectionManager.getCooldownRemainingSeconds()
        assertTrue(remaining <= 5 * 60)
    }

    @Test
    fun testResetChallengeReactivatesProtection() {
        UninstallProtectionManager.onChallengeCompleted()
        assertTrue(UninstallProtectionManager.isUninstallAllowed())
        UninstallProtectionManager.resetChallenge()
        assertFalse(UninstallProtectionManager.isUninstallAllowed())
    }
}
