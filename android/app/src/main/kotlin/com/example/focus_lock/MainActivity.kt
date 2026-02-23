package com.example.focus_lock

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.util.Log

class MainActivity: FlutterActivity() {
    companion object {
        const val TAG = "MainActivity"
        const val CHANNEL = "com.example.focus_lock/app_block"
        const val REQUEST_NOTIFICATION_PERMISSION = 1001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Do NOT start service here — Activity is not fully ready yet
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "MainActivity resumed")
        checkAccessibilityService()
        requestNotificationPermissionAndStartService()
    }

    private fun requestNotificationPermissionAndStartService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+ requires runtime POST_NOTIFICATIONS permission
            if (ContextCompat.checkSelfPermission(
                    this, Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                startAppBlockingService()
            } else {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQUEST_NOTIFICATION_PERMISSION
                )
            }
        } else {
            startAppBlockingService()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            // Start service whether permission granted or denied
            // (service will run without visible notification if denied)
            startAppBlockingService()
        }
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
        }
    }
}
