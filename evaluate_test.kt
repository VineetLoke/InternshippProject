    @Volatile var isIncognitoCached = false

    fun evaluateIncognitoState(node: AccessibilityNodeInfo?) {
        if (node == null) return
        try {
            if (isIncognitoMode(node)) {
                isIncognitoCached = true
                return
            }
            
            val tabSwitchers = node.findAccessibilityNodeInfosByViewId("com.android.chrome:id/tab_switcher_button")
            if (tabSwitchers.isNotEmpty()) {
                var hasIncognitoDesc = false
                for (tab in tabSwitchers) {
                    val desc = tab.contentDescription?.toString()?.lowercase() ?: ""
                    if (desc.contains("incognito")) {
                        hasIncognitoDesc = true
                    }
                    tab.recycle()
                }
                if (!hasIncognitoDesc) {
                    isIncognitoCached = false
                }
            }
        } catch (e: Exception) {
            // Ignore
        }
    }
