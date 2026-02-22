package com.example.focus_lock

import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.util.Log

class MainActivity: FlutterActivity() {
    companion object {
        const val TAG = "MainActivity"
        const val CHANNEL = "com.example.focus_lock/app_block"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Start app blocking service
        startAppBlockingService()
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "MainActivity resumed")
        
        // Check and request accessibility service permission
        checkAccessibilityService()
        
        // Start foreground service
        startAppBlockingService()
    }

    private fun startAppBlockingService() {
        try {
            val serviceIntent = Intent(this, AppBlockingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            Log.d(TAG, "App blocking service started")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting service: ${e.message}")
        }
    }

    private fun checkAccessibilityService() {
        val accessibilityEnabled = try {
            Settings.Secure.getInt(
                contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0
            ) == 1
        } catch (e: Exception) {
            false
        }

        if (!accessibilityEnabled) {
            Log.w(TAG, "Accessibility service not enabled")
            // Show dialog asking user to enable accessibility service
            // This would be handled via Flutter platform channel
        }
    }
}
