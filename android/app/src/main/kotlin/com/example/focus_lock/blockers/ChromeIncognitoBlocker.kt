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
    private const val MAX_TREE_DEPTH = 20

    // ══════════════════════════════════════════════════════════════
    // Incognito detection
    // ══════════════════════════════════════════════════════════════

    /**
     * Fast-path heuristic to track incognito mode state across UI changes.
     * Evaluates whether the screen definitively shows an incognito indicator or a normal tab indicator.
     */
    fun evaluateIncognitoState(node: AccessibilityNodeInfo?) {
        if (node == null) return
        try {
            // Check 1: Look for incognito BADGE specifically (not just any "incognito" text)
            // The badge/indicator has a specific view ID — the homepage button does NOT
            val incognitoBadge = node.findAccessibilityNodeInfosByViewId("com.android.chrome:id/incognito_badge")
            if (incognitoBadge.isNotEmpty()) {
                isIncognitoCached = true
                incognitoBadge.forEach { it.recycle() }
                Log.d(TAG, "Incognito badge found — incognito mode ON")
                return
            }

            val incognitoIndicator = node.findAccessibilityNodeInfosByViewId("com.android.chrome:id/incognito_indicator")
            if (incognitoIndicator.isNotEmpty()) {
                isIncognitoCached = true
                incognitoIndicator.forEach { it.recycle() }
                Log.d(TAG, "Incognito indicator found — incognito mode ON")
                return
            }

            // Check 2: Tab switcher with incognito count label
            // When in incognito, the tab switcher shows "incognito" in its content description
            val tabSwitchers = node.findAccessibilityNodeInfosByViewId("com.android.chrome:id/tab_switcher_button")
            if (tabSwitchers.isNotEmpty()) {
                val isInIncognitoWindow = tabSwitchers.any { tab ->
                    val desc = tab.contentDescription?.toString()?.lowercase() ?: ""
                    // Real incognito tab switcher says something like "2 incognito tabs"
                    // Homepage button just says "Incognito" with no number
                    desc.matches(Regex(".*\d+.*incognito.*")) || desc.matches(Regex(".*incognito.*\d+.*"))
                }
                tabSwitchers.forEach { it.recycle() }
                if (isInIncognitoWindow) {
                    isIncognitoCached = true
                    Log.d(TAG, "Incognito tab switcher found — incognito mode ON")
                    return
                }
            }

            // Check 3: URL bar background is dark in incognito — check toolbar color node
            val toolbars = node.findAccessibilityNodeInfosByViewId("com.android.chrome:id/toolbar")
            if (toolbars.isNotEmpty()) {
                // Normal tab toolbar exists — we are NOT in incognito
                toolbars.forEach { it.recycle() }
                isIncognitoCached = false
                return
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error evaluating incognito state: ${e.message}")
        }
        isIncognitoCached = false
    }

    /**
     * Detect incognito mode by scanning Chrome's accessibility tree
     * for incognito-specific UI elements (badge, buttons, descriptions).
     */
    fun isIncognitoMode(rootNode: AccessibilityNodeInfo): Boolean {
        return try {
            // Fast path: search for nodes containing "incognito" text
            val incognitoNodes = rootNode.findAccessibilityNodeInfosByText("incognito")
            if (incognitoNodes.isNotEmpty()) {
                for (node in incognitoNodes) {
                    val viewId = node.viewIdResourceName
                    val desc = node.contentDescription?.toString()?.lowercase() ?: ""
                    val text = node.text?.toString()?.lowercase() ?: ""

                    val match = (viewId != null && viewId.contains("incognito")) ||
                                desc.contains("incognito") ||
                                text.contains("incognito")
                    if (match) {
                        // Recycle all returned nodes before returning
                        incognitoNodes.forEach { it.recycle() }
                        return true
                    }
                }
                // No match on fast path — recycle before deep scan
                incognitoNodes.forEach { it.recycle() }
            }
            // Deep scan: walk the tree looking for incognito indicators
            scanTreeForIncognito(rootNode, 0)
        } catch (e: Exception) {
            Log.e(TAG, "Error detecting incognito: ${e.message}")
            false
        }
    }

    private fun scanTreeForIncognito(node: AccessibilityNodeInfo, depth: Int): Boolean {
        if (depth > MAX_TREE_DEPTH) return false

        val viewId = node.viewIdResourceName
        if (viewId != null && viewId.contains("incognito")) return true

        val desc = node.contentDescription?.toString()?.lowercase()
        if (desc != null && desc.contains("incognito")) return true

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (scanTreeForIncognito(child, depth + 1)) {
                child.recycle()
                return true
            }
            child.recycle()
        }
        return false
    }

    // ══════════════════════════════════════════════════════════════
    // Blocking decision — any typing in incognito triggers block
    // ══════════════════════════════════════════════════════════════

    /**
     * Returns true when a text-changed event should trigger the blocker.
     * Checks: incognito mode active + not within debounce window.
     */
    fun shouldBlockTyping(rootNode: AccessibilityNodeInfo): Boolean {
        val now = System.currentTimeMillis()
        if (now - lastBlockTime < BLOCK_DEBOUNCE_MS) return false

        // Check cached state first, fallback to deep check
        val isCurrentlyIncognito = isIncognitoCached || isIncognitoMode(rootNode)
        if (!isCurrentlyIncognito) return false

        lastBlockTime = now
        Log.d(TAG, "BLOCKED — typing detected in Chrome incognito")
        return true
    }

    /** Reset debounce timer (called on state transition to IDLE). */
    fun resetDebounce() {
        lastBlockTime = 0L
    }
}
