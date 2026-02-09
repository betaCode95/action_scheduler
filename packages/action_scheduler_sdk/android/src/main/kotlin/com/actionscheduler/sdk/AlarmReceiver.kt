package com.actionscheduler.sdk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * BroadcastReceiver that is triggered by:
 * 1. AlarmManager when a scheduled alarm fires
 * 2. BOOT_COMPLETED when the device restarts (to reschedule alarms)
 *
 * When triggered, it starts the BackgroundExecutionService which runs
 * a headless FlutterEngine to execute due actions.
 */
class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "AlarmReceiver triggered: action=${intent.action}")

        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> {
                // Device rebooted - start background service to recover missed actions
                Log.d(TAG, "Device boot detected, starting background execution for recovery")
                startBackgroundService(context)
            }

            "com.actionscheduler.sdk.ALARM_FIRED" -> {
                // Scheduled alarm fired - start background service to execute due actions
                val requestCode = intent.getIntExtra("requestCode", -1)
                Log.d(TAG, "Alarm fired for requestCode=$requestCode")
                startBackgroundService(context)
            }

            else -> {
                Log.d(TAG, "Unknown action: ${intent.action}")
            }
        }
    }

    private fun startBackgroundService(context: Context) {
        try {
            val serviceIntent = Intent(context, BackgroundExecutionService::class.java)
            context.startService(serviceIntent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start BackgroundExecutionService: ${e.message}", e)
            // Service failed to start. The action will be picked up by
            // startup recovery the next time the user opens the app.
        }
    }

    companion object {
        private const val TAG = "ActionSchedulerAlarm"
    }
}
