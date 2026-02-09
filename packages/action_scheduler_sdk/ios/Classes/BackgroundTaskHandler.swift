import Flutter
import UIKit
import BackgroundTasks

/// Handles iOS BGProcessingTask execution by starting a headless FlutterEngine.
///
/// When the OS triggers a BGProcessingTask:
/// 1. Creates a headless FlutterEngine (no UI)
/// 2. Looks up the stored Dart callback dispatcher handle
/// 3. Executes the Dart callback which runs due scheduled actions
/// 4. Waits for Dart to signal completion
/// 5. Marks the BGTask as complete
@available(iOS 13.0, *)
class BackgroundTaskHandler: NSObject {

    static let shared = BackgroundTaskHandler()

    private var flutterEngine: FlutterEngine?
    private var backgroundChannel: FlutterMethodChannel?
    private var currentTask: BGProcessingTask?

    private override init() {
        super.init()
    }

    /// Called by BGTaskScheduler when the background task is triggered.
    func handleBackgroundTask(_ task: BGProcessingTask) {
        NSLog("[ActionSchedulerSDK] BGProcessingTask triggered")

        currentTask = task

        // Set expiration handler
        task.expirationHandler = { [weak self] in
            NSLog("[ActionSchedulerSDK] BGTask expired")
            self?.cleanup()
            task.setTaskCompleted(success: false)
        }

        let dispatcherHandle = ActionSchedulerPlugin.getDispatcherHandle()
        let actionHandlerHandle = ActionSchedulerPlugin.getActionHandlerHandle()

        guard dispatcherHandle != 0 else {
            NSLog("[ActionSchedulerSDK] No callback dispatcher registered")
            task.setTaskCompleted(success: false)
            return
        }

        startHeadlessEngine(
            dispatcherHandle: dispatcherHandle,
            actionHandlerHandle: actionHandlerHandle
        )
    }

    /// Starts a headless FlutterEngine to execute the Dart callback.
    private func startHeadlessEngine(dispatcherHandle: Int64, actionHandlerHandle: Int64) {
        guard flutterEngine == nil else {
            NSLog("[ActionSchedulerSDK] FlutterEngine already running")
            return
        }

        NSLog("[ActionSchedulerSDK] Starting headless FlutterEngine")

        guard let callbackInfo = FlutterCallbackCache.lookupCallbackInformation(dispatcherHandle) else {
            NSLog("[ActionSchedulerSDK] Could not find callback for handle: \(dispatcherHandle)")
            currentTask?.setTaskCompleted(success: false)
            return
        }

        let engine = FlutterEngine(name: "ActionSchedulerBackground", project: nil, allowHeadlessExecution: true)
        flutterEngine = engine

        // Set up method channel on the background engine
        backgroundChannel = FlutterMethodChannel(
            name: ActionSchedulerPlugin.channelName,
            binaryMessenger: engine.binaryMessenger
        )

        backgroundChannel?.setMethodCallHandler { [weak self] call, result in
            if call.method == "backgroundTaskComplete" {
                NSLog("[ActionSchedulerSDK] Background task complete signal from Dart")
                result(true)
                self?.currentTask?.setTaskCompleted(success: true)
                self?.cleanup()
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        // Start the engine with the callback
        let success = engine.run(
            withEntrypoint: callbackInfo.callbackName,
            libraryURI: callbackInfo.callbackLibraryPath
        )

        if success {
            // Send the action handler handle to Dart
            backgroundChannel?.invokeMethod(
                "executeBackgroundTask",
                arguments: ["callbackHandle": actionHandlerHandle]
            )
        } else {
            NSLog("[ActionSchedulerSDK] Failed to start FlutterEngine")
            currentTask?.setTaskCompleted(success: false)
            cleanup()
        }
    }

    /// Called when Dart signals task completion.
    func signalCompletion() {
        NSLog("[ActionSchedulerSDK] Completion signaled")
        currentTask?.setTaskCompleted(success: true)
        cleanup()
    }

    /// Cleans up the headless engine.
    private func cleanup() {
        backgroundChannel?.setMethodCallHandler(nil)
        backgroundChannel = nil
        flutterEngine?.destroyContext()
        flutterEngine = nil
        currentTask = nil
    }
}
