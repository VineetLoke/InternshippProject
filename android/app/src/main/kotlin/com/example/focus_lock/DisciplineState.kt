package com.example.focus_lock

/**
 * Strict state machine for the discipline control system.
 *
 * Flow:
 *  IDLE
 *    → APP_BLOCKED           when Instagram, Twitter/X, or Reddit opens
 *    → WARNING_DISPLAYED     when Chrome incognito keyword detected
 *
 *  APP_BLOCKED
 *    → IDLE                  when user navigates away from blocked app
 *
 *  WARNING_DISPLAYED
 *    → IDLE                  after 3-second quote display + tab close
 *
 *  REDDIT_CHALLENGE_ACTIVE
 *    → REDDIT_TEMP_UNLOCK    when 100 pushups completed
 *    → APP_BLOCKED           if user cancels challenge
 *
 *  REDDIT_TEMP_UNLOCK
 *    → APP_BLOCKED           when 10-minute timer expires
 */
enum class DisciplineState {
    IDLE,
    APP_BLOCKED,
    WARNING_DISPLAYED,
    REDDIT_CHALLENGE_ACTIVE,
    REDDIT_TEMP_UNLOCK
}
