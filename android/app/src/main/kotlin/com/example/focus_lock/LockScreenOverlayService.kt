package com.example.focus_lock

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class LockScreenOverlayService : Service() {
    companion object {
        const val TAG = "LockScreenOverlay"
    }

    private var windowManager: WindowManager? = null
    private var overlayView: LinearLayout? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val source = intent?.getStringExtra("source") ?: "instagram"
        Log.d(TAG, "LockScreenOverlayService onStartCommand (source=$source)")
        showOverlay(source)
        return START_STICKY
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
                Log.w(TAG, "⚠️ Overlay permission not granted — skipping overlay")
                stopSelf()
                return
            }

            windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

            val isReddit = source == "reddit"
            val bgColor = if (isReddit) "#DD1A1A2E" else "#DD000000"
            val emoji = if (isReddit) "🔒" else "🔒"
            val titleText = if (isReddit) "Reddit is locked." else "Instagram is Locked"
            val subtitleText = if (isReddit)
                "Complete 100 pushups to earn\n10 minutes of access."
            else
                "Stay focused! This app is blocked\nduring your focus period."

            overlayView = LinearLayout(this).apply {
                setBackgroundColor(Color.parseColor(bgColor))
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                isClickable = true
                isFocusable = true

                val icon = TextView(this@LockScreenOverlayService).apply {
                    text = emoji
                    textSize = 64f
                    gravity = Gravity.CENTER
                }
                addView(icon)

                val title = TextView(this@LockScreenOverlayService).apply {
                    text = titleText
                    textSize = 28f
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                    setPadding(0, 32, 0, 16)
                }
                addView(title)

                val subtitle = TextView(this@LockScreenOverlayService).apply {
                    text = subtitleText
                    textSize = 16f
                    setTextColor(Color.parseColor("#CCCCCC"))
                    gravity = Gravity.CENTER
                    setPadding(0, 0, 0, 48)
                }
                addView(subtitle)

                if (isReddit) {
                    // Button to open FocusLock's pushup challenge
                    val pushupBtn = Button(this@LockScreenOverlayService).apply {
                        text = "💪 Earn 10 minutes access"
                        textSize = 18f
                        setOnClickListener {
                            Log.d(TAG, "User tapped Earn Access — notifying accessibility service, opening app")
                            // Notify the accessibility service that challenge has started
                            AppBlockingAccessibilityService.instance?.onRedditChallengeStarted()
                            hideOverlay()
                            val launchIntent = packageManager.getLaunchIntentForPackage(
                                applicationContext.packageName
                            )?.apply {
                                putExtra("navigate_to", "pushup_challenge")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                        Intent.FLAG_ACTIVITY_CLEAR_TOP
                            }
                            if (launchIntent != null) startActivity(launchIntent)
                            stopSelf()
                        }
                    }
                    addView(pushupBtn)

                    // Add some spacing
                    val spacer = TextView(this@LockScreenOverlayService).apply {
                        textSize = 8f
                    }
                    addView(spacer)
                }

                val goHomeBtn = Button(this@LockScreenOverlayService).apply {
                    text = "Go Home"
                    textSize = 18f
                    setOnClickListener {
                        Log.d(TAG, "User tapped Go Home — removing overlay")
                        hideOverlay()
                        val home = Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_HOME)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(home)
                        stopSelf()
                    }
                }
                addView(goHomeBtn)
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
                x = 0
                y = 0
            }

            windowManager?.addView(overlayView, params)
            Log.d(TAG, "✅ Overlay displayed ($source)")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}", e)
        }
    }

    private fun hideOverlay() {
        try {
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
        Log.d(TAG, "LockScreenOverlayService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
