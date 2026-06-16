package com.example.focus_lock.blockers

import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Chrome incognito typing blocker — accessibility-tree approach.
 *
 * Activates ONLY when ALL three conditions are true:
 *  1. Chrome is the foreground app
 *  2. Chrome is in incognito mode (detected via accessibility tree)
 *  3. A text input event (TYPE_VIEW_TEXT_CHANGED) occurs
 *
 * Design rules:
 *  • No keyword lists. No pattern matching.
 *  • Any single typed character in incognito triggers the block.
 *  • Normal Chrome browsing is NEVER affected.
 *  • Uses AccessibilityNodeInfo tree scanning — no enterprise policy required.
 *
 * IMPORTANT (bug fix): incognito detection must be based on incognito-SPECIFIC
 * node indicators (a view id containing "incognito", or a content description
 * containing "incognito") — NOT on the bare package name, and NOT on a stray
 * substring "incognito" found anywhere in page body text (e.g. the "Open
 * incognito tab" menu item / tooltip). The cached state is recomputed and set
 * true OR false on every evaluation so it can never get stuck.
 */
object ChromeIncognitoBlocker {
    private const val TAG = "ChromeIncognitoBlocker"
    const val CHROME_PACKAGE = "com.android.chrome"

    // Debounce: don't re-trigger within 5 seconds of a block
    private const val BLOCK_DEBOUNCE_MS = 5000L
    @Volatile private var lastBlockTime = 0L

    @Volatile var isIncognitoCached = false
        private set

    // Maximum tree depth to prevent runaway recursion
    private const val MAX_TREE_DEPTH = 25

    // Cap how many candidate nodes we log per scan to avoid log spam
    private const val MAX_LOGGED_NODES = 12

    // ═══════════════════════════════════════════════════════════
    // Incognito detection
    // ═══════════════════════════════════════════════════════════

    /**
     * Authoritatively recompute incognito state from the current node tree and
     * update [isIncognitoCached]. Sets the cache to true OR false on EVERY call
     * so a stale "true" can never persist across normal tabs.
     *
     * Only strict incognito-specific indicators count as proof:
     *  • viewIdResourceName containing "incognito"
     *    (e.g. "com.android.chrome:id/incognito_icon", tab-strip incognito ids)
     *  • contentDescription containing "incognito"
     */
    fun evaluateIncognitoState(node: AccessibilityNodeInfo?) {
        if (node == null) return
        try {
            loggedThisScan = 0
            val detected = scanTreeForIncognito(node, 0, logScan = true)
            if (detected != isIncognitoCached) {
                Log.d(TAG, "Incognito cache: $isIncognitoCached -> $detected")
            }
            isIncognitoCached = detected
        } catch (e: Exception) {
            Log.e(TAG, "Error evaluating incognito state: ${e.message}")
            // On error, fail safe to NOT incognito so we never block normal browsing.
            isIncognitoCached = false
        }
    }

    /**
     * Detect incognito mode by scanning Chrome's accessibility tree for
     * incognito-SPECIFIC UI elements (incognito icon / badge view id or
     * content description). Does not update the cache.
     */
    fun isIncognitoMode(rootNode: AccessibilityNodeInfo): Boolean {
        return try {
            scanTreeForIncognito(rootNode, 0, logScan = false)
        } catch (e: Exception) {
            Log.e(TAG, "Error detecting incognito: ${e.message}")
            false
        }
    }

    /**
     * Returns true only if a strict incognito indicator exists AND we're not in
     * the tab switcher. Tab switcher shows incognito tab previews even when you're
     * viewing normal tabs, causing false positives.
     *
     * Detection rules:
     * 1. First check if tab switcher / overview is open - if so, return false
     * 2. Look for active incognito indicators (toolbar, focused EditText context)
     * 3. Exclude menu items and buttons
     */
    private fun scanTreeForIncognito(
        node: AccessibilityNodeInfo,
        depth: Int,
        logScan: Boolean,
    ): Boolean {
        if (depth > MAX_TREE_DEPTH) return false

        // CRITICAL: Check if tab switcher is open - abort immediately if so
        if (depth == 0 && isTabSwitcherOpen(node)) {
            Log.d(TAG, "Tab switcher is open - ignoring incognito indicators")
            return false
        }

        if (logScan) logCandidate(node)

        val viewId = node.viewIdResourceName
        val desc = node.contentDescription?.toString()
        val descLower = desc?.lowercase()

        // Check for ACTIVE incognito indicators ONLY in browsing context
        if (viewId != null) {
            val viewIdLower = viewId.lowercase()

            // Exclude tab switcher / overview UI elements entirely
            if (viewIdLower.contains("tab_switcher") ||
                viewIdLower.contains("tab_list") ||
                viewIdLower.contains("overview") ||
                viewIdLower.contains("stack")) {
                // Skip tab management UI
                return false
            }

            // Exclude menu items and buttons that just offer to OPEN incognito
            if (viewIdLower.contains("menu") ||
                viewIdLower.contains("button") ||
                viewIdLower.contains("overflow")) {
                // Skip this - it's just a menu option
            } else {
                // Look for incognito indicators in the active browsing context
                // Check for toolbar-level indicators (most reliable)
                if (viewIdLower.contains("toolbar") && viewIdLower.contains("incognito")) {
                    Log.d(TAG, "MATCH: Incognito toolbar viewId='$viewId'")
                    return true
                }

                // Check for URL bar in incognito mode
                if (viewIdLower.contains("url_bar") && viewIdLower.contains("incognito")) {
                    Log.d(TAG, "MATCH: Incognito URL bar viewId='$viewId'")
                    return true
                }

                // Check for new tab page in incognito
                if (viewIdLower.contains("incognito_ntp") ||
                    (viewIdLower.contains("ntp") && viewIdLower.contains("incognito"))) {
                    Log.d(TAG, "MATCH: Incognito NTP viewId='$viewId'")
                    return true
                }

                // Selected incognito element in browsing context
                if (viewIdLower.contains("incognito") && node.isSelected &&
                    !viewIdLower.contains("tab_")) {
                    Log.d(TAG, "MATCH: Selected incognito viewId='$viewId'")
                    return true
                }
            }
        }

        // Content descriptions in active browsing context
        if (descLower != null && descLower.contains("incognito")) {
            // Exclude menu items and options
            if (descLower.contains("new incognito") ||
                descLower.contains("open incognito") ||
                descLower.contains("menu") ||
                descLower.contains("button") ||
                descLower.contains("tab list")) {
                // This is just an option or tab switcher UI
            } else if (node.isSelected || node.isFocused || node.isAccessibilityFocused) {
                // Active element in browsing context
                Log.d(TAG, "MATCH: Active incognito contentDescription='$desc'")
                return true
            } else if (descLower.contains("incognito mode") || descLower.contains("incognito tab,")) {
                // Active incognito state indicator
                Log.d(TAG, "MATCH: Incognito state contentDescription='$desc'")
                return true
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = scanTreeForIncognito(child, depth + 1, logScan)
            child.recycle()
            if (found) return true
        }
        return false
    }

    /**
     * Check if Chrome's tab switcher / overview is currently open.
     * Tab switcher shows incognito tabs alongside normal tabs, so we must
     * ignore all incognito indicators when it's active.
     */
    private fun isTabSwitcherOpen(rootNode: AccessibilityNodeInfo): Boolean {
        return findNodeByViewIdSubstring(rootNode, "tab_switcher", 0) != null ||
               findNodeByViewIdSubstring(rootNode, "tab_list_view", 0) != null ||
               findNodeByViewIdSubstring(rootNode, "overview_mode", 0) != null
    }

    /**
     * Search for a node with a viewId containing the given substring.
     * Returns the first match or null.
     */
    private fun findNodeByViewIdSubstring(
        node: AccessibilityNodeInfo,
        substring: String,
        depth: Int
    ): AccessibilityNodeInfo? {
        if (depth > 15) return null  // Limit search depth

        val viewId = node.viewIdResourceName?.lowercase()
        if (viewId != null && viewId.contains(substring)) {
            return node
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findNodeByViewIdSubstring(child, substring, depth + 1)
            if (found != null) {
                child.recycle()
                return found
            }
            child.recycle()
        }
        return null
    }

    // Logs view ids / content descriptions that look toolbar/tab related so
    // misfires can be debugged via logcat. Capped to avoid log spam.
    private var loggedThisScan = 0
    private fun logCandidate(node: AccessibilityNodeInfo) {
        if (loggedThisScan >= MAX_LOGGED_NODES) return
        val viewId = node.viewIdResourceName
        val desc = node.contentDescription?.toString()
        if (viewId != null || desc != null) {
            // Reset counter implicitly per top-level scan via depth==0 callers.
            loggedThisScan++
            Log.d(TAG, "scan node viewId='${viewId ?: "-"}' desc='${desc ?: "-"}'")
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Blocking decision — any typing in incognito triggers block
    // ═══════════════════════════════════════════════════════════

    /**
     * Returns true when a text-changed event should trigger the blocker.
     * Re-evaluates incognito state from the live tree (authoritative) instead
     * of trusting a possibly-stale cache, then applies the debounce.
     */
    fun shouldBlockTyping(rootNode: AccessibilityNodeInfo): Boolean {
        val now = System.currentTimeMillis()
        if (now - lastBlockTime < BLOCK_DEBOUNCE_MS) return false

        // Recompute from the live tree so a stale cache cannot cause a block.
        evaluateIncognitoState(rootNode)
        if (!isIncognitoCached) return false

        lastBlockTime = now
        Log.d(TAG, "BLOCKED — typing detected in Chrome incognito")
        return true
    }

    /** Reset debounce timer (called on state transition to IDLE). */
    fun resetDebounce() {
        lastBlockTime = 0L
        isIncognitoCached = false
    }
}
