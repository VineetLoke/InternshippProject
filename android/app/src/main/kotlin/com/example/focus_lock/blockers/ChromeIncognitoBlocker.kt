package com.example.focus_lock.blockers

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import java.util.Locale
import java.util.regex.Pattern

/**
 * Deterministic Chrome incognito keyword blocker — completely isolated module.
 *
 * Design rules:
 *  • Uses its OWN SharedPreferences file ("chrome_incognito_blocker_prefs"),
 *    so Flutter "Reset Focus" (which clears FlutterSharedPreferences) has ZERO effect.
 *  • Only triggers in Chrome INCOGNITO mode when a blocked keyword is detected.
 *  • Normal browsing and video playback NEVER trigger this blocker.
 *  • The volume-up emergency bypass in the accessibility service does NOT touch this module.
 *  • Completely isolated from Instagram, Reddit, Twitter blockers.
 */
object ChromeIncognitoBlocker {
    private const val TAG = "ChromeIncognitoBlocker"
    const val CHROME_PACKAGE = "com.android.chrome"

    // Dedicated prefs file — isolated from everything else
    private const val PREFS_NAME = "chrome_incognito_blocker_prefs"
    private const val KEY_BLOCK_COUNT = "cib_block_count"

    // Debounce: 3 seconds between triggers
    private const val BLOCK_DEBOUNCE_MS = 3000L

    // Warning duration before closing tab
    const val WARNING_DURATION_MS = 3000L

    // ── Blocked keywords (exactly as specified) ───────────────────
    private val BLOCKED_KEYWORDS = listOf(
        "porn", "pornhub", "xxx", "xvideos", "xnxx",
        "redtube", "youporn", "hentai", "nsfw", "onlyfans",
        "fansly", "sexvideo", "pornvideo", "rule34", "bdsm",
        "escort", "camgirl", "chaturbate"
    )

    // Regex: word boundaries + case-insensitive
    private val KEYWORD_REGEX: Pattern = run {
        val joined = BLOCKED_KEYWORDS.joinToString("|") { Pattern.quote(it) }
        Pattern.compile("\\b($joined)\\b", Pattern.CASE_INSENSITIVE)
    }

    @Volatile private var initialized = false
    private lateinit var prefs: SharedPreferences
    private lateinit var appContext: Context

    // Debounce
    private var lastBlockTime = 0L

    // Callback fired by accessibility service to close the incognito tab
    var onCloseTab: (() -> Unit)? = null

    // Callback to show the warning overlay
    var onShowWarning: (() -> Unit)? = null

    // Callback to dismiss the warning overlay
    var onDismissWarning: (() -> Unit)? = null

    fun init(context: Context) {
        if (initialized) return
        appContext = context.applicationContext
        prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        initialized = true
        Log.d(TAG, "Initialized. blockCount=${getBlockCount()}")
    }

    // ══════════════════════════════════════════════════════════════
    // Detection — called by AccessibilityService on Chrome events
    // ══════════════════════════════════════════════════════════════

    // Chrome URL bar resource IDs (used for direct keyword scanning)
    private val CHROME_URL_BAR_IDS = listOf(
        "com.android.chrome:id/url_bar",
        "com.android.chrome:id/search_box_text",
        "com.android.chrome:id/omnibox_text_field"
    )

    // Chrome incognito indicator view IDs
    private val CHROME_INCOGNITO_IDS = listOf(
        "com.android.chrome:id/incognito_badge",
        "com.android.chrome:id/incognito_icon"
    )

    /**
     * Evaluate a Chrome content/text change event.
     *
     * @param rootNode   The root accessibility node of the active window.
     * @param eventTexts Text from the event (event.text entries).
     * @param eventDesc  Content description from the event.
     * @param sourceNode The source node of the event (may be null).
     * @return true if blocking was triggered.
     */
    fun onChromeContentChanged(
        rootNode: AccessibilityNodeInfo,
        eventTexts: List<CharSequence?>,
        eventDesc: CharSequence?,
        sourceNode: AccessibilityNodeInfo?
    ): Boolean {
        if (!initialized) return false

        // Debounce
        val now = System.currentTimeMillis()
        if (now - lastBlockTime < BLOCK_DEBOUNCE_MS) return false

        // ── CRITICAL: Only trigger in incognito mode ─────────────
        if (!isIncognito(rootNode)) return false

        // ── Scan for blocked keywords ────────────────────────────
        var keywordFound = false

        // 1. Check event text entries
        for (cs in eventTexts) {
            val text = cs?.toString() ?: continue
            if (matchesKeyword(text)) {
                Log.d(TAG, "Keyword found in event text")
                keywordFound = true
                break
            }
        }

        // 2. Check content description
        if (!keywordFound && eventDesc != null) {
            if (matchesKeyword(eventDesc.toString())) {
                Log.d(TAG, "Keyword found in content description")
                keywordFound = true
            }
        }

        // 3. Check Chrome URL bar directly (most reliable source)
        if (!keywordFound) {
            keywordFound = scanUrlBar(rootNode)
        }

        // 4. Check source node tree (depth-limited)
        if (!keywordFound && sourceNode != null) {
            keywordFound = scanNodeForKeyword(sourceNode, 0)
        }

        // 5. Broader root tree scan for keywords (deeper, catches page content)
        if (!keywordFound) {
            keywordFound = scanNodeForKeyword(rootNode, 0)
        }

        if (keywordFound) {
            lastBlockTime = now
            incrementBlockCount()
            Log.d(TAG, "Blocked keyword in INCOGNITO — triggering warning")
            onShowWarning?.invoke()
            return true
        }

        return false
    }

