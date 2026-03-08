package com.example.focus_lock.controllers

/**
 * Strict state machine for the discipline control system.
 *
 * Flow:
 *  IDLE
 *    → APP_BLOCKED                when Instagram, Twitter/X, or Reddit opens
 *    → CHROME_INCOGNITO_BLOCKED   when Chrome incognito search contains blocked keyword
 *
 *  APP_BLOCKED
 *    → IDLE                       when user navigates away from blocked app
 *
 *  CHROME_INCOGNITO_BLOCKED
 *    → IDLE                       after 3-second warning + BACK action
 *    → IDLE                       if user leaves Chrome during warning
 *
 *  WARNING_DISPLAYED
 *    → IDLE                       (reserved for future use)
 *
 *  REDDIT_CHALLENGE_ACTIVE
 *    → REDDIT_TEMP_UNLOCK         when 100 pushups completed
 *    → APP_BLOCKED                if user cancels challenge
 *
 *  REDDIT_TEMP_UNLOCK
 *    → APP_BLOCKED                when 10-minute timer expires
 */
enum class DisciplineState {
    IDLE,
    APP_BLOCKED,
    CHROME_INCOGNITO_BLOCKED,
    WARNING_DISPLAYED,
    REDDIT_CHALLENGE_ACTIVE,
    REDDIT_TEMP_UNLOCK
}
