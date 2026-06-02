package com.focuslock.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class AppBlockerAccessibilityService : AccessibilityService() {

    companion object {
        var instance: AppBlockerAccessibilityService? = null
        private const val PREFS_NAME = "focuslock_prefs"
        private const val INSTAGRAM_PACKAGE = "com.instagram.android"
        private const val TEMP_UNLOCK_DURATION = 600000L // 10 minutes in ms
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val packageName = event.packageName?.toString() ?: return

        if (packageName == INSTAGRAM_PACKAGE) {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val isBlocked = prefs.getBoolean("instagram_blocked", true)
            val tempUnlockTimestamp = prefs.getLong("temp_unlock_timestamp", 0L)
            val current = System.currentTimeMillis()
            val isUnlocked = (tempUnlockTimestamp + TEMP_UNLOCK_DURATION) > current

            if (isBlocked && !isUnlocked) {
                // Perform back action to kick user out
                performGlobalAction(GLOBAL_ACTION_BACK)
                
                // Show overlay on the main thread
                handler.post {
                    showBlockOverlay()
                }
            }
        } else {
            // If the user navigates away from Instagram, remove overlay
            if (packageName != "com.focuslock.app" && overlayView != null) {
                handler.post {
                    removeOverlay()
                }
            }
        }
    }

    private fun showBlockOverlay() {
        if (overlayView != null) return

        val layoutParams = WindowManager.LayoutParams().apply {
            type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
            } else {
                WindowManager.LayoutParams.TYPE_PHONE
            }
            format = PixelFormat.TRANSLUCENT
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = WindowManager.LayoutParams.MATCH_PARENT
            height = WindowManager.LayoutParams.MATCH_PARENT
            gravity = Gravity.CENTER
        }

        // Parent layout
        val mainLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#E00A0A1A")) // Dark theme matching background
            setPadding(50, 50, 50, 50)
        }

        // Lock Icon Text
        val lockIcon = TextView(this).apply {
            text = "🔒"
            textSize = 72f
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 40)
        }
        mainLayout.addView(lockIcon)

        // Title
        val titleText = TextView(this).apply {
            text = "Instagram is Blocked"
            setTextColor(Color.WHITE)
            textSize = 28f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 20)
        }
        mainLayout.addView(titleText)

        // Subtitle
        val subtitleText = TextView(this).apply {
            text = "Keep going! Turn your distractions into discipline."
            setTextColor(Color.parseColor("#8E8EA9")) // Sleek grey text
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 80)
        }
        mainLayout.addView(subtitleText)

        // Button
        val challengeButton = Button(this).apply {
            text = "Do 10 Pushups to Unlock"
            setTextColor(Color.WHITE)
            textSize = 18f
            typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
            isAllCaps = false
            
            // Design modern rounded button background
            val shape = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(28).toFloat()
                colors = intArrayOf(Color.parseColor("#6C63FF"), Color.parseColor("#5A52D5"))
                orientation = GradientDrawable.Orientation.LEFT_RIGHT
            }
            background = shape
            setPadding(dpToPx(32), dpToPx(16), dpToPx(32), dpToPx(16))
            
            setOnClickListener {
                removeOverlay()
                openPushupChallenge()
            }
        }

        val buttonParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.CENTER
        }
        mainLayout.addView(challengeButton, buttonParams)

        overlayView = mainLayout
        windowManager?.addView(overlayView, layoutParams)
    }

    private fun removeOverlay() {
        overlayView?.let {
            windowManager?.removeView(it)
            overlayView = null
        }
    }

    private fun openPushupChallenge() {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = "OPEN_PUSHUP_CHALLENGE"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        startActivity(intent)
    }

    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        super.onDestroy()
        removeOverlay()
        instance = null
    }
}
