import 'dart:async';

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
///
/// ## Quick Start
///
/// ```dart
/// // Initialize the SDK
/// await ActionScheduler.initialize();
///
/// // Register an action handler
/// ActionScheduler.instance.onActionDue = (actionId, metadata) async {
///   switch (actionId) {
///     case 'daily-save':
///       await performDailySave();
///       return true;
///     default:
///       return false;
///   }
/// };
///
/// // Register a scheduled action
/// await ActionScheduler.instance.register(
///   ScheduledAction(
///     id: 'daily-save',
///     name: 'Daily DigiGold Save',
///     schedule: Schedule.daily(hour: 9, minute: 0),
///   ),
/// );
///
/// // Start the scheduler
/// ActionScheduler.instance.start();
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
  /// Set [enableNotifications] to false to skip notification initialization
  /// (useful for testing).
  static Future<void> initialize({
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
  /// 3. Start periodic checking for due actions
  ///
  /// Returns the number of actions recovered during startup.
  Future<int> start({
    Duration checkInterval = const Duration(seconds: 30),
  }) async {
    final recovered = await _taskRunner.performStartupRecovery();

    // Reschedule notifications for all active actions
    final activeActions = await _actionRepo.getActive();
    await _notificationService.rescheduleAll(activeActions);

    // Start the foreground timer
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
  /// Computes the first next run time and persists the action.
  /// If notifications are configured, schedules the reminder.
  Future<void> register(ScheduledAction action) async {
    // Compute next run time
    final nextRun = ScheduleEvaluator.computeNextRun(action.schedule);
    final actionWithNextRun = action.copyWith(nextRunAt: nextRun);

    await _actionRepo.insert(actionWithNextRun);

    // Schedule notification if configured
    if (actionWithNextRun.notification != null) {
      await _notificationService.scheduleForAction(actionWithNextRun);
    }

    _actionChanges.add(actionWithNextRun);
  }

  /// Updates an existing scheduled action.
  ///
  /// Recomputes next run time and reschedules notification.
  Future<void> update(ScheduledAction action) async {
    final nextRun = ScheduleEvaluator.computeNextRun(action.schedule);
    final updated = action.copyWith(nextRunAt: nextRun);

    await _actionRepo.update(updated);

    // Reschedule notification
    await _notificationService.cancelForAction(action.id);
    if (updated.notification != null && updated.isActive) {
      await _notificationService.scheduleForAction(updated);
    }

    _actionChanges.add(updated);
  }

  /// Unregisters (deletes) a scheduled action and all its execution logs.
  Future<void> unregister(String actionId) async {
    await _notificationService.cancelForAction(actionId);
    await _executionRepo.deleteByActionId(actionId);
    await _actionRepo.delete(actionId);
  }

  /// Pauses a scheduled action (it won't run until resumed).
  Future<void> pause(String actionId) async {
    await _actionRepo.setActive(actionId, false);
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
    return _executionRepo.getByActionId(actionId, limit: limit, offset: offset);
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
