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
        Log.d(TAG, "LockScreenOverlayService onStartCommand")
        showOverlay()
        return START_STICKY
    }

    private fun showOverlay() {
        // Don't add a second overlay if one is already showing
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

            overlayView = LinearLayout(this).apply {
                setBackgroundColor(Color.parseColor("#DD000000")) // dark scrim
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                // Consume all clicks so they don't pass through
                isClickable = true
                isFocusable = true

                val icon = TextView(this@LockScreenOverlayService).apply {
                    text = "🔒"
                    textSize = 64f
                    gravity = Gravity.CENTER
                }
                addView(icon)

                val title = TextView(this@LockScreenOverlayService).apply {
                    text = "Instagram is Locked"
                    textSize = 28f
                    setTextColor(Color.WHITE)
                    gravity = Gravity.CENTER
                    setPadding(0, 32, 0, 16)
                }
                addView(title)

                val subtitle = TextView(this@LockScreenOverlayService).apply {
                    text = "Stay focused! This app is blocked\nduring your focus period."
                    textSize = 16f
                    setTextColor(Color.parseColor("#CCCCCC"))
                    gravity = Gravity.CENTER
                    setPadding(0, 0, 0, 48)
                }
                addView(subtitle)

                val goHomeBtn = Button(this@LockScreenOverlayService).apply {
                    text = "Go Home"
                    textSize = 18f
                    setOnClickListener {
                        Log.d(TAG, "User tapped Go Home — removing overlay")
                        hideOverlay()
                        // Launch home screen
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
                // FLAG_NOT_FOCUSABLE removed so the overlay captures all touch/key events
                // FLAG_NOT_TOUCHABLE removed so touches do NOT pass through
                flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                width = WindowManager.LayoutParams.MATCH_PARENT
                height = WindowManager.LayoutParams.MATCH_PARENT
                x = 0
                y = 0
            }

            windowManager?.addView(overlayView, params)
            Log.d(TAG, "✅ Overlay displayed — Instagram is visually blocked")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}", e)
        }
    }

    private fun hideOverlay() {
        try {
            if (overlayView != null && windowManager != null) {
                windowManager?.removeView(overlayView)
                overlayView = null
                Log.d(TAG, "Overlay removed")
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
