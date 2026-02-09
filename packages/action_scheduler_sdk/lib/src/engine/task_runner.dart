import 'dart:async';

import 'package:uuid/uuid.dart';

import '../models/execution_record.dart';
import '../models/scheduled_action.dart';
import '../persistence/action_repository.dart';
import '../persistence/execution_repository.dart';
import 'schedule_evaluator.dart';

/// The type signature for action handler callbacks.
///
/// Receives the action ID and optional metadata. Should return `true`
/// for success or `false` for failure. Throwing an exception is treated
/// as a failure.
typedef ActionHandler = Future<bool> Function(
  String actionId,
  Map<String, String>? metadata,
);

/// Executes due actions, records results, and computes next run times.
///
/// The TaskRunner is the core execution engine of the SDK. It:
/// 1. Finds all actions that are due to run
/// 2. Executes them via the registered handler
/// 3. Records execution results (success/failure/duration/context)
/// 4. Computes and stores the next run time
class TaskRunner {
  final ActionRepository _actionRepo;
  final ExecutionRepository _executionRepo;
  final Uuid _uuid = const Uuid();

  /// The registered action handler provided by the app developer.
  ActionHandler? _handler;

  /// Timer for periodic foreground checks.
  Timer? _foregroundTimer;

  /// The execution context to tag records with.
  /// Defaults to foreground; set to background when running in a headless isolate.
  ExecutionContext executionContext;

  TaskRunner(this._actionRepo, this._executionRepo, {
    this.executionContext = ExecutionContext.foreground,
  });

  /// Registers the action handler that will be called when actions are due.
  void registerHandler(ActionHandler handler) {
    _handler = handler;
  }

  /// Starts periodic foreground checking for due actions.
  ///
  /// Checks every [checkInterval] (default: 30 seconds) for actions
  /// whose next run time has passed.
  void startForegroundScheduler({
    Duration checkInterval = const Duration(seconds: 30),
  }) {
    _foregroundTimer?.cancel();
    _foregroundTimer = Timer.periodic(checkInterval, (_) async {
      try {
        await runDueActions();
      } catch (e) {
        // Silently handle database errors (e.g., DB closed during background execution).
        // The next timer tick will retry.
      }
    });
  }

  /// Stops the foreground scheduler.
  void stopForegroundScheduler() {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
  }

  /// Checks for and executes all actions that are currently due.
  ///
  /// Returns the number of actions that were executed.
  /// Database errors are caught and return 0 (next tick retries).
  Future<int> runDueActions() async {
    if (_handler == null) return 0;

    try {
      final dueActions = await _actionRepo.getDueActions();
      int executed = 0;

      for (final action in dueActions) {
        await _executeAction(action);
        executed++;
      }

      return executed;
    } catch (e) {
      // Database may be temporarily unavailable (e.g., closed by a
      // concurrent background isolate). Return 0 and retry next tick.
      return 0;
    }
  }

  /// Performs startup recovery: detects missed actions and logs them.
  ///
  /// For each active action whose nextRunAt is in the past:
  /// - Logs missed execution records for each missed run
  /// - Executes the most recent missed run (catch-up)
  /// - Computes and stores the next future run time
  Future<int> performStartupRecovery() async {
    if (_handler == null) return 0;

    final activeActions = await _actionRepo.getActive();
    int recovered = 0;

    for (final action in activeActions) {
      if (action.nextRunAt == null) continue;
      if (!ScheduleEvaluator.isDue(action.nextRunAt!)) continue;

      // Find all missed run times
      final lastRun = action.lastRunAt ?? action.createdAt;
      final missedTimes = ScheduleEvaluator.computeMissedRuns(
        action.schedule,
        lastRunAt: lastRun,
      );

      // Log missed executions (except the last one which we'll run)
      for (int i = 0; i < missedTimes.length - 1; i++) {
        await _executionRepo.insert(ExecutionRecord(
          id: _uuid.v4(),
          actionId: action.id,
          scheduledTime: missedTimes[i],
          status: ExecutionStatus.missed,
          failureReason: FailureReason.appNotRunning,
          errorMessage: 'App was not running at scheduled time',
        ));
      }

      // Execute the most recent due occurrence (catch-up execution)
      if (missedTimes.isNotEmpty) {
        await _executeAction(
          action,
          scheduledTime: missedTimes.last,
          contextOverride: ExecutionContext.recovery,
        );
        recovered++;
      }
    }

    return recovered;
  }

