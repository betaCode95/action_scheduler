package com.actionscheduler.sdk

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Flutter plugin that bridges Dart calls to Android's AlarmManager.
 *
 * Handles three method channel operations:
 * - registerCallbackDispatcher: Stores the Dart callback handle for headless execution
 * - scheduleAlarm: Sets an exact alarm via AlarmManager
 * - cancelAlarm: Cancels a pending alarm
 */
class ActionSchedulerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // --- ActivityAware ---

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivity() {
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "canScheduleExactAlarms" -> {
                result.success(canScheduleExactAlarms(context))
            }

            "openExactAlarmSettings" -> {
                openExactAlarmSettings()
                result.success(true)
            }

            "registerCallbackDispatcher" -> {
                val callbackHandle = call.argument<Long>("callbackHandle")
                if (callbackHandle != null) {
                    saveCallbackHandle(context, PREF_DISPATCHER_HANDLE, callbackHandle)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "callbackHandle is required", null)
                }
            }

            "scheduleAlarm" -> {
                val requestCode = call.argument<Int>("requestCode")
                val triggerAtMillis = call.argument<Long>("triggerAtMillis")
                if (requestCode != null && triggerAtMillis != null) {
                    scheduleExactAlarm(context, requestCode, triggerAtMillis)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "requestCode and triggerAtMillis are required", null)
                }
            }

            "cancelAlarm" -> {
                val requestCode = call.argument<Int>("requestCode")
                if (requestCode != null) {
                    cancelAlarm(context, requestCode)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "requestCode is required", null)
                }
            }

            "backgroundTaskComplete" -> {
                // Signal received from Dart that background work is done
                BackgroundExecutionService.completeTask()
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Opens the system settings page for granting exact alarm permission.
     * Required on Android 12+ (API 31) for SCHEDULE_EXACT_ALARM.
     */
    private fun openExactAlarmSettings() {
        val activity = activityBinding?.activity ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:${activity.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            activity.startActivity(intent)
        }
    }

    companion object {
        const val CHANNEL_NAME = "com.actionscheduler.sdk/background"
        private const val PREFS_NAME = "action_scheduler_sdk_prefs"
        const val PREF_DISPATCHER_HANDLE = "dispatcher_callback_handle"
        const val PREF_ACTION_HANDLER_HANDLE = "action_handler_callback_handle"

        /**
         * Checks if exact alarms can be scheduled.
         * Returns true on Android < 12 (always allowed) or if permission is granted.
         */
        fun canScheduleExactAlarms(context: Context): Boolean {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                return alarmManager.canScheduleExactAlarms()
            }
            return true // Always allowed on older Android versions
        }

        /**
         * Schedules an exact alarm using AlarmManager.
         *
         * Uses setExactAndAllowWhileIdle() which fires even in Doze mode.
         */
        fun scheduleExactAlarm(context: Context, requestCode: Int, triggerAtMillis: Long) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, AlarmReceiver::class.java).apply {
                action = "com.actionscheduler.sdk.ALARM_FIRED"
                putExtra("requestCode", requestCode)
            }

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context, requestCode, intent, flags
            )

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            }
        }

        /**
         * Cancels a pending alarm.
         */
        fun cancelAlarm(context: Context, requestCode: Int) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, AlarmReceiver::class.java).apply {
                action = "com.actionscheduler.sdk.ALARM_FIRED"
            }

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context, requestCode, intent, flags
            )
            alarmManager.cancel(pendingIntent)
        }

        /**
         * Saves a callback handle to SharedPreferences.
         */
        fun saveCallbackHandle(context: Context, key: String, handle: Long) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putLong(key, handle)
                .apply()
        }

        /**
         * Loads a callback handle from SharedPreferences.
         */
        fun getCallbackHandle(context: Context, key: String): Long {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getLong(key, 0)
        }
    }
}
