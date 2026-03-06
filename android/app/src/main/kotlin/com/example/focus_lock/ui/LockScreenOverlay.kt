package com.example.focus_lock.ui

import android.accessibilityservice.AccessibilityService
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
import com.example.focus_lock.services.AccessibilityMonitor

/**
 * Psychologically designed blocking overlay (PART 6 & 7).
 *
 * Design intent: create a pause-and-reflection moment, not punishment.
 * - Dark minimal design, calm but authoritative tone
 * - Centered typography with breathing space
 * - Slow fade transitions (800ms)
 * - 3-second delay before interaction buttons appear
 * - Progress bar during initial display
 * - Subtle animations to calm the user
 */
class LockScreenOverlay : Service() {
    companion object {
        const val TAG = "LockScreenOverlay"
        private const val BG_COLOR = "#0D0D0D"              // solid near-black (PART 6 spec)
        private const val TEXT_PRIMARY = "#EAEAEA"          // soft white (PART 6 spec)
        private const val TEXT_SECONDARY = "#7A7A8C"        // muted grey
        private const val TEXT_QUOTE = "#C0C0CC"            // slightly brighter for quote
        private const val ACCENT_COLOR = "#C6A85A"          // muted gold accent (PART 6 spec)
        private const val BUTTON_BG = "#1A1A2E"            // dark button background
        private const val BUTTON_TEXT = "#CCCCDD"           // soft button text
        private const val PROGRESS_COLOR = "#C6A85A"        // muted gold progress bar
        private const val PROGRESS_BG = "#12121A"           // progress background
        private const val FADE_DURATION_MS = 700L           // slow fade-in (PART 6 spec: 700ms)
        private const val BUTTON_DELAY_MS = 3000L           // 3s delay before buttons (PART 7)
    }

    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val source = intent?.getStringExtra("source") ?: "instagram"
        Log.d(TAG, "LockScreenOverlay started (source=$source)")
        showOverlay(source)
        return START_NOT_STICKY
    }

    private fun showOverlay(source: String) {
        if (overlayView != null) {
            Log.d(TAG, "Overlay already visible — skipping")
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !android.provider.Settings.canDrawOverlays(this)
            ) {
                Log.w(TAG, "Overlay permission not granted — skipping")
                stopSelf()
                return
            }

            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val isReddit = source == "reddit"

            // ── Root container ───────────────────────────────────────
            overlayView = FrameLayout(this).apply {
                setBackgroundColor(Color.parseColor(BG_COLOR))
                isClickable = true
                isFocusable = true
            }

            // ── Content layout ───────────────────────────────────────
            val content = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(48), dp(80), dp(48), dp(48))
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            }

            // Top breathing space
            content.addView(createSpacer(1f))

            // Lock icon — subtle, not aggressive
            val lockIcon = TextView(this).apply {
                text = "\uD83D\uDD12"
                textSize = 48f
                gravity = Gravity.CENTER
                setPadding(0, 0, 0, dp(24))
            }
            content.addView(lockIcon)

            // Title — calm, authoritative
            val titleText = when {
                isReddit -> "Reddit Locked"
                source == "twitter" -> "Twitter/X Locked"
                else -> "Instagram Locked"
            }
            val title = TextView(this).apply {
                text = titleText
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
                setTextColor(Color.parseColor(TEXT_PRIMARY))
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
                letterSpacing = 0.06f
                setPadding(0, 0, 0, dp(40))
            }
            content.addView(title)

            // Divider — thin, muted gold accent
            val divider = View(this).apply {
                setBackgroundColor(Color.parseColor(ACCENT_COLOR))
                alpha = 0.3f
                layoutParams = LinearLayout.LayoutParams(dp(120), dp(1)).apply {
                    gravity = Gravity.CENTER
                    bottomMargin = dp(40)
                }
            }
            content.addView(divider)

            // Main quote (PART 6)
            val quote = TextView(this).apply {
                text = "\u201CKill the boy and let the man be born.\u201D"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
                setTextColor(Color.parseColor(TEXT_QUOTE))
                gravity = Gravity.CENTER
                typeface = Typeface.create("serif", Typeface.ITALIC)
                letterSpacing = 0.02f
                setLineSpacing(6f, 1.2f)
                setPadding(0, 0, 0, dp(20))
            }
            content.addView(quote)

            // Subtitle (PART 6)
            val subtitle = TextView(this).apply {
                text = "Discipline is forged in resistance."
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setTextColor(Color.parseColor(TEXT_SECONDARY))
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
                letterSpacing = 0.08f
                setPadding(0, 0, 0, dp(48))
            }
            content.addView(subtitle)

            // Progress bar — subtle visual timer (PART 7)
            val progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
                isIndeterminate = false
                max = 100
                progress = 0
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, dp(3)
                ).apply {
                    bottomMargin = dp(48)
                    leftMargin = dp(32)
                    rightMargin = dp(32)
                }
                val bgDrawable = GradientDrawable().apply {
                    setColor(Color.parseColor(PROGRESS_BG))
                    cornerRadius = 4f
                }
                val progressShape = GradientDrawable().apply {
                    setColor(Color.parseColor(PROGRESS_COLOR))
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

            // ── Buttons container (hidden for 3 seconds — PART 7) ────
            val buttonContainer = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                visibility = View.INVISIBLE
                alpha = 0f
            }

            if (isReddit) {
                // "Earn access" button for Reddit (PART 4 & 7)
                val earnBtn = createButton("Earn 10 minutes access") {
                    Log.d(TAG, "User tapped Earn Access — starting pushup challenge")
                    AccessibilityMonitor.instance?.onRedditChallengeStarted()
                    hideOverlay()
                    val launchIntent = packageManager.getLaunchIntentForPackage(
                        applicationContext.packageName
                    )?.apply {
                        putExtra("navigate_to", "pushup_challenge")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    }
                    if (launchIntent != null) startActivity(launchIntent)
                    stopSelf()
                }
                buttonContainer.addView(earnBtn)

                // Spacer between buttons
                buttonContainer.addView(View(this).apply {
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT, dp(12)
                    )
                })
            }

            // "Return to focus" button (PART 7)
            val focusBtn = createButton("Return to focus") {
                Log.d(TAG, "User tapped Return to focus")
                hideOverlay()
                // Navigate back (not to home screen)
                val svc = AccessibilityMonitor.instance
                svc?.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
                stopSelf()
            }
            buttonContainer.addView(focusBtn)

            content.addView(buttonContainer)

            // Bottom breathing space
            content.addView(createSpacer(1f))

            overlayView?.addView(content)

            // ── Window params ────────────────────────────────────────
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

            // ── Slow fade-in animation (PART 6) ─────────────────────
            overlayView?.startAnimation(AlphaAnimation(0f, 1f).apply {
                duration = FADE_DURATION_MS
                interpolator = DecelerateInterpolator()
                fillAfter = true
            })

            // ── Reveal buttons after 3-second delay (PART 7) ────────
            handler.postDelayed({
                buttonContainer.visibility = View.VISIBLE
                buttonContainer.animate()
                    .alpha(1f)
                    .setDuration(600)
                    .setInterpolator(DecelerateInterpolator())
                    .start()
            }, BUTTON_DELAY_MS)

            Log.d(TAG, "Overlay displayed ($source) with psychological UI")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}", e)
        }
    }

    /** Animate the progress bar from 0 to 100 over 3 seconds. */
    private fun animateProgress(progressBar: ProgressBar) {
        val totalSteps = 100
        val intervalMs = BUTTON_DELAY_MS / totalSteps
        for (i in 1..totalSteps) {
            handler.postDelayed({ progressBar.progress = i }, intervalMs * i)
        }
    }

    /** Create a styled button with dark minimal design. */
    private fun createButton(text: String, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            this.text = text
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(Color.parseColor(BUTTON_TEXT))
            gravity = Gravity.CENTER
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
            letterSpacing = 0.04f
            setPadding(dp(24), dp(16), dp(24), dp(16))
            background = GradientDrawable().apply {
                setColor(Color.parseColor(BUTTON_BG))
                cornerRadius = dp(12).toFloat()
                setStroke(1, Color.parseColor("#22FFFFFF"))
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            setOnClickListener { onClick() }
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
                Log.d(TAG, "Overlay removed (immediate)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error hiding overlay: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        hideOverlay()
        Log.d(TAG, "LockScreenOverlay destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
