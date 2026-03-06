package com.example.focus_lock

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.WindowManager
import android.view.animation.AlphaAnimation
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Full-screen blocking overlay for Instagram.
 *
 * UI spec:
 *  • Solid near-black background (#0A0A0A)
 *  • Centered text: "You don't need this."
 *  • Smooth 700ms fade-in
 *  • No buttons — ever. Overlay is purely informational.
 *  • Dismissed programmatically by [InstagramBlocker] after 5 seconds.
 */
class InstagramBlockOverlayService : Service() {
    companion object {
        const val TAG = "IGBlockOverlay"
        private const val BG_COLOR = "#0A0A0A"
        private const val TEXT_COLOR = "#E0E0E0"
        private const val FADE_DURATION_MS = 700L
    }

    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        showOverlay()
        return START_NOT_STICKY
    }

    private fun showOverlay() {
        if (overlayView != null) return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(this)
            ) {
                stopSelf()
                return
            }

            windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

            overlayView = FrameLayout(this).apply {
                setBackgroundColor(Color.parseColor(BG_COLOR))
                isClickable = true
                isFocusable = true
            }

            val content = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            }

            val message = TextView(this).apply {
                text = "You don\u2019t need this."
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
                setTextColor(Color.parseColor(TEXT_COLOR))
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
                letterSpacing = 0.04f
            }
            content.addView(message)

            overlayView?.addView(content)

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
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                width = WindowManager.LayoutParams.MATCH_PARENT
                height = WindowManager.LayoutParams.MATCH_PARENT
            }

            windowManager?.addView(overlayView, params)

            overlayView?.startAnimation(AlphaAnimation(0f, 1f).apply {
                duration = FADE_DURATION_MS
                interpolator = DecelerateInterpolator()
                fillAfter = true
            })

            Log.d(TAG, "Blocking overlay displayed")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}", e)
        }
    }

    private fun hideOverlay() {
        try {
            handler.removeCallbacksAndMessages(null)
            if (overlayView != null && windowManager != null) {
                windowManager?.removeViewImmediate(overlayView)
                overlayView = null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error hiding overlay: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        hideOverlay()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
