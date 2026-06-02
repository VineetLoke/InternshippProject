package com.focuslock.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Intent.ACTION_BOOT_COMPLETED == intent.action) {
            Log.d("FocusLockBoot", "Boot completed broadcast received")
            // Future placeholder to restart foreground monitoring service if needed
        }
    }
}
