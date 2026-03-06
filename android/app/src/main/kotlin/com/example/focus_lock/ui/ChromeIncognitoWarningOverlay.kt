package com.example.focus_lock.ui

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.ClipDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.AlphaAnimation
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

/**
 * Full-screen incognito keyword warning overlay — isolated from all other overlays.
 *
 * Shown for exactly 3 seconds when ChromeIncognitoBlocker detects a blocked keyword.
 * Dark minimal design with centered motivational quote and attribution.
 *
 * The AccessibilityService handles the 3-second timer and tab dismissal.
 */
class ChromeIncognitoWarningOverlay : Service() {
    companion object {
        const val TAG = "IncognitoWarning"
        private const val BG_COLOR = "#0D0D0D"
        private const val FADE_DURATION_MS = 700L
        private const val COUNTDOWN_MS = 3000L
        private const val ACCENT_COLOR = "#C6A85A"
    }

    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "ChromeIncognitoWarningOverlay started")
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

            overlayView = FrameLayout(this).apply {
                setBackgroundColor(Color.parseColor(BG_COLOR))
                isClickable = true
                isFocusable = true
            }

            val content = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(64), 0, dp(64), 0)
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            }

            // Top spacer
            content.addView(createSpacer(1f))

            // Main quote
            val quoteView = TextView(this).apply {
                text = "\u201CKill the boy and let the man be born.\u201D"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                typeface = Typeface.create("serif", Typeface.BOLD)
                setPadding(0, 0, 0, dp(24))
                letterSpacing = 0.02f
                setLineSpacing(8f, 1.1f)
            }
            content.addView(quoteView)

            // Attribution
            val attributionView = TextView(this).apply {
                text = "\u2014 Maester Aemon Targaryen"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setTextColor(Color.parseColor("#AAFFFFFF"))
                gravity = Gravity.CENTER
                typeface = Typeface.create("serif", Typeface.ITALIC)
                letterSpacing = 0.04f
                setPadding(0, 0, 0, dp(48))
            }
            content.addView(attributionView)

            // Subtle divider — muted gold accent
            val divider = View(this).apply {
                setBackgroundColor(Color.parseColor(ACCENT_COLOR))
                alpha = 0.3f
                layoutParams = LinearLayout.LayoutParams(dp(160), dp(1)).apply {
                    gravity = Gravity.CENTER
                    bottomMargin = dp(56)
                }
            }
            content.addView(divider)

            // Progress bar countdown
            val progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
                isIndeterminate = false
                max = 100
                progress = 0
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, dp(2)
                ).apply {
                    leftMargin = dp(48)
                    rightMargin = dp(48)
                }
                val bgDrawable = GradientDrawable().apply {
                    setColor(Color.parseColor("#12121A"))
                    cornerRadius = 4f
                }
                val progressShape = GradientDrawable().apply {
                    setColor(Color.parseColor(ACCENT_COLOR))
                    cornerRadius = 4f
                }
                val clip = ClipDrawable(progressShape, Gravity.START, ClipDrawable.HORIZONTAL)
                progressDrawable = LayerDrawable(arrayOf(bgDrawable, clip)).apply {
                    setId(0, android.R.id.background)
                    setId(1, android.R.id.progress)
                }
            }
            content.addView(progressBar)

            // Animate progress bar over 3 seconds
            animateProgress(progressBar)

            // Bottom spacer
            content.addView(createSpacer(1f))

            overlayView?.addView(content)

            // Window params
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

            // Slow fade-in
            overlayView?.startAnimation(AlphaAnimation(0f, 1f).apply {
                duration = FADE_DURATION_MS
                interpolator = DecelerateInterpolator()
                fillAfter = true
            })

            Log.d(TAG, "Incognito warning overlay displayed")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}", e)
        }
    }

    private fun animateProgress(progressBar: ProgressBar) {
        val totalSteps = 100
        val intervalMs = COUNTDOWN_MS / totalSteps
        for (i in 1..totalSteps) {
            handler.postDelayed({ progressBar.progress = i }, intervalMs * i)
        }
    }

    private fun createSpacer(weight: Float): View {
        return View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, weight
            )
        }
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics
        ).toInt()
    }

    /** Remove overlay using removeViewImmediate for safety. */
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
        Log.d(TAG, "ChromeIncognitoWarningOverlay destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
