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
            // Fast Check 1: Do we see an explicit "incognito" node anywhere on screen?
            val incognitoNodes = node.findAccessibilityNodeInfosByText("incognito")
            if (incognitoNodes.isNotEmpty()) {
                isIncognitoCached = true
                incognitoNodes.forEach { it.recycle() }
                return
            }
            
            // Fast Check 2: Do we see the Chrome tab switcher button?
            val tabSwitchers = node.findAccessibilityNodeInfosByViewId("com.android.chrome:id/tab_switcher_button")
            if (tabSwitchers.isNotEmpty()) {
                // If a tab switcher is visible but NO "incognito" text was found anywhere on screen,
                // this is a normal tab window. (The incognito tab switcher explicitly contains "incognito").
                isIncognitoCached = false
                tabSwitchers.forEach { it.recycle() }
                return
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error evaluating incognito state: ${e.message}")
        }
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

        // Deep check is authoritative.
        val isCurrentlyIncognito = isIncognitoMode(rootNode)
        
        // Update cache
        if (isCurrentlyIncognito) {
            isIncognitoCached = true
        }

        // If deep scan is false, verify if we should fall back to cache.
        // We only trust the cache if the node structure is extremely sparse (childCount <= 2),
        // indicating that we might be in a keyboard-focused state where the URL/tabs bar is temporarily detached.
        if (!isCurrentlyIncognito) {
            val isSparse = rootNode.childCount <= 2
            if (!isSparse || !isIncognitoCached) {
                return false
            }
        }

        lastBlockTime = now
        Log.d(TAG, "BLOCKED — typing detected in Chrome incognito")
        return true
    }

    /** Reset debounce timer and cache (called on state transition to IDLE). */
    fun resetDebounce() {
        lastBlockTime = 0L
        isIncognitoCached = false
    }

    fun resetCache() {
        isIncognitoCached = false
        Log.d(TAG, "Chrome incognito cache reset")
    }
}
