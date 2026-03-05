package com.example.focus_lock

import android.accessibilityservice.AccessibilityService
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
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
import android.widget.TextView

/**
 * Chrome content-blocked overlay (PART 5 & 6).
 *
 * Displayed after the 3-second discipline warning when a blocked keyword
 * is detected in Chrome incognito. Dark minimal design with psychological
 * resistance elements. Remains visible until the user exits Chrome
 * (detected by the AccessibilityService).
 */
class ChromeLockOverlayService : Service() {
    companion object {
        const val TAG = "ChromeLockOverlay"
        private const val BG_COLOR = "#F5050505"
        private const val FADE_DURATION_MS = 800L
        private const val BUTTON_DELAY_MS = 3000L
    }

    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null
    private val handler = Handler(Looper.getMainLooper())

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

            // Lock icon
            val lockIcon = TextView(this).apply {
                text = "\uD83D\uDD12"
                textSize = 56f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(32))
            }
            content.addView(lockIcon)

            // Title
            val title = TextView(this).apply {
                text = "Content Blocked"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
                letterSpacing = 0.04f
                setPadding(0, 0, 0, dp(20))
            }
            content.addView(title)

            // Subtitle
            val subtitle = TextView(this).apply {
                text = "Close this tab to continue."
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setTextColor(Color.parseColor("#99FFFFFF"))
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(56))
            }
            content.addView(subtitle)

            // Divider
            val divider = View(this).apply {
                setBackgroundColor(Color.parseColor("#15FFFFFF"))
                layoutParams = LinearLayout.LayoutParams(dp(120), dp(1)).apply {
                    gravity = Gravity.CENTER
                    bottomMargin = dp(56)
                }
            }
            content.addView(divider)

            // Quote
            val quote = TextView(this).apply {
                text = "\u201CDiscipline is choosing between\nwhat you want now and\nwhat you want most.\u201D"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setTextColor(Color.parseColor("#55FFFFFF"))
                gravity = Gravity.CENTER
                typeface = Typeface.create("serif", Typeface.ITALIC)
                letterSpacing = 0.03f
                setLineSpacing(4f, 1.15f)
                setPadding(0, 0, 0, dp(48))
            }
            content.addView(quote)

            // "Return to focus" button — appears after 3s delay (PART 7)
            val button = TextView(this).apply {
                text = "Return to focus"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setTextColor(Color.parseColor("#CCCCDD"))
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif", Typeface.NORMAL)
                letterSpacing = 0.04f
                setPadding(dp(24), dp(16), dp(24), dp(16))
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#1A1A2E"))
                    cornerRadius = dp(12).toFloat()
                    setStroke(1, Color.parseColor("#22FFFFFF"))
                }
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                )
                visibility = View.INVISIBLE
                alpha = 0f
                setOnClickListener {
                    Log.d(TAG, "User tapped Return to focus")
                    hideOverlay()
                    val svc = AppBlockingAccessibilityService.instance
                    svc?.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
                    stopSelf()
                }
            }
            content.addView(button)

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

            // Slow fade-in (PART 6)
            overlayView?.startAnimation(AlphaAnimation(0f, 1f).apply {
                duration = FADE_DURATION_MS
                interpolator = DecelerateInterpolator()
                fillAfter = true
            })

            // Reveal button after 3s delay (PART 7)
            handler.postDelayed({
                button.visibility = View.VISIBLE
                button.animate()
                    .alpha(1f)
                    .setDuration(600)
                    .setInterpolator(DecelerateInterpolator())
                    .start()
            }, BUTTON_DELAY_MS)

            Log.d(TAG, "Chrome lock overlay displayed")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}", e)
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

    /** Remove overlay using removeViewImmediate (PART 8). */
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
        Log.d(TAG, "ChromeLockOverlayService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