    // ══════════════════════════════════════════════════════════════
    // URL bar scanning — direct view ID lookup
    // ══════════════════════════════════════════════════════════════

    /**
     * Scan Chrome URL bar by known resource IDs.
     * This is the most reliable way to detect keyword searches.
     */
    private fun scanUrlBar(rootNode: AccessibilityNodeInfo): Boolean {
        for (viewId in CHROME_URL_BAR_IDS) {
            val nodes = try {
                rootNode.findAccessibilityNodeInfosByViewId(viewId)
            } catch (_: Exception) { null }

            if (nodes != null) {
                for (node in nodes) {
                    val text = node.text?.toString() ?: ""
                    val desc = node.contentDescription?.toString() ?: ""
                    try {
                        if (text.isNotEmpty() && matchesKeyword(text)) {
                            Log.d(TAG, "Keyword found in URL bar ($viewId): text")
                            return true
                        }
                        if (desc.isNotEmpty() && matchesKeyword(desc)) {
                            Log.d(TAG, "Keyword found in URL bar ($viewId): desc")
                            return true
                        }
                    } finally {
                        try { node.recycle() } catch (_: Exception) {}
                    }
                }
            }
        }
        return false
    }

    // ══════════════════════════════════════════════════════════════
    // Incognito detection
    // ══════════════════════════════════════════════════════════════

    /**
     * Detect Chrome incognito mode using multiple strategies:
     *  1. findAccessibilityNodeInfosByText("incognito") — full tree search
     *  2. Known Chrome incognito view IDs
     *  3. Manual tree scan as fallback (depth 8)
     */
    private fun isIncognito(node: AccessibilityNodeInfo): Boolean {
        // Strategy 1: Use Android's built-in full-tree text search (most reliable)
        try {
            val matches = node.findAccessibilityNodeInfosByText("incognito")
            if (matches != null && matches.isNotEmpty()) {
                for (match in matches) {
                    try { match.recycle() } catch (_: Exception) {}
                }
                Log.d(TAG, "Incognito detected via findByText (${matches.size} nodes)")
                return true
            }
        } catch (_: Exception) {}

        // Strategy 2: Check known Chrome incognito view IDs
        for (viewId in CHROME_INCOGNITO_IDS) {
            try {
                val nodes = node.findAccessibilityNodeInfosByViewId(viewId)
                if (nodes != null && nodes.isNotEmpty()) {
                    for (n in nodes) {
                        try { n.recycle() } catch (_: Exception) {}
                    }
                    Log.d(TAG, "Incognito detected via view ID: $viewId")
                    return true
                }
            } catch (_: Exception) {}
        }

        // Strategy 3: Manual fallback scan (depth 8) for edge cases
        return scanForIncognito(node, 0)
    }

    private fun scanForIncognito(node: AccessibilityNodeInfo?, depth: Int): Boolean {
        if (node == null || depth > 8) return false

        val desc = node.contentDescription?.toString()?.lowercase(Locale.ROOT) ?: ""
        val text = node.text?.toString()?.lowercase(Locale.ROOT) ?: ""

        if ("incognito" in desc || "incognito" in text) return true
        // Also check for "private" browsing indicators
        if ("private tab" in desc || "private browsing" in desc) return true

        for (i in 0 until node.childCount) {
            val child = try { node.getChild(i) } catch (_: Exception) { null }
            if (child != null) {
                val found = scanForIncognito(child, depth + 1)
                try { child.recycle() } catch (_: Exception) {}
                if (found) return true
            }
        }
        return false
    }

    // ══════════════════════════════════════════════════════════════
    // Keyword matching
    // ══════════════════════════════════════════════════════════════

    private fun matchesKeyword(text: String): Boolean {
        if (text.isBlank()) return false
        return KEYWORD_REGEX.matcher(text).find()
    }

    /** Recursively scan node tree for keywords (max depth 6). */
    private fun scanNodeForKeyword(node: AccessibilityNodeInfo?, depth: Int): Boolean {
        if (node == null || depth > 6) return false

        val text = node.text?.toString() ?: ""
        val desc = node.contentDescription?.toString() ?: ""

        if (text.isNotEmpty() && matchesKeyword(text)) return true
        if (desc.isNotEmpty() && matchesKeyword(desc)) return true

        for (i in 0 until node.childCount) {
            val child = try { node.getChild(i) } catch (_: Exception) { null }
            if (child != null) {
                val found = scanNodeForKeyword(child, depth + 1)
                try { child.recycle() } catch (_: Exception) {}
                if (found) return true
            }
        }
        return false
    }

    // ══════════════════════════════════════════════════════════════
    // Stats — isolated SharedPreferences
    // ══════════════════════════════════════════════════════════════

    private fun incrementBlockCount() {
        val count = prefs.getInt(KEY_BLOCK_COUNT, 0) + 1
        prefs.edit().putInt(KEY_BLOCK_COUNT, count).apply()
    }

    fun getBlockCount(): Int {
        if (!initialized) return 0
        return prefs.getInt(KEY_BLOCK_COUNT, 0)
    }

    /** Status map for Flutter method channel. */
    fun getStatus(): Map<String, Any> {
        return mapOf(
            "isActive" to initialized,
            "blockedKeywordCount" to BLOCKED_KEYWORDS.size,
            "totalBlocks" to getBlockCount()
        )
    }
}
