package com.example.focus_lock

/**
 * State machine for the discipline control system.
 *
 * States:
 *  IDLE                    — No blocking active, normal device usage
 *  WARNING_DISPLAYED       — 3-second warning overlay is showing (Chrome keyword)
 *  LOCK_ACTIVE             — Persistent Chrome lock overlay is displayed
 *  REDDIT_LOCKED           — Reddit is fully blocked, overlay showing
 *  REDDIT_CHALLENGE_ACTIVE — User is doing the 100-pushup challenge
 *  REDDIT_TEMP_UNLOCK      — Reddit temporarily unlocked for 10 minutes
 */
enum class DisciplineState {
    IDLE,
    WARNING_DISPLAYED,
    LOCK_ACTIVE,
    REDDIT_LOCKED,
    REDDIT_CHALLENGE_ACTIVE,
    REDDIT_TEMP_UNLOCK
}
