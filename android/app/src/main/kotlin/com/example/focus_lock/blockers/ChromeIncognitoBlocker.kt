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
                keywordFound = true
                break
            }
        }

        // 2. Check content description
        if (!keywordFound && eventDesc != null) {
            if (matchesKeyword(eventDesc.toString())) {
                keywordFound = true
            }
        }

        // 3. Check source node tree (depth-limited)
        if (!keywordFound && sourceNode != null) {
            keywordFound = scanNodeForKeyword(sourceNode, 0)
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
    // Incognito detection
    // ══════════════════════════════════════════════════════════════

    /**
     * Detect Chrome incognito by scanning for "incognito" in the
     * accessibility node tree (content descriptions, text).
     * Max depth 3 to keep performance acceptable.
     */
    private fun isIncognito(node: AccessibilityNodeInfo): Boolean {
        return scanForIncognito(node, 0)
    }

    private fun scanForIncognito(node: AccessibilityNodeInfo?, depth: Int): Boolean {
        if (node == null || depth > 3) return false

        val desc = node.contentDescription?.toString()?.lowercase(Locale.ROOT) ?: ""
        val text = node.text?.toString()?.lowercase(Locale.ROOT) ?: ""

        if ("incognito" in desc || "incognito" in text) return true

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

    /** Recursively scan node tree for keywords (max depth 4). */
    private fun scanNodeForKeyword(node: AccessibilityNodeInfo?, depth: Int): Boolean {
        if (node == null || depth > 4) return false

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
