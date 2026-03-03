package com.example.focus_lock

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Persistent lock overlay for Chrome.
 *
 * Displayed after the 3-second discipline warning when a blocked keyword
 * is detected.  Remains visible until the user exits Chrome (detected by
 * the AccessibilityService).
 */
class ChromeLockOverlayService : Service() {
    companion object {
        const val TAG = "ChromeLockOverlay"
    }

    private var windowManager: WindowManager? = null
    private var overlayView: LinearLayout? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "ChromeLockOverlayService started")
        showOverlay()
        return START_NOT_STICKY
    }

    private fun showOverlay() {
        if (overlayView != null) return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(this)
            ) {
                Log.w(TAG, "Overlay permission not granted")
                stopSelf()
                return
            }

            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

            overlayView = LinearLayout(this).apply {
                setBackgroundColor(Color.parseColor("#F5050505"))
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                isClickable = true
                isFocusable = true
                setPadding(64, 0, 64, 0)

                // Lock icon
                val lockIcon = TextView(this@ChromeLockOverlayService).apply {
                    text = "\uD83D\uDD12"  // 🔒
                    textSize = 56f
                    gravity = Gravity.CENTER
                    setPadding(0, 0, 0, 32)
                }
                addView(lockIcon)

                // Title
                val title = TextView(this@ChromeLockOverlayService).apply {
                    text = "Content Blocked"
                    textSize = 24f
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                    typeface = Typeface.create("sans-serif-medium", Typeface.BOLD)
                    setPadding(0, 0, 0, 20)
                    letterSpacing = 0.03f
                }
                addView(title)

                // Subtitle
                val subtitle = TextView(this@ChromeLockOverlayService).apply {
                    text = "Exit Chrome to continue using your device."
                    textSize = 14f
                    setTextColor(Color.parseColor("#99FFFFFF"))
                    gravity = Gravity.CENTER
                    setPadding(0, 0, 0, 56)
                }
                addView(subtitle)

                // Divider
                val divider = android.view.View(this@ChromeLockOverlayService).apply {
                    setBackgroundColor(Color.parseColor("#15FFFFFF"))
                    layoutParams = LinearLayout.LayoutParams(120, 1).apply {
                        gravity = Gravity.CENTER
                        bottomMargin = 56
                    }
                }
                addView(divider)

                // Discipline quote
                val quote = TextView(this@ChromeLockOverlayService).apply {
                    text = "\u201CDiscipline is choosing between\nwhat you want now and\nwhat you want most.\u201D"
                    textSize = 13f
                    setTextColor(Color.parseColor("#55FFFFFF"))
                    gravity = Gravity.CENTER
                    typeface = Typeface.create("serif", Typeface.ITALIC)
                    letterSpacing = 0.03f
                    setLineSpacing(4f, 1.15f)
                }
                addView(quote)
            }

            val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
            }

            val params = WindowManager.LayoutParams().apply {
                type = layoutType
                format = PixelFormat.TRANSLUCENT
                flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                width = WindowManager.LayoutParams.MATCH_PARENT
                height = WindowManager.LayoutParams.MATCH_PARENT
            }

            windowManager?.addView(overlayView, params)
            Log.d(TAG, "Chrome lock overlay displayed")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}", e)
        }
    }

    private fun hideOverlay() {
        try {
            if (overlayView != null && windowManager != null) {
                windowManager?.removeView(overlayView)
                overlayView = null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error hiding overlay: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        hideOverlay()
        Log.d(TAG, "ChromeLockOverlayService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
