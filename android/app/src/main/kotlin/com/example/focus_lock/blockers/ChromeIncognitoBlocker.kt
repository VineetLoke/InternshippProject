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
     * Returns true only if a strict incognito indicator (view id or content
     * description containing "incognito") exists in the tree. Page body *text*
     * is intentionally NOT used as proof to avoid false positives from menus
     * and tooltips like "Open incognito tab".
     */
    private fun scanTreeForIncognito(
        node: AccessibilityNodeInfo,
        depth: Int,
        logScan: Boolean,
    ): Boolean {
        if (depth > MAX_TREE_DEPTH) return false

        if (logScan) logCandidate(node)

        val viewId = node.viewIdResourceName
        if (viewId != null && viewId.lowercase().contains("incognito")) {
            Log.d(TAG, "Incognito indicator via viewId='$viewId'")
            return true
        }

        val desc = node.contentDescription?.toString()?.lowercase()
        if (desc != null && desc.contains("incognito")) {
            Log.d(TAG, "Incognito indicator via contentDescription='$desc'")
            return true
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = scanTreeForIncognito(child, depth + 1, logScan)
            child.recycle()
            if (found) return true
        }
        return false
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
