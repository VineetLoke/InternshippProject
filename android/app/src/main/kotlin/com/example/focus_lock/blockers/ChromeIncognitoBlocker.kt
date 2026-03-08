package com.example.focus_lock.blockers

import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import java.util.regex.Pattern

/**
 * Chrome incognito keyword blocker — accessibility-tree approach.
 *
 * Activates ONLY when ALL three conditions are true:
 *  1. Chrome is the foreground app
 *  2. Chrome is in incognito mode (detected via accessibility tree)
 *  3. The URL bar / search text contains a blocked keyword
 *
 * Design rules:
 *  • Completely isolated from Instagram, Reddit, Twitter blockers.
 *  • Normal Chrome browsing is NEVER affected.
 *  • Only incognito searches containing blocked terms trigger the warning.
 *  • Uses AccessibilityNodeInfo tree scanning — no enterprise policy required.
 */
object ChromeIncognitoBlocker {
    private const val TAG = "ChromeIncognitoBlocker"
    const val CHROME_PACKAGE = "com.android.chrome"

    // Chrome accessibility resource IDs for the URL / search bar
    private const val URL_BAR_ID = "com.android.chrome:id/url_bar"
    private const val SEARCH_BOX_ID = "com.android.chrome:id/search_box_text"

    // Debounce: don't re-trigger within 5 seconds of a block
    private const val BLOCK_DEBOUNCE_MS = 5000L
    @Volatile private var lastBlockTime = 0L

    // ── Blocked keyword set (case-insensitive) ───────────────────
    private val BLOCKED_KEYWORDS = setOf(
        "adult", "porn", "pornography", "explicit", "nsfw",
        "erotic", "sex", "sexual", "sexy", "fetish", "bdsm",
        "cam", "escort", "adultvideo", "adultcontent", "adultchat",
        "hookup", "sexchat", "eroticvideo", "sexvideo", "pornvideo",
        "adultstream", "adultsite", "maturecontent", "adultmovie",
        "strip", "striptease", "cybersex", "sexshop", "sexsite",
        "adultcam", "livecam", "adultdating", "adultforum",
        "sexforum", "adultmedia", "eroticmedia", "pornmedia",
        "adultnetwork", "eroticnetwork", "pornnetwork",
        "adultgallery", "sexgallery", "eroticgallery", "pornlibrary",
        "adultvideos", "eroticvideos", "adulttube", "pornsite",
        "pornhub", "redtube", "xvideos", "xnxx", "youporn",
        "tube8", "hentai", "rule34", "onlyfans", "fansly",
        "banged", "chaturbate"
    )

    // ── Regex pattern with word boundaries ───────────────────────
    private val KEYWORD_PATTERN: Pattern = Pattern.compile(
        "\\b(porn|sex|erotic|adult|nsfw|cam|escort|fetish|bdsm|hentai|" +
        "xvideos|xnxx|pornhub|redtube|youporn|tube8|rule34|onlyfans|" +
        "fansly|chaturbate|hookup|striptease|cybersex|livecam|banged|" +
        "pornography|explicit|sexual|sexy|strip|pornsite|adulttube)\\b",
        Pattern.CASE_INSENSITIVE
    )

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
    // URL / search text extraction
    // ══════════════════════════════════════════════════════════════

    /** Extract text from Chrome's URL bar or search box. */
    fun extractUrlBarText(rootNode: AccessibilityNodeInfo): String? {
        return try {
            // Try the main URL bar first
            val urlBarNodes = rootNode.findAccessibilityNodeInfosByViewId(URL_BAR_ID)
            for (node in urlBarNodes) {
                val text = node.text?.toString()
                if (!text.isNullOrBlank()) return text
            }
            // Fall back to the search box
            val searchNodes = rootNode.findAccessibilityNodeInfosByViewId(SEARCH_BOX_ID)
            for (node in searchNodes) {
                val text = node.text?.toString()
                if (!text.isNullOrBlank()) return text
            }
            null
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting URL text: ${e.message}")
            null
        }
    }

    /** Extract text from an AccessibilityEvent's text list (TYPE_VIEW_TEXT_CHANGED). */
    fun extractEventText(eventText: List<CharSequence>?): String? {
        if (eventText.isNullOrEmpty()) return null
        return eventText.joinToString(" ") { it.toString() }.takeIf { it.isNotBlank() }
    }

    // ══════════════════════════════════════════════════════════════
    // Keyword matching
    // ══════════════════════════════════════════════════════════════

    /** Returns true if text contains any blocked keyword (set lookup + regex). */
    fun containsBlockedKeyword(text: String): Boolean {
        val lower = text.lowercase()

        // Fast set-based lookup
        for (keyword in BLOCKED_KEYWORDS) {
            if (lower.contains(keyword)) return true
        }
        // Regex word-boundary check
        if (KEYWORD_PATTERN.matcher(lower).find()) return true

        return false
    }

    // ══════════════════════════════════════════════════════════════
    // Blocking decisions
    // ══════════════════════════════════════════════════════════════

    /**
     * Full blocking decision via tree scan.
     * Returns true only when incognito + keyword + not debounced.
     */
    fun shouldBlock(rootNode: AccessibilityNodeInfo): Boolean {
        val now = System.currentTimeMillis()
        if (now - lastBlockTime < BLOCK_DEBOUNCE_MS) return false

        if (!isIncognitoMode(rootNode)) return false

        val text = extractUrlBarText(rootNode) ?: return false
        if (!containsBlockedKeyword(text)) return false

        lastBlockTime = now
        Log.d(TAG, "BLOCKED — incognito keyword detected in: $text")
        return true
    }

    /**
     * Blocking decision using event text (fast path for TYPE_VIEW_TEXT_CHANGED).
     * Incognito state must be confirmed separately before calling.
     */
    fun shouldBlockEventText(eventText: String, isIncognito: Boolean): Boolean {
        if (!isIncognito) return false

        val now = System.currentTimeMillis()
        if (now - lastBlockTime < BLOCK_DEBOUNCE_MS) return false

        if (!containsBlockedKeyword(eventText)) return false

        lastBlockTime = now
        Log.d(TAG, "BLOCKED — incognito keyword in typed text: $eventText")
        return true
    }

    /** Reset debounce timer (called on state transition to IDLE). */
    fun resetDebounce() {
        lastBlockTime = 0L
    }
}