  /// Executes a single action and records the result.
  Future<void> _executeAction(
    ScheduledAction action, {
    DateTime? scheduledTime,
    ExecutionContext? contextOverride,
  }) async {
    final effectiveScheduledTime =
        scheduledTime ?? action.nextRunAt ?? DateTime.now();
    final effectiveContext = contextOverride ?? executionContext;
    final executionStart = DateTime.now();

    try {
      final success = await _handler!(action.id, action.metadata);
      final executionEnd = DateTime.now();
      final durationMs =
          executionEnd.difference(executionStart).inMilliseconds;

      await _executionRepo.insert(ExecutionRecord(
        id: _uuid.v4(),
        actionId: action.id,
        scheduledTime: effectiveScheduledTime,
        executionTime: executionStart,
        status: success ? ExecutionStatus.success : ExecutionStatus.failed,
        durationMs: durationMs,
        failureReason: success ? FailureReason.none : FailureReason.callbackError,
        errorMessage: success ? null : 'Action handler returned false',
        executionContext: effectiveContext,
      ));

      // Compute next run time
      final nextRun = ScheduleEvaluator.computeNextRun(action.schedule);
      await _actionRepo.updateRunTimes(
        id: action.id,
        lastRunAt: executionStart,
        nextRunAt: nextRun,
      );
    } catch (e) {
      final executionEnd = DateTime.now();
      final durationMs =
          executionEnd.difference(executionStart).inMilliseconds;

      await _executionRepo.insert(ExecutionRecord(
        id: _uuid.v4(),
        actionId: action.id,
        scheduledTime: effectiveScheduledTime,
        executionTime: executionStart,
        status: ExecutionStatus.failed,
        durationMs: durationMs,
        failureReason: FailureReason.callbackError,
        errorMessage: e.toString(),
        executionContext: effectiveContext,
      ));

      // Still advance the next run time on failure
      final nextRun = ScheduleEvaluator.computeNextRun(action.schedule);
      await _actionRepo.updateRunTimes(
        id: action.id,
        lastRunAt: executionStart,
        nextRunAt: nextRun,
      );
    }
  }

  /// Manually triggers a specific action regardless of its schedule.
  ///
  /// Useful for testing or one-off immediate execution.
  Future<ExecutionRecord> triggerAction(String actionId) async {
    final action = await _actionRepo.getById(actionId);
    if (action == null) {
      throw ArgumentError('Action not found: $actionId');
    }
    if (_handler == null) {
      throw StateError('No action handler registered');
    }

    final executionStart = DateTime.now();

    try {
      final success = await _handler!(action.id, action.metadata);
      final executionEnd = DateTime.now();
      final durationMs =
          executionEnd.difference(executionStart).inMilliseconds;

      final record = ExecutionRecord(
        id: _uuid.v4(),
        actionId: actionId,
        scheduledTime: executionStart,
        executionTime: executionStart,
        status: success ? ExecutionStatus.success : ExecutionStatus.failed,
        durationMs: durationMs,
        failureReason: success ? FailureReason.none : FailureReason.callbackError,
        errorMessage: success ? null : 'Action handler returned false',
        executionContext: executionContext,
      );

      await _executionRepo.insert(record);
      return record;
    } catch (e) {
      final executionEnd = DateTime.now();
      final durationMs =
          executionEnd.difference(executionStart).inMilliseconds;

      final record = ExecutionRecord(
        id: _uuid.v4(),
        actionId: actionId,
        scheduledTime: executionStart,
        executionTime: executionStart,
        status: ExecutionStatus.failed,
        durationMs: durationMs,
        failureReason: FailureReason.callbackError,
        errorMessage: e.toString(),
        executionContext: executionContext,
      );

      await _executionRepo.insert(record);
      return record;
    }
  }

  /// Disposes resources used by the task runner.
  void dispose() {
    stopForegroundScheduler();
  }
}
