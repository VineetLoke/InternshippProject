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
import android.view.animation.AlphaAnimation
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Full-screen discipline warning overlay.
 *
 * Shown for exactly 3 seconds when a blocked keyword is detected in Chrome.
 * Premium dark UI with a centered motivational quote.
 * The AccessibilityService handles the 3-second timer and dismissal.
 */
class DisciplineWarningOverlayService : Service() {
    companion object {
        const val TAG = "DisciplineWarning"
    }

    private var windowManager: WindowManager? = null
    private var overlayView: LinearLayout? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "DisciplineWarningOverlayService started")
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
                setBackgroundColor(Color.parseColor("#F0050505"))
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                isClickable = true
                isFocusable = true
                setPadding(64, 0, 64, 0)

                // Top spacer
                val topSpacer = android.view.View(this@DisciplineWarningOverlayService)
                topSpacer.layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
                )
                addView(topSpacer)

                // Main quote
                val quoteView = TextView(this@DisciplineWarningOverlayService).apply {
                    text = "\u201CKill the boy and let the man be born.\u201D"
                    textSize = 26f
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                    typeface = Typeface.create("serif", Typeface.BOLD)
                    setPadding(0, 0, 0, 40)
                    letterSpacing = 0.02f
                    setLineSpacing(8f, 1.1f)
                }
                addView(quoteView)

                // Subtle divider line
                val divider = android.view.View(this@DisciplineWarningOverlayService).apply {
                    setBackgroundColor(Color.parseColor("#22FFFFFF"))
                    layoutParams = LinearLayout.LayoutParams(160, 1).apply {
                        gravity = Gravity.CENTER
                        bottomMargin = 40
                    }
                }
                addView(divider)

                // Subtitle
                val subtitleView = TextView(this@DisciplineWarningOverlayService).apply {
                    text = "Focus is forged in resistance."
                    textSize = 14f
                    setTextColor(Color.parseColor("#88FFFFFF"))
                    gravity = Gravity.CENTER
                    typeface = Typeface.create("sans-serif-light", Typeface.ITALIC)
                    letterSpacing = 0.08f
                }
                addView(subtitleView)

                // Bottom spacer
                val bottomSpacer = android.view.View(this@DisciplineWarningOverlayService)
                bottomSpacer.layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
                )
                addView(bottomSpacer)

                // Fade-in animation
                val fadeIn = AlphaAnimation(0f, 1f).apply {
                    duration = 500
                    fillAfter = true
                }
                startAnimation(fadeIn)
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
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                width = WindowManager.LayoutParams.MATCH_PARENT
                height = WindowManager.LayoutParams.MATCH_PARENT
            }

            windowManager?.addView(overlayView, params)
            Log.d(TAG, "Discipline warning overlay displayed")
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
        Log.d(TAG, "DisciplineWarningOverlayService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
