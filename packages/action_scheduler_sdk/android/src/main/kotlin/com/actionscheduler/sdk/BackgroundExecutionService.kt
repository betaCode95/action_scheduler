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
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation

/**
 * Service that runs a headless FlutterEngine to execute scheduled actions
 * when the app is not in the foreground.
 *
 * Lifecycle:
 * 1. AlarmReceiver starts this service
 * 2. Service acquires a WakeLock to prevent the CPU from sleeping
 * 3. Ensures Flutter native libraries are loaded (critical for background starts)
 * 4. Creates a headless FlutterEngine (no UI)
 * 5. Looks up the stored Dart callback dispatcher handle
 * 6. Executes the Dart callback which initializes the SDK and runs due actions
 * 7. Dart signals completion via "backgroundTaskComplete"
 * 8. Service releases the WakeLock and stops itself
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

        try {
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
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start background execution: ${e.message}", e)
            cleanupAndStop()
        }

        return START_NOT_STICKY
    }

    private fun startHeadlessFlutterEngine(dispatcherHandle: Long, actionHandlerHandle: Long) {
        if (flutterEngine != null) {
            Log.d(TAG, "FlutterEngine already running")
            return
        }

        Log.d(TAG, "Starting headless FlutterEngine")

        // Ensure Flutter native libraries are loaded.
        // This is critical when the service starts in a new process where
        // FlutterJNI hasn't been loaded yet (causes UnsatisfiedLinkError otherwise).
        val flutterLoader: FlutterLoader = FlutterInjector.instance().flutterLoader()
        if (!flutterLoader.initialized()) {
            flutterLoader.startInitialization(applicationContext)
            flutterLoader.ensureInitializationComplete(applicationContext, null)
        }

        val callbackInfo: FlutterCallbackInformation?
        try {
            callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle)
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Flutter native library not available for callback lookup. " +
                    "Background execution failed: ${e.message}")
            cleanupAndStop()
            return
        }

        if (callbackInfo == null) {
            Log.e(TAG, "Could not find callback for handle: $dispatcherHandle. " +
                    "Ensure the app was launched at least once to register callbacks.")
            cleanupAndStop()
            return
        }

        val appBundlePath = flutterLoader.findAppBundlePath()
        Log.d(TAG, "Callback info: lib=${callbackInfo.callbackLibraryPath}, " +
                "fn=${callbackInfo.callbackName}, bundle=$appBundlePath")

        try {
            // Create the headless engine with automatic plugin registration disabled
            // (we only need the method channel, not the full plugin set)
            flutterEngine = FlutterEngine(this, null, true).also { engine ->
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

                // Execute the Dart callback dispatcher using DartEntrypoint
                // We must pass BOTH the library URI and function name so the
                // engine can resolve the function in the correct Dart library.
                val entrypoint = DartEntrypoint(
                    appBundlePath,
                    callbackInfo.callbackLibraryPath,
                    callbackInfo.callbackName
                )
                Log.d(TAG, "Executing Dart entrypoint: ${callbackInfo.callbackLibraryPath}#${callbackInfo.callbackName}")
                engine.dartExecutor.executeDartEntrypoint(entrypoint)

                // Send the action handler callback handle to Dart so it can
                // look up and call the developer's handler function
                backgroundChannel?.invokeMethod(
                    "executeBackgroundTask",
                    mapOf("callbackHandle" to actionHandlerHandle)
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create headless FlutterEngine: ${e.message}", e)
            cleanupAndStop()
        }
    }

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "ActionSchedulerSDK:BackgroundExecution"
            ).apply {
                acquire(10 * 60 * 1000L) // 10 minute timeout
            }
            Log.d(TAG, "WakeLock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire WakeLock: ${e.message}", e)
        }
    }

    private fun cleanupAndStop() {
        Log.d(TAG, "Cleaning up and stopping service")

        try {
            backgroundChannel?.setMethodCallHandler(null)
            backgroundChannel = null

            flutterEngine?.destroy()
            flutterEngine = null

            wakeLock?.let {
                if (it.isHeld) it.release()
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "Error during cleanup: ${e.message}", e)
        }

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
    }

    init {
        sInstance = this
    }
}
