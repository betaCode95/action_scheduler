/// Status of a single action execution.
enum ExecutionStatus {
  /// The action completed successfully.
  success,

  /// The action failed during execution.
  failed,

  /// The action was missed (e.g., device was off at scheduled time).
  missed,

  /// The action was skipped (e.g., manually or due to a precondition).
  skipped,
}

/// Reason for a failed or missed execution.
enum FailureReason {
  /// No failure — execution was successful.
  none,

  /// The action's callback threw an exception.
  callbackError,

  /// The device was offline/unavailable at the scheduled time.
  deviceOffline,

  /// The app was not running at the scheduled time.
  appNotRunning,

  /// The action timed out during execution.
  timeout,

  /// An unknown or uncategorized error occurred.
  unknown,
}

/// Where the execution took place.
enum ExecutionContext {
  /// Executed while the app was in the foreground (via Timer or manual trigger).
  foreground,

  /// Executed in a headless background isolate (via AlarmManager / BGTask).
  background,

  /// Executed during startup recovery (catch-up for missed runs).
  recovery,
}

/// A record of a single action execution attempt.
///
/// Tracks when the action was scheduled vs when it actually ran,
/// the outcome, any error details, and whether it ran in the
/// foreground or background.
class ExecutionRecord {
  /// Unique identifier for this execution record.
  final String id;

  /// The ID of the scheduled action this execution belongs to.
  final String actionId;

  /// The time the action was originally scheduled to run.
  final DateTime scheduledTime;

  /// The time execution actually started (null if missed/skipped).
  final DateTime? executionTime;

  /// The outcome of the execution.
  final ExecutionStatus status;

  /// Duration of the execution in milliseconds.
  final int durationMs;

  /// Human-readable error message (if failed).
  final String? errorMessage;

  /// Categorized failure reason.
  final FailureReason failureReason;

  /// Whether this was a foreground, background, or recovery execution.
  final ExecutionContext executionContext;

  const ExecutionRecord({
    required this.id,
    required this.actionId,
    required this.scheduledTime,
    this.executionTime,
    required this.status,
    this.durationMs = 0,
    this.errorMessage,
    this.failureReason = FailureReason.none,
    this.executionContext = ExecutionContext.foreground,
  });

  /// Serializes to a map for database storage.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'actionId': actionId,
      'scheduledTime': scheduledTime.toIso8601String(),
      'executionTime': executionTime?.toIso8601String(),
      'status': status.index,
      'durationMs': durationMs,
      'errorMessage': errorMessage,
      'failureReason': failureReason.index,
      'executionContext': executionContext.index,
    };
  }

  /// Deserializes from a database map.
  factory ExecutionRecord.fromMap(Map<String, dynamic> map) {
    return ExecutionRecord(
      id: map['id'] as String,
      actionId: map['actionId'] as String,
      scheduledTime: DateTime.parse(map['scheduledTime'] as String),
      executionTime: map['executionTime'] != null
          ? DateTime.parse(map['executionTime'] as String)
          : null,
      status: ExecutionStatus.values[map['status'] as int],
      durationMs: map['durationMs'] as int? ?? 0,
      errorMessage: map['errorMessage'] as String?,
      failureReason: FailureReason.values[map['failureReason'] as int? ?? 0],
      executionContext: ExecutionContext
          .values[map['executionContext'] as int? ?? 0],
    );
  }

  /// Whether this execution was successful.
  bool get isSuccess => status == ExecutionStatus.success;

  /// Whether this execution represents a failure.
  bool get isFailure =>
      status == ExecutionStatus.failed || status == ExecutionStatus.missed;

  @override
  String toString() =>
      'ExecutionRecord(actionId: $actionId, status: $status, context: ${executionContext.name}, scheduled: $scheduledTime)';
}
