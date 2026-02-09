package com.actionscheduler.sdk

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation

/**
 * Service that runs a headless FlutterEngine to execute scheduled actions
 * when the app is not in the foreground.
 *
 * Lifecycle:
 * 1. AlarmReceiver starts this service
 * 2. Service acquires a WakeLock to prevent the CPU from sleeping
 * 3. Creates a headless FlutterEngine (no UI)
 * 4. Looks up the stored Dart callback dispatcher handle
 * 5. Executes the Dart callback which initializes the SDK and runs due actions
 * 6. Dart signals completion via "backgroundTaskComplete"
 * 7. Service releases the WakeLock and stops itself
 */
class BackgroundExecutionService : Service() {

    private var flutterEngine: FlutterEngine? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var backgroundChannel: MethodChannel? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "BackgroundExecutionService created")
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "BackgroundExecutionService started")

        // Get the stored callback dispatcher handle
        val dispatcherHandle = ActionSchedulerPlugin.getCallbackHandle(
            this, ActionSchedulerPlugin.PREF_DISPATCHER_HANDLE
        )
        val actionHandlerHandle = ActionSchedulerPlugin.getCallbackHandle(
            this, ActionSchedulerPlugin.PREF_ACTION_HANDLER_HANDLE
        )

        if (dispatcherHandle == 0L) {
            Log.e(TAG, "No callback dispatcher registered. Stopping.")
            cleanupAndStop()
            return START_NOT_STICKY
        }

        startHeadlessFlutterEngine(dispatcherHandle, actionHandlerHandle)
        return START_NOT_STICKY
    }

    private fun startHeadlessFlutterEngine(dispatcherHandle: Long, actionHandlerHandle: Long) {
        if (flutterEngine != null) {
            Log.d(TAG, "FlutterEngine already running")
            return
        }

        Log.d(TAG, "Starting headless FlutterEngine")

        val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle)
        if (callbackInfo == null) {
            Log.e(TAG, "Could not find callback for handle: $dispatcherHandle")
            cleanupAndStop()
            return
        }

        // Create the headless engine
        flutterEngine = FlutterEngine(this, null, false).also { engine ->
            // Set up the method channel on the background engine
            backgroundChannel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                ActionSchedulerPlugin.CHANNEL_NAME
            )

            backgroundChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "backgroundTaskComplete" -> {
                        Log.d(TAG, "Background task complete signal received from Dart")
                        result.success(true)
                        cleanupAndStop()
                    }
                    else -> result.notImplemented()
                }
            }

            // Execute the Dart callback dispatcher
            val dartCallback = DartExecutor.DartCallback(
                assets,
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                callbackInfo
            )
            engine.dartExecutor.executeDartCallback(dartCallback)

            // Send the action handler callback handle to Dart so it can
            // look up and call the developer's handler function
            backgroundChannel?.invokeMethod(
                "executeBackgroundTask",
                mapOf("callbackHandle" to actionHandlerHandle)
            )
        }
    }

    private fun acquireWakeLock() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "ActionSchedulerSDK:BackgroundExecution"
        ).apply {
            acquire(10 * 60 * 1000L) // 10 minute timeout
        }
        Log.d(TAG, "WakeLock acquired")
    }

    private fun cleanupAndStop() {
        Log.d(TAG, "Cleaning up and stopping service")

        backgroundChannel?.setMethodCallHandler(null)
        backgroundChannel = null

        flutterEngine?.destroy()
        flutterEngine = null

        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null

        sInstance = null
        stopSelf()
    }

    override fun onDestroy() {
        cleanupAndStop()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "ActionSchedulerBgSvc"
        private var sInstance: BackgroundExecutionService? = null

        /**
         * Called from the plugin when Dart signals task completion.
         */
        fun completeTask() {
            sInstance?.cleanupAndStop()
        }

        init {
            // Store instance for static access
        }
    }

    init {
        sInstance = this
    }
}
