package com.example.focus_lock.blockers

import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Universal Browser Private/Incognito Blocker.
 *
 * Activates for Chrome, Firefox, Opera, and Samsung Internet.
 * Checks visible nodes for specific private mode keywords and badge layouts.
 */
object BrowserIncognitoBlocker {
    private const val TAG = "BrowserIncognitoBlocker"
    
    const val CHROME_PACKAGE = "com.android.chrome"
    const val FIREFOX_PACKAGE = "org.mozilla.firefox"
    const val OPERA_PACKAGE = "com.opera.browser"
    const val SAMSUNG_BROWSER_PACKAGE = "com.sec.android.app.sbrowser"
    
    val BROWSER_PACKAGES = setOf(CHROME_PACKAGE, FIREFOX_PACKAGE, OPERA_PACKAGE, SAMSUNG_BROWSER_PACKAGE)

    private const val BLOCK_DEBOUNCE_MS = 5000L
    @Volatile private var lastBlockTime = 0L

    @Volatile var isIncognitoCached = false
        private set

    private const val MAX_TREE_DEPTH = 20

    /**
     * Fast-path heuristic to track private browsing state.
     */
    fun evaluateIncognitoState(node: AccessibilityNodeInfo?, packageName: String) {
        if (node == null) return
        try {
            var hasPrivateIndicator = false
            
            when (packageName) {
                CHROME_PACKAGE -> {
                    val incognitoNodes = node.findAccessibilityNodeInfosByText("incognito")
                    if (incognitoNodes.isNotEmpty()) {
                        for (n in incognitoNodes) {
                            val viewId = n.viewIdResourceName ?: ""
                            val desc = n.contentDescription?.toString()?.lowercase() ?: ""
                            val text = n.text?.toString()?.lowercase() ?: ""

                            val isBadgeId = viewId.contains("incognito_badge") && n.isVisibleToUser
                            val isActiveDesc = desc == "incognito mode active" && n.isVisibleToUser
                            val isIncognitoStartPage = text.contains("gone incognito") && n.isVisibleToUser

                            if (isBadgeId || isActiveDesc || isIncognitoStartPage) {
                                hasPrivateIndicator = true
                                break
                            }
                        }
                        incognitoNodes.forEach { it.recycle() }
                    }
                }
                FIREFOX_PACKAGE -> {
                    val privateNodes = node.findAccessibilityNodeInfosByText("private")
                    if (privateNodes.isNotEmpty()) {
                        for (n in privateNodes) {
                            val desc = n.contentDescription?.toString()?.lowercase() ?: ""
                            val text = n.text?.toString()?.lowercase() ?: ""
                            val isPrivateIndicator = (desc.contains("private") || text.contains("private browsing") || text.contains("private tab")) && n.isVisibleToUser
                            if (isPrivateIndicator) {
                                hasPrivateIndicator = true
                                break
                            }
                        }
                        privateNodes.forEach { it.recycle() }
                    }
                }
                SAMSUNG_BROWSER_PACKAGE -> {
                    val secretNodes = node.findAccessibilityNodeInfosByText("secret")
                    if (secretNodes.isNotEmpty()) {
                        for (n in secretNodes) {
                            val desc = n.contentDescription?.toString()?.lowercase() ?: ""
                            val text = n.text?.toString()?.lowercase() ?: ""
                            val isSecretIndicator = (desc.contains("secret mode") || text.contains("secret mode") || text.contains("secret tab")) && n.isVisibleToUser
                            if (isSecretIndicator) {
                                hasPrivateIndicator = true
                                break
                            }
                        }
                        secretNodes.forEach { it.recycle() }
                    }
                }
                OPERA_PACKAGE -> {
                    val privateNodes = node.findAccessibilityNodeInfosByText("private")
                    if (privateNodes.isNotEmpty()) {
                        for (n in privateNodes) {
                            val desc = n.contentDescription?.toString()?.lowercase() ?: ""
                            val text = n.text?.toString()?.lowercase() ?: ""
                            val isPrivateIndicator = (desc.contains("private") || text.contains("private")) && n.isVisibleToUser
                            if (isPrivateIndicator) {
                                hasPrivateIndicator = true
                                break
                            }
                        }
                        privateNodes.forEach { it.recycle() }
                    }
                }
            }

            if (hasPrivateIndicator) {
                isIncognitoCached = true
                return
            }
            
            // Tab switcher check to reset cache for Chrome
            if (packageName == CHROME_PACKAGE) {
                val tabSwitchers = node.findAccessibilityNodeInfosByViewId("com.android.chrome:id/tab_switcher_button")
                if (tabSwitchers.isNotEmpty()) {
                    isIncognitoCached = false
                    tabSwitchers.forEach { it.recycle() }
                    return
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error evaluating private state: ${e.message}")
        }
    }

    /**
     * Detect private/incognito mode by scanning the accessibility tree.
     */
    fun isIncognitoMode(rootNode: AccessibilityNodeInfo, packageName: String): Boolean {
        return try {
            var detected = false
            when (packageName) {
                CHROME_PACKAGE -> {
                    val incognitoNodes = rootNode.findAccessibilityNodeInfosByText("incognito")
                    if (incognitoNodes.isNotEmpty()) {
                        for (node in incognitoNodes) {
                            val viewId = node.viewIdResourceName ?: ""
                            val desc = node.contentDescription?.toString()?.lowercase() ?: ""
                            val text = node.text?.toString()?.lowercase() ?: ""

                            val isBadgeId = viewId.contains("incognito_badge") && node.isVisibleToUser
                            val isActiveDesc = desc == "incognito mode active" && node.isVisibleToUser
                            val isIncognitoStartPage = text.contains("gone incognito") && node.isVisibleToUser

                            if (isBadgeId || isActiveDesc || isIncognitoStartPage) {
                                detected = true
                                break
                            }
                        }
                        incognitoNodes.forEach { it.recycle() }
                    }
                }
                FIREFOX_PACKAGE -> {
                    val privateNodes = rootNode.findAccessibilityNodeInfosByText("private")
                    if (privateNodes.isNotEmpty()) {
                        for (node in privateNodes) {
                            val desc = node.contentDescription?.toString()?.lowercase() ?: ""
                            val text = node.text?.toString()?.lowercase() ?: ""
                            val isPrivateIndicator = (desc.contains("private") || text.contains("private browsing") || text.contains("private tab")) && node.isVisibleToUser
                            if (isPrivateIndicator) {
                                detected = true
                                break
                            }
                        }
                        privateNodes.forEach { it.recycle() }
                    }
                }
                SAMSUNG_BROWSER_PACKAGE -> {
                    val secretNodes = rootNode.findAccessibilityNodeInfosByText("secret")
                    if (secretNodes.isNotEmpty()) {
                        for (node in secretNodes) {
                            val desc = node.contentDescription?.toString()?.lowercase() ?: ""
                            val text = node.text?.toString()?.lowercase() ?: ""
                            val isSecretIndicator = (desc.contains("secret mode") || text.contains("secret mode") || text.contains("secret tab")) && node.isVisibleToUser
                            if (isSecretIndicator) {
                                detected = true
                                break
                            }
                        }
                        secretNodes.forEach { it.recycle() }
                    }
                }
                OPERA_PACKAGE -> {
                    val privateNodes = rootNode.findAccessibilityNodeInfosByText("private")
                    if (privateNodes.isNotEmpty()) {
                        for (node in privateNodes) {
                            val desc = node.contentDescription?.toString()?.lowercase() ?: ""
                            val text = node.text?.toString()?.lowercase() ?: ""
                            val isPrivateIndicator = (desc.contains("private") || text.contains("private")) && node.isVisibleToUser
                            if (isPrivateIndicator) {
                                detected = true
                                break
                            }
                        }
                        privateNodes.forEach { it.recycle() }
                    }
                }
            }
            if (detected) return true
            
            // Deep scan walk fallback
            scanTreeForPrivate(rootNode, packageName, 0)
        } catch (e: Exception) {
            Log.e(TAG, "Error detecting private mode: ${e.message}")
            false
        }
    }

    private fun scanTreeForPrivate(node: AccessibilityNodeInfo, packageName: String, depth: Int): Boolean {
        if (depth > MAX_TREE_DEPTH) return false

        if (node.isVisibleToUser) {
            val viewId = node.viewIdResourceName ?: ""
            val desc = node.contentDescription?.toString()?.lowercase() ?: ""
            val text = node.text?.toString()?.lowercase() ?: ""

            when (packageName) {
                CHROME_PACKAGE -> {
                    if (viewId.contains("incognito_badge") || 
                        desc == "incognito mode active" || 
                        text.contains("gone incognito")) return true
                }
                FIREFOX_PACKAGE -> {
                    if (desc.contains("private browsing") || 
                        desc.contains("private tab") || 
                        text.contains("private browsing") || 
                        text.contains("private tab")) return true
                }
                SAMSUNG_BROWSER_PACKAGE -> {
                    if (desc.contains("secret mode") || text.contains("secret mode")) return true
                }
                OPERA_PACKAGE -> {
                    if (desc.contains("private tab") || text.contains("private mode") || desc.contains("private mode")) return true
                }
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (scanTreeForPrivate(child, packageName, depth + 1)) {
                child.recycle()
                return true
            }
            child.recycle()
        }
        return false
    }

    fun shouldBlockTyping(rootNode: AccessibilityNodeInfo, packageName: String): Boolean {
        val now = System.currentTimeMillis()
        if (now - lastBlockTime < BLOCK_DEBOUNCE_MS) return false

        val isCurrentlyPrivate = isIncognitoMode(rootNode, packageName)
        
        if (isCurrentlyPrivate) {
            isIncognitoCached = true
        }

        if (!isCurrentlyPrivate) {
            val isSparse = rootNode.childCount <= 2
            if (!isSparse || !isIncognitoCached) {
                return false
            }
        }

        lastBlockTime = now
        Log.d(TAG, "BLOCKED — typing detected in private tab of $packageName")
        return true
    }

    fun resetDebounce() {
        lastBlockTime = 0L
        isIncognitoCached = false
    }

    fun resetCache() {
        isIncognitoCached = false
        Log.d(TAG, "Browser private cache reset")
    }
}
