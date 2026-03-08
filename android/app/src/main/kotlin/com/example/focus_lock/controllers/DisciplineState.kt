package com.example.focus_lock.controllers

/**
 * Strict state machine for the discipline control system.
 *
 * Flow:
 *  IDLE
 *    → APP_BLOCKED           when Instagram, Twitter/X, or Reddit opens
 *
 *  APP_BLOCKED
 *    → IDLE                  when user navigates away from blocked app
 *
 *  WARNING_DISPLAYED
 *    → IDLE                  (reserved for future use)
 *
 *  REDDIT_CHALLENGE_ACTIVE
 *    → REDDIT_TEMP_UNLOCK    when 100 pushups completed
 *    → APP_BLOCKED           if user cancels challenge
 *
 *  REDDIT_TEMP_UNLOCK
 *    → APP_BLOCKED           when 10-minute timer expires
 *
 * Note: Chrome incognito is now disabled via enterprise policy
 * (IncognitoModeAvailability: 1) — no Accessibility monitoring needed.
 */
enum class DisciplineState {
    IDLE,
    APP_BLOCKED,
    WARNING_DISPLAYED,
    REDDIT_CHALLENGE_ACTIVE,
    REDDIT_TEMP_UNLOCK
}
