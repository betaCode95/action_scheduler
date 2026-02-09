import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'background/background_channel.dart';
import 'background/callback_dispatcher.dart' as bg;
import 'engine/schedule_evaluator.dart';
import 'engine/task_runner.dart';
import 'models/execution_record.dart';
import 'models/scheduled_action.dart';
import 'notifications/notification_service.dart';
import 'persistence/action_repository.dart';
import 'persistence/database_provider.dart';
import 'persistence/execution_repository.dart';

/// The main entry point for the Action Scheduler SDK.
///
/// Provides a simple, high-level API for:
/// - Registering and managing scheduled actions
/// - Querying execution history
/// - Configuring action handlers
/// - Managing the scheduling lifecycle
/// - Background execution via native platform alarms
///
/// ## Quick Start
///
/// ```dart
/// @pragma('vm:entry-point')
/// void backgroundCallback() {
///   ActionScheduler.executeInBackground(myHandler);
/// }
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await ActionScheduler.initialize(
///     backgroundCallback: backgroundCallback,
///     actionHandler: myHandler,
///   );
///
///   ActionScheduler.instance.onActionDue = myHandler;
///   await ActionScheduler.instance.register(...);
///   ActionScheduler.instance.start();
///   runApp(MyApp());
/// }
/// ```
class ActionScheduler {
  // --- Singleton pattern ---

  static ActionScheduler? _instance;

  /// Returns the singleton instance. Throws if not initialized.
  static ActionScheduler get instance {
    if (_instance == null) {
      throw StateError(
        'ActionScheduler not initialized. Call ActionScheduler.initialize() first.',
      );
    }
    return _instance!;
  }

  /// Whether the SDK has been initialized.
  static bool get isInitialized => _instance != null;

  // --- Internal components ---

  final DatabaseProvider _dbProvider;
  final ActionRepository _actionRepo;
  final ExecutionRepository _executionRepo;
  final TaskRunner _taskRunner;
  final NotificationService _notificationService;

  /// Stream controller for broadcasting action state changes.
  final StreamController<ScheduledAction> _actionChanges =
      StreamController.broadcast();

  /// Stream controller for broadcasting new execution records.
  final StreamController<ExecutionRecord> _executionChanges =
      StreamController.broadcast();

  ActionScheduler._({
    required DatabaseProvider dbProvider,
    required ActionRepository actionRepo,
    required ExecutionRepository executionRepo,
    required TaskRunner taskRunner,
    required NotificationService notificationService,
  })  : _dbProvider = dbProvider,
        _actionRepo = actionRepo,
        _executionRepo = executionRepo,
        _taskRunner = taskRunner,
        _notificationService = notificationService;

  /// Initializes the Action Scheduler SDK.
  ///
  /// Must be called once before using [instance]. Typically called
  /// in `main()` before `runApp()`.
  ///
  /// [backgroundCallback] is a top-level function annotated with
  /// `@pragma('vm:entry-point')` that will be invoked by the native platform
  /// when a background alarm fires. It should call [executeInBackground].
  ///
  /// [actionHandler] is the developer's action handler function. It must be
  /// a top-level or static function so it can be looked up in background isolates.
  ///
  /// Set [enableNotifications] to false to skip notification initialization
  /// (useful for testing).
  static Future<void> initialize({
    Function? backgroundCallback,
    ActionHandler? actionHandler,
    bool enableNotifications = true,
  }) async {
    if (_instance != null) return;

    final dbProvider = DatabaseProvider();
    final actionRepo = ActionRepository(dbProvider);
    final executionRepo = ExecutionRepository(dbProvider);
    final taskRunner = TaskRunner(actionRepo, executionRepo);
    final notificationService = NotificationService();

    if (enableNotifications) {
      await notificationService.initialize();
    }

    _instance = ActionScheduler._(
      dbProvider: dbProvider,
      actionRepo: actionRepo,
      executionRepo: executionRepo,
      taskRunner: taskRunner,
      notificationService: notificationService,
    );

    // Register the background callback dispatcher with native code
    if (backgroundCallback != null) {
      final dispatcherHandle =
          PluginUtilities.getCallbackHandle(bg.callbackDispatcher);
      if (dispatcherHandle != null) {
        await BackgroundChannel.registerCallbackDispatcher(dispatcherHandle);
      }
    }

    // Store the action handler handle so background isolate can look it up
    if (actionHandler != null) {
      final handlerHandle = PluginUtilities.getCallbackHandle(actionHandler);
      if (handlerHandle != null) {
        try {
          await BackgroundChannel.registerActionHandler(handlerHandle);
        } catch (_) {
          // May fail if platform not available (e.g., tests)
        }
      }
    }
  }

  /// Executes due actions in a background isolate.
  ///
  /// This should be called from the top-level background callback function:
  ///
  /// ```dart
  /// @pragma('vm:entry-point')
  /// void backgroundCallback() {
  ///   ActionScheduler.executeInBackground(myHandler);
  /// }
  /// ```
  static void executeInBackground(ActionHandler handler) {
    WidgetsFlutterBinding.ensureInitialized();

    BackgroundChannel.setMethodCallHandler((call) async {
      if (call.method == 'executeBackgroundTask') {
        // Initialize persistence in the background isolate
        final dbProvider = DatabaseProvider();
        final actionRepo = ActionRepository(dbProvider);
        final executionRepo = ExecutionRepository(dbProvider);
        final taskRunner = TaskRunner(
          actionRepo,
          executionRepo,
          executionContext: ExecutionContext.background,
        );

        taskRunner.registerHandler(handler);

        // Run all due actions
        await taskRunner.runDueActions();

        // Also schedule the next alarm for each executed action
        final activeActions = await actionRepo.getActive();
        for (final action in activeActions) {
          if (action.nextRunAt != null) {
            await _scheduleNativeAlarm(action);
          }
        }

        await dbProvider.close();

        // Signal native that we're done
        await BackgroundChannel.backgroundTaskComplete();
      }
    });
  }

  // ==========================================================================
  // Action Handler Registration
  // ==========================================================================

  /// Sets the callback that is invoked when a scheduled action is due.
  ///
  /// The callback receives the action ID and optional metadata, and should
  /// return `true` for success or `false` for failure. Throwing is treated
  /// as failure.
  ///
  /// Must be set before calling [start].
  set onActionDue(ActionHandler handler) {
    _taskRunner.registerHandler(handler);
  }

  // ==========================================================================
  // Scheduling Lifecycle
  // ==========================================================================

  /// Starts the foreground scheduler and performs startup recovery.
  ///
  /// This should be called after setting [onActionDue] and registering
  /// initial actions. It will:
  /// 1. Detect and log any missed executions since last run
  /// 2. Execute the most recent missed run for each action (catch-up)
  /// 3. Schedule native alarms for all active actions
  /// 4. Start periodic foreground checking for due actions
  ///
  /// Returns the number of actions recovered during startup.
  Future<int> start({
    Duration checkInterval = const Duration(seconds: 30),
  }) async {
    final recovered = await _taskRunner.performStartupRecovery();

    // Reschedule notifications for all active actions
    final activeActions = await _actionRepo.getActive();
    await _notificationService.rescheduleAll(activeActions);

    // Schedule native background alarms for all active actions
    await _scheduleAllNativeAlarms(activeActions);

    // Start the foreground timer (belt-and-suspenders with native alarms)
    _taskRunner.startForegroundScheduler(checkInterval: checkInterval);

    return recovered;
  }

  /// Stops the foreground scheduler.
  void stop() {
    _taskRunner.stopForegroundScheduler();
  }

  // ==========================================================================
  // Action Management
  // ==========================================================================

  /// Registers a new scheduled action.
  ///
  /// Computes the first next run time, persists the action, schedules
  /// a native background alarm, and optionally schedules a notification.
  Future<void> register(ScheduledAction action) async {
    // Compute next run time
    final nextRun = ScheduleEvaluator.computeNextRun(action.schedule);
    final actionWithNextRun = action.copyWith(nextRunAt: nextRun);

    await _actionRepo.insert(actionWithNextRun);

    // Schedule native background alarm
    await _scheduleNativeAlarm(actionWithNextRun);

    // Schedule notification if configured
    if (actionWithNextRun.notification != null) {
      await _notificationService.scheduleForAction(actionWithNextRun);
    }

    _actionChanges.add(actionWithNextRun);
  }

  /// Updates an existing scheduled action.
  ///
  /// Recomputes next run time, reschedules native alarm and notification.
  Future<void> update(ScheduledAction action) async {
    final nextRun = ScheduleEvaluator.computeNextRun(action.schedule);
    final updated = action.copyWith(nextRunAt: nextRun);

    await _actionRepo.update(updated);

    // Reschedule native alarm
    await _cancelNativeAlarm(action.id);
    if (updated.isActive) {
      await _scheduleNativeAlarm(updated);
    }

    // Reschedule notification
    await _notificationService.cancelForAction(action.id);
    if (updated.notification != null && updated.isActive) {
      await _notificationService.scheduleForAction(updated);
    }

    _actionChanges.add(updated);
  }

  /// Unregisters (deletes) a scheduled action and all its execution logs.
  Future<void> unregister(String actionId) async {
    await _cancelNativeAlarm(actionId);
    await _notificationService.cancelForAction(actionId);
    await _executionRepo.deleteByActionId(actionId);
    await _actionRepo.delete(actionId);
  }

  /// Pauses a scheduled action (it won't run until resumed).
  Future<void> pause(String actionId) async {
    await _actionRepo.setActive(actionId, false);
    await _cancelNativeAlarm(actionId);
    await _notificationService.cancelForAction(actionId);

    final action = await _actionRepo.getById(actionId);
    if (action != null) _actionChanges.add(action);
  }

  /// Resumes a paused action.
  Future<void> resume(String actionId) async {
    await _actionRepo.setActive(actionId, true);

    final action = await _actionRepo.getById(actionId);
    if (action != null) {
      // Recompute next run time
      final nextRun = ScheduleEvaluator.computeNextRun(action.schedule);
      await _actionRepo.updateRunTimes(
        id: actionId,
        lastRunAt: action.lastRunAt,
        nextRunAt: nextRun,
      );

      final updated = action.copyWith(nextRunAt: nextRun, isActive: true);

      // Schedule native alarm
      await _scheduleNativeAlarm(updated);

      if (updated.notification != null) {
        await _notificationService.scheduleForAction(updated);
      }
      _actionChanges.add(updated);
    }
  }

  /// Manually triggers an action immediately, regardless of schedule.
  Future<ExecutionRecord> triggerNow(String actionId) async {
    final record = await _taskRunner.triggerAction(actionId);
    _executionChanges.add(record);
    return record;
  }

  // ==========================================================================
  // Permissions
  // ==========================================================================

  /// Checks if exact alarm scheduling is permitted on the current device.
  ///
  /// On Android 12+ (API 31), `SCHEDULE_EXACT_ALARM` is a special permission
  /// that the user must grant in system settings. On older Android and iOS,
  /// this always returns true.
  ///
  /// Call this before [start] and prompt the user if it returns false.
  static Future<bool> canScheduleExactAlarms() async {
    return BackgroundChannel.canScheduleExactAlarms();
  }

  /// Opens the system settings page where the user can grant exact alarm
  /// permission (Android 12+ only). No effect on iOS or older Android.
  ///
  /// Typical usage:
  /// ```dart
  /// if (!await ActionScheduler.canScheduleExactAlarms()) {
  ///   // Show a dialog explaining why the permission is needed
  ///   await ActionScheduler.openExactAlarmSettings();
  /// }
  /// ```
  static Future<void> openExactAlarmSettings() async {
    return BackgroundChannel.openExactAlarmSettings();
  }

  // ==========================================================================
  // Native Alarm Scheduling (private)
  // ==========================================================================

  /// Schedules a native platform alarm for an action's next run time.
  static Future<void> _scheduleNativeAlarm(ScheduledAction action) async {
    if (action.nextRunAt == null || !action.isActive) return;
    try {
      await BackgroundChannel.scheduleAlarm(
        requestCode: action.id.hashCode,
        triggerAtMillis: action.nextRunAt!.millisecondsSinceEpoch,
      );
    } catch (_) {
      // Platform channel may not be available (e.g., in tests or web)
    }
  }

  /// Cancels a native platform alarm for an action.
  static Future<void> _cancelNativeAlarm(String actionId) async {
    try {
      await BackgroundChannel.cancelAlarm(requestCode: actionId.hashCode);
    } catch (_) {
      // Platform channel may not be available
    }
  }

  /// Schedules native alarms for all active actions.
  Future<void> _scheduleAllNativeAlarms(
      List<ScheduledAction> activeActions) async {
    for (final action in activeActions) {
      await _scheduleNativeAlarm(action);
    }
  }

  // ==========================================================================
  // Querying
  // ==========================================================================

  /// Retrieves all registered actions.
  Future<List<ScheduledAction>> getAllActions() async {
    return _actionRepo.getAll();
  }

  /// Retrieves only active actions.
  Future<List<ScheduledAction>> getActiveActions() async {
    return _actionRepo.getActive();
  }

  /// Retrieves a single action by its ID.
  Future<ScheduledAction?> getAction(String actionId) async {
    return _actionRepo.getById(actionId);
  }

  /// Retrieves execution logs for a specific action.
  Future<List<ExecutionRecord>> getExecutionLogs(
    String actionId, {
    int limit = 50,
    int offset = 0,
  }) async {
    return _executionRepo.getByActionId(actionId,
        limit: limit, offset: offset);
  }

  /// Retrieves all execution logs across all actions.
  Future<List<ExecutionRecord>> getAllExecutionLogs({
    int limit = 100,
    int offset = 0,
  }) async {
    return _executionRepo.getAll(limit: limit, offset: offset);
  }

  /// Retrieves only failed executions.
  Future<List<ExecutionRecord>> getFailedExecutions({
    int limit = 50,
    int offset = 0,
  }) async {
    return _executionRepo.getFailures(limit: limit, offset: offset);
  }

  /// Retrieves execution statistics for a specific action.
  Future<Map<String, int>> getExecutionStats(String actionId) async {
    return _executionRepo.getStats(actionId);
  }

  // ==========================================================================
  // Streams (Observability)
  // ==========================================================================

  /// Stream of action state changes (register, update, pause, resume).
  Stream<ScheduledAction> get actionChanges => _actionChanges.stream;

  /// Stream of new execution records.
  Stream<ExecutionRecord> get executionChanges => _executionChanges.stream;

  // ==========================================================================
  // Maintenance
  // ==========================================================================

  /// Deletes execution logs older than [retention].
  Future<int> pruneExecutionLogs({
    Duration retention = const Duration(days: 30),
  }) async {
    return _executionRepo.pruneOlderThan(retention);
  }

  /// Disposes all resources. Call when the app is shutting down.
  Future<void> dispose() async {
    _taskRunner.dispose();
    _actionChanges.close();
    _executionChanges.close();
    await _dbProvider.close();
    _instance = null;
  }
}
