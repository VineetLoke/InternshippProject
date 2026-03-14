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

    // Maximum tree depth to prevent runaway recursion
    private const val MAX_TREE_DEPTH = 20

    // ══════════════════════════════════════════════════════════════
    // Incognito detection
    // ══════════════════════════════════════════════════════════════

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

                    if (viewId != null && viewId.contains("incognito")) return true
                    if (desc.contains("incognito")) return true
                    if (text.contains("incognito")) return true
                }
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
            if (scanTreeForIncognito(child, depth + 1)) return true
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

        if (!isIncognitoMode(rootNode)) return false

        lastBlockTime = now
        Log.d(TAG, "BLOCKED — typing detected in Chrome incognito")
        return true
    }

    /** Reset debounce timer (called on state transition to IDLE). */
    fun resetDebounce() {
        lastBlockTime = 0L
    }
}
