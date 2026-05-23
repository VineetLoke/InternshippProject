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
import android.view.animation.AnimationSet
import android.view.animation.DecelerateInterpolator
import android.view.animation.ScaleAnimation
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

/**
 * Full-screen discipline warning overlay (PART 5 & 6).
 *
 * Shown for exactly 3 seconds when Chrome incognito mode is detected.
 * Premium dark UI with centered motivational quote,
 * progress bar countdown, and slow fade animations.
 *
 * The AccessibilityService handles the 3-second timer and dismissal.
 */
class DisciplineWarningOverlay : Service() {
    class CountdownRingView(context: Context) : View(context) {
        private val paintBg = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#22FF4444")
            style = android.graphics.Paint.Style.STROKE
            strokeWidth = 8f
        }
        private val paintArc = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FF4444")
            style = android.graphics.Paint.Style.STROKE
            strokeWidth = 8f
            strokeCap = android.graphics.Paint.Cap.ROUND
        }
        var progress = 100f // 100 to 0
            set(value) {
                field = value
                invalidate()
            }
        private val rectF = android.graphics.RectF()

        override fun onDraw(canvas: android.graphics.Canvas) {
            super.onDraw(canvas)
            val padding = 10f
            rectF.set(padding, padding, width - padding, height - padding)
            // draw background circle
            canvas.drawCircle(width / 2f, height / 2f, (width - padding * 2) / 2f, paintBg)
            // draw progress arc
            val angle = 360f * (progress / 100f)
            canvas.drawArc(rectF, -90f, angle, false, paintArc)
        }
    }

    companion object {
        const val TAG = "DisciplineWarning"
        private const val FADE_IN_DURATION_MS = 600L
        private const val FADE_OUT_DURATION_MS = 400L
        private const val COUNTDOWN_MS = 5000L
        private const val ACCENT_COLOR = "#C6A85A"
    }

    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "DisciplineWarningOverlay started")
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

            // Deep red radial gradient background
            val gradientBackground = GradientDrawable().apply {
                gradientType = GradientDrawable.RADIAL_GRADIENT
                colors = intArrayOf(
                    Color.parseColor("#0D0008"), // Center
                    Color.parseColor("#000000")  // Edges
                )
                gradientRadius = resources.displayMetrics.widthPixels.toFloat() * 1.5f
            }

            overlayView = FrameLayout(this).apply {
                background = gradientBackground
                isClickable = true
                isFocusable = true
            }

            val content = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(48), dp(60), dp(48), dp(48))
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            }

            // Top spacer
            content.addView(createSpacer(1f))

            // Warning icon with slow red pulse animation
            val warningIcon = TextView(this).apply {
                text = "⚠️"
                textSize = 56f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(16))
            }
            warningIcon.startAnimation(AlphaAnimation(0.5f, 1.0f).apply {
                duration = 750L
                repeatMode = AlphaAnimation.REVERSE
                repeatCount = AlphaAnimation.INFINITE
                interpolator = DecelerateInterpolator()
            })
            content.addView(warningIcon)

            // Title: heavy red all-caps STOP.
            val title = TextView(this).apply {
                text = "STOP."
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 36f)
                setTextColor(Color.parseColor("#FF4444"))
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif-black", Typeface.BOLD)
                setPadding(0, 0, 0, dp(24))
            }
            content.addView(title)

            // Main quote (Robert Greene - Quote B)
            val quoteView = TextView(this).apply {
                text = "“The pain is a kind of challenge your mind presents — will you learn how to focus and move past the boredom, or like a child will you succumb to the need for immediate pleasure and distraction?”"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
                setTextColor(Color.parseColor("#F0E6D0"))
                gravity = Gravity.CENTER
                typeface = Typeface.create("serif", Typeface.ITALIC)
                setPadding(0, 0, 0, dp(16))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    letterSpacing = 0.02f
                }
                setLineSpacing(10f, 1.3f)
            }
            content.addView(quoteView)

            // Attribution
            val attributionView = TextView(this).apply {
                text = "— Robert Greene, Mastery"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setTextColor(Color.parseColor("#8A7A6C"))
                gravity = Gravity.CENTER
                typeface = Typeface.create("serif", Typeface.ITALIC)
                setPadding(0, 0, 0, dp(24))
            }
            content.addView(attributionView)

            // Subtle divider
            val dividerDrawable = GradientDrawable().apply {
                orientation = GradientDrawable.Orientation.LEFT_RIGHT
                colors = intArrayOf(
                    Color.TRANSPARENT,
                    Color.parseColor("#FF4444"),
                    Color.TRANSPARENT
                )
            }
            val divider = View(this).apply {
                background = dividerDrawable
                alpha = 0.4f
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(1)).apply {
                    gravity = Gravity.CENTER
                    bottomMargin = dp(24)
                    leftMargin = dp(64)
                    rightMargin = dp(64)
                }
            }
            content.addView(divider)

            // Subtitle
            val subtitleView = TextView(this).apply {
                text = "Mastery is forged in resistance."
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setTextColor(Color.parseColor("#8A7A6C"))
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif-light", Typeface.ITALIC)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    letterSpacing = 0.08f
                }
                setPadding(0, 0, 0, dp(32))
            }
            content.addView(subtitleView)

            // Circular progress countdown ring
            val countdownRing = CountdownRingView(this).apply {
                layoutParams = LinearLayout.LayoutParams(dp(80), dp(80)).apply {
                    gravity = Gravity.CENTER
                    bottomMargin = dp(12)
                }
            }
            content.addView(countdownRing)

            // Countdown text below the ring
            val countdownText = TextView(this).apply {
                text = "Closing in 5s"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                setTextColor(Color.parseColor("#FF4444"))
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif", Typeface.BOLD)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    letterSpacing = 0.08f
                }
            }
            content.addView(countdownText)

            // Animate circular countdown ring and text updates over 5 seconds
            var elapsed = 0L
            val interval = 50L
            val progressRunnable = object : Runnable {
                override fun run() {
                    elapsed += interval
                    val pct = 100f * (1f - elapsed.toFloat() / COUNTDOWN_MS)
                    countdownRing.progress = if (pct < 0f) 0f else pct

                    val remainingSecs = Math.max(0, Math.ceil((COUNTDOWN_MS - elapsed).toDouble() / 1000.0).toInt())
                    countdownText.text = "Closing in ${remainingSecs}s"

                    if (elapsed < COUNTDOWN_MS) {
                        handler.postDelayed(this, interval)
                    }
                }
            }
            handler.postDelayed(progressRunnable, interval)

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

            // Smooth entrance: fade-in 600ms + scale 0.95 → 1.0 + shake animation (translateX 4dp)
            content.alpha = 0f
            content.scaleX = 0.95f
            content.scaleY = 0.95f
            content.animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(FADE_IN_DURATION_MS)
                .setInterpolator(DecelerateInterpolator())
                .start()

            val shakeAnimator = android.animation.ObjectAnimator.ofFloat(
                content, "translationX", 0f, dp(4).toFloat(), -dp(4).toFloat(), dp(4).toFloat(), -dp(4).toFloat(), dp(2).toFloat(), -dp(2).toFloat(), 0f
            ).apply {
                duration = 600
                interpolator = DecelerateInterpolator()
            }
            shakeAnimator.start()

            Log.d(TAG, "Discipline warning overlay displayed with premium UI")
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

    /** Remove overlay with a smooth 400ms fade-out. */
    private fun hideOverlay() {
        try {
            handler.removeCallbacksAndMessages(null)
            val view = overlayView
            val wm = windowManager
            if (view != null && wm != null) {
                val fadeOut = AlphaAnimation(1f, 0f).apply {
                    duration = FADE_OUT_DURATION_MS
                    interpolator = DecelerateInterpolator()
                    fillAfter = true
                }
                fadeOut.setAnimationListener(object : android.view.animation.Animation.AnimationListener {
                    override fun onAnimationStart(a: android.view.animation.Animation?) {}
                    override fun onAnimationRepeat(a: android.view.animation.Animation?) {}
                    override fun onAnimationEnd(a: android.view.animation.Animation?) {
                        try {
                            wm.removeViewImmediate(view)
                        } catch (_: Exception) {}
                        overlayView = null
                    }
                })
                view.startAnimation(fadeOut)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error hiding overlay: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        hideOverlay()
        Log.d(TAG, "DisciplineWarningOverlay destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
