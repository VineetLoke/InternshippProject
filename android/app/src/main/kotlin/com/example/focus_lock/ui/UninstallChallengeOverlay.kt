package com.example.focus_lock.ui

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.AlphaAnimation
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import com.example.focus_lock.services.UninstallProtectionManager

/**
 * Full-screen overlay for the uninstall protection challenge.
 * User must complete 200 pushups (via proximity sensor or tap counter)
 * to disable protection. After completion, a 5-minute cooldown window opens.
 *
 * Design: Dark background (#0D0D0D), large centered text, progress bar.
 */
class UninstallChallengeOverlay : Service(), SensorEventListener {
    companion object {
        const val TAG = "UninstallChallenge"
        private const val REQUIRED_PUSHUPS = 200

        // Anti-cheat: pushup cycle must be 800ms-8000ms
        private const val MIN_CYCLE_MS = 800L
        private const val MAX_CYCLE_MS = 8000L
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private val handler = Handler(Looper.getMainLooper())

    // Pushup detection via proximity sensor
    private var sensorManager: SensorManager? = null
    private var proximitySensor: Sensor? = null
    private var isNear = false
    private var lastTransitionTime = 0L
    private var pushupCount = 0
    private var challengeCompleted = false

    // UI references
    private var countText: TextView? = null
    private var progressBar: ProgressBar? = null
    private var statusText: TextView? = null
    private var tapButton: TextView? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        UninstallProtectionManager.init(this)
        showOverlay()
        startProximitySensor()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        removeOverlay()
        stopProximitySensor()
    }

    // ══════════════════════════════════════════════════════════════════
    // Overlay UI
    // ══════════════════════════════════════════════════════════════════

    private fun showOverlay() {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.CENTER

        overlayView = buildUI()

        // Fade-in animation
        val fadeIn = AlphaAnimation(0f, 1f)
        fadeIn.duration = 700
        overlayView?.startAnimation(fadeIn)

        windowManager?.addView(overlayView, params)
        Log.d(TAG, "Challenge overlay SHOWN")
    }

