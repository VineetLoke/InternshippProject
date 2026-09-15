package com.example.focus_lock.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import com.example.focus_lock.R

/** Shared foreground-service notification and start helpers. */
object FocusForeground {
    private const val CHANNEL_ID = "focus_lock_enforcement"

    fun start(context: Context, intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
        else context.startService(intent)
    }

    fun promote(service: Service, id: Int, title: String, text: String) {
        ensureChannel(service)
        service.startForeground(id, notification(service, title, text, false))
    }

    fun postHealth(context: Context, title: String, text: String, needsAccessibilityAction: Boolean) {
        ensureChannel(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(1100, notification(context, title, text, needsAccessibilityAction))
    }

    private fun notification(context: Context, title: String, text: String, needsAccessibilityAction: Boolean): Notification {
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        if (needsAccessibilityAction) {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            val pending = PendingIntent.getActivity(
                context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(0, "Enable accessibility", pending)
        }
        return builder.build()
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "FocusLock enforcement", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }
}
