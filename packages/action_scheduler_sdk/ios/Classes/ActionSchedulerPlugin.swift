import Flutter
import UIKit
import BackgroundTasks

/// Flutter plugin that bridges Dart calls to iOS BGTaskScheduler.
///
/// Handles method channel operations for scheduling/canceling background tasks
/// and stores callback handles in UserDefaults for headless engine execution.
public class ActionSchedulerPlugin: NSObject, FlutterPlugin {

    static let channelName = "com.actionscheduler.sdk/background"
    static let bgTaskIdentifier = "com.actionscheduler.background"
    private static let dispatcherHandleKey = "dispatcher_callback_handle"
    private static let actionHandlerHandleKey = "action_handler_callback_handle"

    private var channel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = ActionSchedulerPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Register the BGTask handler
        if #available(iOS 13.0, *) {
            registerBackgroundTask()
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Arguments required", details: nil))
            return
        }

        switch call.method {
        case "registerCallbackDispatcher":
            guard let callbackHandle = args["callbackHandle"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "callbackHandle required", details: nil))
                return
            }
            UserDefaults.standard.set(callbackHandle, forKey: ActionSchedulerPlugin.dispatcherHandleKey)
            result(true)

        case "scheduleAlarm":
            guard let triggerAtMillis = args["triggerAtMillis"] as? Int64 else {
                result(FlutterError(code: "INVALID_ARGS", message: "triggerAtMillis required", details: nil))
                return
            }
            if #available(iOS 13.0, *) {
                scheduleBGTask(triggerAtMillis: triggerAtMillis)
            }
            result(true)

        case "cancelAlarm":
            if #available(iOS 13.0, *) {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: ActionSchedulerPlugin.bgTaskIdentifier)
            }
            result(true)

        case "backgroundTaskComplete":
            BackgroundTaskHandler.shared.signalCompletion()
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - BGTaskScheduler

    @available(iOS 13.0, *)
    private static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: bgTaskIdentifier,
            using: nil
        ) { task in
            guard let bgTask = task as? BGProcessingTask else { return }
            BackgroundTaskHandler.shared.handleBackgroundTask(bgTask)
        }
    }

    @available(iOS 13.0, *)
    private func scheduleBGTask(triggerAtMillis: Int64) {
        let request = BGProcessingTaskRequest(identifier: ActionSchedulerPlugin.bgTaskIdentifier)
        let triggerDate = Date(timeIntervalSince1970: Double(triggerAtMillis) / 1000.0)
        request.earliestBeginDate = triggerDate
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            NSLog("[ActionSchedulerSDK] BGTask scheduled for \(triggerDate)")
        } catch {
            NSLog("[ActionSchedulerSDK] Failed to schedule BGTask: \(error)")
        }
    }

    // MARK: - Callback Handle Helpers

    static func getDispatcherHandle() -> Int64 {
        return Int64(UserDefaults.standard.integer(forKey: dispatcherHandleKey))
    }

    static func getActionHandlerHandle() -> Int64 {
        return Int64(UserDefaults.standard.integer(forKey: actionHandlerHandleKey))
    }
}
