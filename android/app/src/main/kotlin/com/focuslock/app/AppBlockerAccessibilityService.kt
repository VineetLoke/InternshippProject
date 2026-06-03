package com.focuslock.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

class AppBlockerAccessibilityService : AccessibilityService() {
    companion object {
        var isBlockingEnabled: Boolean = true
        var tempUnlockUntil: Long = 0L

        private val BLOCKED_PACKAGES = setOf(
            "com.instagram.android",
            "com.instagram.lite"
        )
    }

    private var overlayView: View? = null
    private var windowManager: WindowManager? = null

    override fun onServiceConnected() {
        super.onServiceConnected()
        android.util.Log.d("FocusLock", "Accessibility Service Connected!")
        val prefs = getSharedPreferences("focuslock_prefs", Context.MODE_PRIVATE)
        isBlockingEnabled = prefs.getBoolean("instagram_blocked", true)
        tempUnlockUntil = prefs.getLong("temp_unlock_timestamp", 0L)
    }


    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        
        // Listen to window state changes (e.g. app open)
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val packageName = event.packageName?.toString() ?: return
        android.util.Log.d("FocusLock", "Accessibility event package: $packageName")

        // Ignore our own app and system UI
        if (packageName == "com.focuslock.app" ||
            packageName == "com.android.systemui" ||
            packageName == "com.android.launcher" ||
            packageName.startsWith("com.android.launcher") ||
            packageName.contains("launcher") ||
            packageName.contains("trebuchet")) {
            return
        }

        if (!BLOCKED_PACKAGES.contains(packageName)) {
            return
        }

        // Load latest preferences directly to ensure we are in sync across processes
        val prefs = getSharedPreferences("focuslock_prefs", Context.MODE_PRIVATE)
        val isBlocked = prefs.getBoolean("instagram_blocked", true)
        val unlockUntil = prefs.getLong("temp_unlock_timestamp", 0L)
        val now = System.currentTimeMillis()

        android.util.Log.d("FocusLock", "Instagram detected! isBlocked: $isBlocked, unlockUntil: $unlockUntil, now: $now")

        if (!isBlocked) {
            android.util.Log.d("FocusLock", "Instagram block is disabled. Allowing.")
            return
        }

        if (now < unlockUntil) {
            val secondsLeft = (unlockUntil - now) / 1000
            android.util.Log.d("FocusLock", "Temporary unlock active! $secondsLeft seconds remaining. Allowing.")
            return
        }

        android.util.Log.d("FocusLock", "Instagram is blocked! Showing overlay and going BACK.")
        // Block! Show overlay and press BACK
        showLockOverlay()
        performGlobalAction(GLOBAL_ACTION_BACK)
    }

    override fun onInterrupt() {
        android.util.Log.d("FocusLock", "Accessibility service interrupted.")
        removeLockOverlay()
    }

    override fun onDestroy() {
        android.util.Log.d("FocusLock", "Accessibility service destroyed.")
        super.onDestroy()
        removeLockOverlay()
    }

    private fun showLockOverlay() {
        if (overlayView != null) return // Already showing

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.CENTER

        // Build the overlay UI programmatically
        val container = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#F0121212"))
            isClickable = true
            isFocusable = true
        }

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            val pad = dpToPx(32)
            setPadding(pad, pad, pad, pad)
        }

        // Lock icon
        val lockEmoji = TextView(this).apply {
            text = "🔒"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 64f)
            gravity = Gravity.CENTER
        }
        content.addView(lockEmoji)

        // Title
        val title = TextView(this).apply {
            text = "Instagram is Blocked"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            lp.topMargin = dpToPx(24)
            layoutParams = lp
        }
        content.addView(title)

        // Motivational message
        val message = TextView(this).apply {
            text = "Your future self will thank you.\nStay focused. Stay strong. 💪"
            setTextColor(Color.parseColor("#B0B0B0"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            gravity = Gravity.CENTER
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            lp.topMargin = dpToPx(16)
            layoutParams = lp
        }
        content.addView(message)

        // Pushup button
        val pushupButton = Button(this).apply {
            text = "💪 Do 10 Pushups to Unlock"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setBackgroundColor(Color.parseColor("#7C4DFF"))
            typeface = Typeface.DEFAULT_BOLD
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dpToPx(56)
            )
            lp.topMargin = dpToPx(40)
            lp.marginStart = dpToPx(16)
            lp.marginEnd = dpToPx(16)
            layoutParams = lp
            isAllCaps = false

            setOnClickListener {
                // Open FocusLock app at pushup challenge screen via deep link
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse("focuslock://pushup-challenge"))
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                startActivity(intent)
                removeLockOverlay()
            }
        }
        content.addView(pushupButton)

        // Dismiss button (go back to home)
        val dismissButton = Button(this).apply {
            text = "← Go Back"
            setTextColor(Color.parseColor("#888888"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setBackgroundColor(Color.TRANSPARENT)
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            lp.topMargin = dpToPx(16)
            layoutParams = lp
            isAllCaps = false

            setOnClickListener {
                removeLockOverlay()
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
        }
        content.addView(dismissButton)

        val contentParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        )
        container.addView(content, contentParams)

        overlayView = container
        try {
            android.util.Log.d("FocusLock", "Attempting to add overlay view to WindowManager")
            windowManager?.addView(container, params)
            android.util.Log.d("FocusLock", "Overlay view added successfully")
        } catch (e: Exception) {
            android.util.Log.e("FocusLock", "Error adding overlay view to WindowManager", e)
        }
    }

    private fun removeLockOverlay() {
        overlayView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                // View might not be attached
            }
            overlayView = null
        }
    }

    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            resources.displayMetrics
        ).toInt()
    }
}
