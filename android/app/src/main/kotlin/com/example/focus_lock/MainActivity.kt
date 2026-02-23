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

class MainActivity : FlutterActivity() {
    companion object {
        const val TAG = "MainActivity"
        const val REQUEST_NOTIFICATION_PERMISSION = 1001
    }

    // Flag prevents starting the service more than once per process lifetime.
    private var serviceStarted = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
    }

    override fun onStart() {
        super.onStart()
        // Use onStart (not onResume) so this fires only when the Activity
        // transitions from stopped → started, not on every foreground event.
        if (!serviceStarted) {
            requestNotificationPermissionThenStart()
        }
    }

    private fun requestNotificationPermissionThenStart() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this, Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                startMonitoringService()
            } else {
                // Request; result handled below — service starts regardless
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQUEST_NOTIFICATION_PERMISSION
                )
            }
        } else {
            startMonitoringService()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            startMonitoringService() // start with or without notification permission
        }
    }

    /**
     * Starts the lightweight background watchdog service using a plain
     * startService() call — no foreground type, no notification required.
     */
    private fun startMonitoringService() {
        if (serviceStarted) return
        serviceStarted = true
        try {
            val intent = Intent(this, AppBlockingService::class.java)
            startService(intent)
            Log.d(TAG, "Monitoring service started")
        } catch (e: Exception) {
            Log.e(TAG, "Could not start monitoring service: ${e.message}")
        }
    }
}