    private fun buildUI(): View {
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#0D0D0D"))
        }

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(80, 0, 80, 0)
        }

        // Title
        val title = TextView(this).apply {
            text = "Protection Active"
            setTextColor(Color.parseColor("#C6A85A"))
            textSize = 28f
            typeface = Typeface.create("sans-serif-light", Typeface.BOLD)
            gravity = Gravity.CENTER
        }
        container.addView(title, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = 60 })

        // Discipline quote
        val quote = TextView(this).apply {
            text = "Discipline protects you from your weaker self."
            setTextColor(Color.parseColor("#888888"))
            textSize = 16f
            typeface = Typeface.create("sans-serif-light", Typeface.ITALIC)
            gravity = Gravity.CENTER
        }
        container.addView(quote, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = 80 })

        // Message
        val message = TextView(this).apply {
            text = "To remove FocusLock protection,\ncomplete 200 pushups."
            setTextColor(Color.parseColor("#CCCCCC"))
            textSize = 18f
            gravity = Gravity.CENTER
            lineSpacing = 8f
        }
        container.addView(message, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = 60 })

        // Pushup counter
        countText = TextView(this).apply {
            text = "Pushups: 0 / $REQUIRED_PUSHUPS"
            setTextColor(Color.WHITE)
            textSize = 36f
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
            gravity = Gravity.CENTER
        }
        container.addView(countText, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = 40 })

        // Progress bar
        progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = REQUIRED_PUSHUPS
            progress = 0
            progressDrawable.setColorFilter(
                Color.parseColor("#C6A85A"),
                android.graphics.PorterDuff.Mode.SRC_IN
            )
            minimumHeight = 16
        }
        container.addView(progressBar, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            bottomMargin = 40
            leftMargin = 40
            rightMargin = 40
        })

        // Status text
        statusText = TextView(this).apply {
            text = "Place phone face-up on floor.\nDo pushups over it."
            setTextColor(Color.parseColor("#666666"))
            textSize = 14f
            gravity = Gravity.CENTER
            lineSpacing = 4f
        }
        container.addView(statusText, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = 60 })

        // Manual tap counter button (fallback)
        tapButton = TextView(this).apply {
            text = "TAP TO COUNT"
            setTextColor(Color.parseColor("#0D0D0D"))
            setBackgroundColor(Color.parseColor("#C6A85A"))
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(60, 30, 60, 30)
            setOnClickListener { onManualTap() }
        }
        container.addView(tapButton, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            bottomMargin = 40
        })

        // Dismiss button (only visible after completion)
        val dismissText = TextView(this).apply {
            text = "CLOSE"
            setTextColor(Color.parseColor("#666666"))
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding(40, 20, 40, 20)
            setOnClickListener { stopSelf() }
        }
        container.addView(dismissText, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = Gravity.CENTER_HORIZONTAL })

        val containerParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        )
        root.addView(container, containerParams)
        return root
    }

    // ══════════════════════════════════════════════════════════════════
    // Pushup detection via proximity sensor
    // ══════════════════════════════════════════════════════════════════

    private fun startProximitySensor() {
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        proximitySensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        if (proximitySensor != null) {
            sensorManager?.registerListener(this, proximitySensor, SensorManager.SENSOR_DELAY_UI)
            Log.d(TAG, "Proximity sensor registered")
        } else {
            Log.w(TAG, "No proximity sensor — manual tap mode only")
            handler.post {
                statusText?.text = "No proximity sensor available.\nUse the tap button."
            }
        }
    }

    private fun stopProximitySensor() {
        sensorManager?.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_PROXIMITY) return
        if (challengeCompleted) return

        val distance = event.values[0]
        val maxRange = event.sensor.maximumRange
        val nowNear = distance < maxRange

        val now = System.currentTimeMillis()
        if (nowNear && !isNear) {
            // Chest approaching phone (down phase)
            isNear = true
            lastTransitionTime = now
        } else if (!nowNear && isNear) {
            // Pushed back up (up phase = 1 pushup)
            isNear = false
            val cycleTime = now - lastTransitionTime
            if (cycleTime in MIN_CYCLE_MS..MAX_CYCLE_MS) {
                pushupCount++
                updateUI()
                checkCompletion()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // ══════════════════════════════════════════════════════════════════
    // Manual tap counter
    // ══════════════════════════════════════════════════════════════════

    private var lastTapTime = 0L

    private fun onManualTap() {
        if (challengeCompleted) return
        val now = System.currentTimeMillis()
        // Debounce taps: minimum 800ms between taps (anti-spam)
        if (now - lastTapTime < MIN_CYCLE_MS) return
        lastTapTime = now
        pushupCount++
        updateUI()
        checkCompletion()
    }

    // ══════════════════════════════════════════════════════════════════
    // UI updates
    // ══════════════════════════════════════════════════════════════════

    private fun updateUI() {
        handler.post {
            countText?.text = "Pushups: $pushupCount / $REQUIRED_PUSHUPS"
            progressBar?.progress = pushupCount.coerceAtMost(REQUIRED_PUSHUPS)
        }
    }

    private fun checkCompletion() {
        if (pushupCount >= REQUIRED_PUSHUPS && !challengeCompleted) {
            challengeCompleted = true
            UninstallProtectionManager.onChallengeCompleted()
            Log.d(TAG, "Challenge COMPLETED — 5-minute cooldown started")

            handler.post {
                countText?.text = "CHALLENGE COMPLETE"
                countText?.setTextColor(Color.parseColor("#4CAF50"))
                progressBar?.progress = REQUIRED_PUSHUPS
                statusText?.text = "Protection disabled for 5 minutes.\nYou may now uninstall the app."
                statusText?.setTextColor(Color.parseColor("#C6A85A"))
                tapButton?.visibility = View.GONE
            }

            // Auto-dismiss after 10 seconds
            handler.postDelayed({ stopSelf() }, 10_000L)
        }
    }

    private fun removeOverlay() {
        try {
            if (overlayView != null) {
                windowManager?.removeView(overlayView)
                overlayView = null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing overlay: ${e.message}")
        }
    }
}
