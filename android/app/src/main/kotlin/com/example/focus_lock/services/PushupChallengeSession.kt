package com.example.focus_lock.services

import android.content.Context
import java.util.UUID

/**
 * Fail-closed native gate for temporary access. Sessions are intentionally
 * in-memory: process death invalidates a challenge rather than granting access.
 */
object PushupChallengeSession {
    private const val SESSION_TTL_MS = 30L * 60L * 1000L

    private data class Session(
        val token: String,
        val target: String,
        val requiredReps: Int,
        val expiresAt: Long,
        var recordedReps: Int = 0
    )

    @Volatile private var session: Session? = null

    @Synchronized
    fun begin(context: Context, target: String, requiredReps: Int): String? {
        if (target !in NativeLockState.socialPackages || requiredReps <= 0 ||
            !NativeLockState.isTargetBlocked(context, target)) return null
        return UUID.randomUUID().toString().also {
            session = Session(it, target, requiredReps, System.currentTimeMillis() + SESSION_TTL_MS)
        }
    }

    @Synchronized
    fun recordRep(token: String): Boolean {
        val current = validSession(token) ?: return false
        if (current.recordedReps < current.requiredReps) current.recordedReps++
        return true
    }

    @Synchronized
    fun redeem(context: Context, token: String, target: String): Boolean {
        val current = validSession(token) ?: return false
        if (current.target != target || current.recordedReps < current.requiredReps) return false
        session = null // single use, before the grant is committed
        return NativeLockState.grantTemporaryUnlock(context, target)
    }

    @Synchronized
    private fun validSession(token: String): Session? {
        val current = session ?: return null
        if (current.token != token || System.currentTimeMillis() >= current.expiresAt) {
            session = null
            return null
        }
        return current
    }
}
