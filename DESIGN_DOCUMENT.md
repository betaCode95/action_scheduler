# Action Scheduler SDK — Design Document

## 1. Overview

The Action Scheduler SDK is a cross-platform Flutter library that enables mobile developers to schedule and execute recurring tasks locally on the device. The SDK handles **when** to run a task, while the app developer defines **what** the task does.

### Core Capabilities

- **Flexible Scheduling**: Daily, weekly, monthly, and custom interval recurrence rules
- **Persistence**: All actions and execution history survive app restarts and device reboots
- **Reliability**: Startup recovery detects and logs missed executions, then catches up
- **Observability**: Complete execution audit trail with queryable success/failure logs
- **Notifications**: Configurable pre-action reminder notifications with adjustable lead times
- **Simple API**: Single facade class (`ActionScheduler`) with intuitive methods

---

## 2. Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        App Developer                            │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ Register      │  │ Action       │  │ Query Execution      │  │
│  │ Actions       │  │ Handler      │  │ Logs & Stats         │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                 │                      │              │
├─────────┼─────────────────┼──────────────────────┼──────────────┤
│         ▼                 ▼                      ▼              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  ActionScheduler (Facade)                │    │
│  │                                                         │    │
│  │  • register() / unregister() / pause() / resume()       │    │
│  │  • onActionDue = handler                                │    │
│  │  • start() / stop()                                     │    │
│  │  • getExecutionLogs() / getFailedExecutions()           │    │
│  │  • triggerNow() (manual execution)                      │    │
│  │  • actionChanges / executionChanges (streams)           │    │
│  └──────────┬──────────────────────────────────────────────┘    │
│             │                                                   │
│  ┌──────────┼──────────────────────────────────────────────┐    │
│  │          ▼            SDK Internals                     │    │
│  │                                                         │    │
│  │  ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │    │
│  │  │  Schedule    │  │  Task        │  │ Notification  │  │    │
│  │  │  Evaluator   │  │  Runner      │  │ Service       │  │    │
│  │  │             │  │              │  │               │  │    │
│  │  │ • Next run  │  │ • Execute    │  │ • Schedule    │  │    │
│  │  │   time calc │  │   due tasks  │  │   reminders   │  │    │
│  │  │ • Missed    │  │ • Record     │  │ • Cancel /    │  │    │
│  │  │   run       │  │   results    │  │   reschedule  │  │    │
│  │  │   detection │  │ • Startup    │  │               │  │    │
│  │  │             │  │   recovery   │  │               │  │    │
│  │  └─────────────┘  └──────┬───────┘  └───────────────┘  │    │
│  │                          │                              │    │
│  │  ┌───────────────────────┼───────────────────────────┐  │    │
│  │  │                       ▼                           │  │    │
│  │  │              Persistence Layer                    │  │    │
│  │  │                                                   │  │    │
│  │  │  ┌────────────────┐  ┌─────────────────────────┐  │  │    │
│  │  │  │ ActionRepo     │  │ ExecutionRepo            │  │  │    │
│  │  │  │                │  │                          │  │  │    │
│  │  │  │ • CRUD for     │  │ • CRUD for execution     │  │  │    │
│  │  │  │   scheduled    │  │   records                │  │  │    │
│  │  │  │   actions      │  │ • Stats aggregation      │  │  │    │
│  │  │  │ • Query due    │  │ • Failure filtering      │  │  │    │
│  │  │  │   actions      │  │ • Log retention/pruning  │  │  │    │
│  │  │  └────────┬───────┘  └──────────┬──────────────┘  │  │    │
│  │  │           │                     │                 │  │    │
│  │  │           ▼                     ▼                 │  │    │
│  │  │    ┌─────────────────────────────────────────┐    │  │    │
│  │  │    │         SQLite Database                  │    │  │    │
│  │  │    │                                         │    │  │    │
│  │  │    │  scheduled_actions │ execution_logs     │    │  │    │
│  │  │    └─────────────────────────────────────────┘    │  │    │
│  │  └───────────────────────────────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Responsibilities

| Component | Responsibility |
|-----------|---------------|
| **ActionScheduler** | Singleton facade — the only class app developers interact with |
| **ScheduleEvaluator** | Pure computation: next run times, missed run detection, day clamping |
| **TaskRunner** | Execution engine: runs due actions, records results, handles errors |
| **NotificationService** | Manages `flutter_local_notifications` lifecycle and scheduling |
| **ActionRepository** | CRUD for `scheduled_actions` table with query helpers |
| **ExecutionRepository** | CRUD for `execution_logs` table with stats/filtering |
| **DatabaseProvider** | SQLite connection management, schema creation, migrations |

### 2.3 Data Model

```
┌──────────────────────────┐       ┌──────────────────────────────┐
│    ScheduledAction       │       │     ExecutionRecord          │
├──────────────────────────┤       ├──────────────────────────────┤
│ id: String (PK)          │──┐    │ id: String (PK)             │
│ name: String             │  │    │ actionId: String (FK) ──────┼──┐
│ description: String?     │  │    │ scheduledTime: DateTime     │  │
│ schedule: Schedule       │  │    │ executionTime: DateTime?    │  │
│ isActive: bool           │  │    │ status: ExecutionStatus     │  │
│ createdAt: DateTime      │  │    │ durationMs: int             │  │
│ lastRunAt: DateTime?     │  │    │ errorMessage: String?       │  │
│ nextRunAt: DateTime?     │  └────│ failureReason: FailureReason│  │
│ notification: NotifConfig│       └──────────────────────────────┘  │
│ metadata: Map?           │                                        │
└──────────────────────────┘       1:N relationship ────────────────┘

┌──────────────────────────┐       ┌──────────────────────────────┐
│    Schedule              │       │    NotificationConfig        │
├──────────────────────────┤       ├──────────────────────────────┤
│ type: ScheduleType       │       │ title: String               │
│ hour: int (0-23)         │       │ body: String                │
│ minute: int (0-59)       │       │ leadTime: Duration          │
│ dayOfWeek: int? (1-7)    │       │ enabled: bool               │
│ dayOfMonth: int? (1-31)  │       └──────────────────────────────┘
│ interval: Duration?      │
└──────────────────────────┘
```

---

## 3. Key Design Decisions

### 3.1 Persistence: SQLite via sqflite

**Decision**: Use SQLite for all persistent storage.

**Rationale**:
- SQLite is battle-tested, available on both Android and iOS natively
- Supports complex queries (joins, aggregations) needed for execution stats
- ACID transactions ensure data consistency even during crashes
- `sqflite` is the most mature Flutter SQLite package with platform support
- Indexed columns (`actionId`, `scheduledTime`, `status`) ensure fast queries

**Alternative considered**: SharedPreferences — rejected due to lack of query capabilities, poor performance with large datasets, and no transactional guarantees.

### 3.2 Scheduling: Foreground Timer + Startup Recovery

**Decision**: Use a periodic foreground timer (30-second interval) combined with startup recovery.

**Rationale**:
- **Foreground Timer**: Checks every 30 seconds for due actions when the app is active. This provides near-exact-time execution with minimal resource usage.
- **Startup Recovery**: On every app launch, the SDK detects all missed executions (by comparing `nextRunAt` to current time), logs them as "missed," and executes the most recent one as a catch-up.
- This approach is **deterministic and testable** — no platform-specific background scheduling quirks.

**Alternative considered**: `workmanager` for background task execution — deferred to future scope due to:
  - Android WorkManager enforces a minimum 15-minute interval
  - iOS BGTaskScheduler has unpredictable timing
  - Background execution in Flutter isolates can't access the full app context
  - The foreground + recovery approach covers the core use cases reliably

### 3.3 Notification System: flutter_local_notifications

**Decision**: Use `flutter_local_notifications` for pre-action reminders.

**Rationale**:
- Cross-platform (Android + iOS) from a single API
- Supports exact-time scheduled notifications via `zonedSchedule`
- Notifications persist across app restarts (platform-managed)
- Configurable lead time per action (e.g., 15 min, 1 hour, 24 hours)
- Notification taps can carry a payload (action ID) for deep linking

### 3.4 API Design: Singleton Facade Pattern

**Decision**: Expose all SDK functionality through a single `ActionScheduler` class using the singleton pattern.

**Rationale**:
- Minimizes the learning curve — developers interact with one class
- Initialization is explicit (`ActionScheduler.initialize()`) and fail-fast
- Internal components are hidden behind the facade
- Streams (`actionChanges`, `executionChanges`) enable reactive UI updates

### 3.5 Action Handler: Callback Pattern

**Decision**: App developers register a single callback (`onActionDue`) that receives the action ID and metadata.

**Rationale**:
- Keeps the SDK agnostic about what actions do
- The `switch`-on-action-ID pattern is simple and explicit
- Metadata map allows passing arbitrary data (amount, currency, plan, etc.)
- Return value (`bool`) cleanly signals success/failure

---

## 4. Execution Flow

### 4.1 Normal Execution (App in Foreground)

```
Timer fires (every 30s)
    │
    ▼
TaskRunner.runDueActions()
    │
    ├── Query: SELECT * FROM scheduled_actions WHERE isActive=1 AND nextRunAt <= NOW()
    │
    ▼
For each due action:
    │
    ├── Call handler(actionId, metadata)
    │     │
    │     ├── Success → Record ExecutionRecord(status: success, durationMs: ...)
    │     └── Failure → Record ExecutionRecord(status: failed, errorMessage: ...)
    │
    ├── Compute next run time via ScheduleEvaluator
    ├── Update action's lastRunAt and nextRunAt
    └── Reschedule notification for next occurrence
```

### 4.2 Startup Recovery (After App Restart)

```
App starts → ActionScheduler.start()
    │
    ├── Query all active actions
    │
    ▼
For each action where nextRunAt < NOW():
    │
    ├── Compute all missed run times since lastRunAt
    │
    ├── Log each intermediate missed run as ExecutionRecord(status: missed)
    │
    ├── Execute the most recent missed run (catch-up)
    │     │
    │     ├── Success → Record as success
    │     └── Failure → Record as failed
    │
    ├── Compute next future run time
    └── Schedule notification for next occurrence
```

### 4.3 Notification Flow

```
Action registered with NotificationConfig
    │
    ├── Compute nextRunAt
    ├── Schedule notification at (nextRunAt - leadTime)
    │
    ▼
Notification fires (platform-managed, works even if app is closed)
    │
    ├── User sees reminder: "Your daily save will run at 9:00 AM"
    │
    ▼
When action executes:
    │
    ├── Cancel old notification
    ├── Compute new nextRunAt
    └── Schedule new notification at (new nextRunAt - leadTime)
```

---

## 5. Trade-offs and Assumptions

### Trade-offs

| Trade-off | Decision | Reason |
|-----------|----------|--------|
| **Background execution** | Deferred to future | Foreground + recovery covers core use cases without platform complexity |
| **Exact-time execution** | Best-effort (30s window) | Perfect timing requires AlarmManager/BGTaskScheduler which are platform-specific |
| **Concurrency** | Sequential execution | Avoids race conditions; sufficient for typical mobile task volumes |
| **Log retention** | Unlimited by default | `pruneExecutionLogs()` API available for cleanup; developer controls policy |
| **Handler registration** | Single callback | Simpler than per-action callbacks; `switch` pattern is idiomatic |

### Assumptions

1. **App launches regularly**: The startup recovery mechanism assumes the app is opened at least daily. Actions missed during extended inactivity will be caught up on next launch.
2. **Tasks are idempotent**: Catch-up execution assumes running a missed action once is safe, even if delayed.
3. **Tasks are lightweight**: The SDK executes tasks on the main isolate. CPU-intensive tasks should use `compute()` internally.
4. **Metadata is simple**: Key-value string pairs. Complex data should be stored externally and referenced by ID.

---

## 6. Future Scope and Enhancements

### 6.1 Background Execution (Priority: High)
Integrate `workmanager` for periodic background checks when the app is not in the foreground. This would use Android WorkManager and iOS BGTaskScheduler to run the same `TaskRunner.runDueActions()` logic in a background isolate.

### 6.2 Retry Policy (Priority: Medium)
Add configurable retry strategies for failed actions:
- Exponential backoff (1min, 5min, 30min, ...)
- Maximum retry count
- Dead-letter queue for permanently failed actions

### 6.3 Action Dependencies (Priority: Medium)
Support action chaining where Action B runs only after Action A succeeds:
```dart
Schedule.after('action-a', delay: Duration(minutes: 5))
```

### 6.4 Cron Expression Support (Priority: Low)
Support standard cron expressions for advanced scheduling:
```dart
Schedule.cron('0 9 * * 1-5') // Weekdays at 9 AM
```

### 6.5 Remote Configuration (Priority: Low)
Allow schedule definitions to be fetched from a remote server, enabling dynamic schedule updates without app releases.

### 6.6 Analytics Dashboard (Priority: Low)
A built-in Flutter widget that visualizes execution history, success rates, and failure trends as charts.

### 6.7 Platform Channels for Native Alarms (Priority: Medium)
Use platform channels to leverage Android `AlarmManager` and iOS `UNNotificationRequest` for exact-time scheduling that survives app closure.

---

## 7. Project Structure

The SDK is a standalone Flutter package under `packages/`, cleanly separated from the sample app. Any Flutter project can depend on it via a path or pub dependency.

```
action_scheduler/
├── packages/
│   └── action_scheduler_sdk/              # ← Standalone SDK package
│       ├── pubspec.yaml                   # SDK's own dependencies
│       ├── lib/
│       │   ├── action_scheduler_sdk.dart  # Public barrel export
│       │   └── src/
│       │       ├── action_scheduler.dart  # Main facade / API
│       │       ├── models/
│       │       │   ├── schedule.dart
│       │       │   ├── scheduled_action.dart
│       │       │   ├── execution_record.dart
│       │       │   └── notification_config.dart
│       │       ├── engine/
│       │       │   ├── schedule_evaluator.dart
│       │       │   └── task_runner.dart
│       │       ├── persistence/
│       │       │   ├── database_provider.dart
│       │       │   ├── action_repository.dart
│       │       │   └── execution_repository.dart
│       │       └── notifications/
│       │           └── notification_service.dart
│       └── test/
│           └── schedule_evaluator_test.dart
├── lib/                                   # ← Sample app
│   ├── main.dart
│   └── app/
│       ├── theme.dart
│       ├── sample_actions.dart
│       ├── screens/
│       │   ├── home_screen.dart
│       │   ├── action_detail_screen.dart
│       │   └── add_action_screen.dart
│       └── widgets/
│           ├── action_card.dart
│           └── execution_tile.dart
├── test/
│   └── widget_test.dart
├── pubspec.yaml                           # Sample app depends on SDK via path
├── DESIGN_DOCUMENT.md
└── README.md
```

### Integration

Any Flutter app can add the SDK as a dependency:

```yaml
# Via path (local development)
dependencies:
  action_scheduler_sdk:
    path: packages/action_scheduler_sdk

# Via pub.dev (once published)
dependencies:
  action_scheduler_sdk: ^1.0.0
```

---

## 8. Sample App

The included sample app demonstrates two pre-configured scheduled actions:

1. **Daily DigiGold Auto-Save**: Runs every day at 9:00 AM, simulating a ₹100 savings deposit with a 1-hour advance notification.

2. **Monthly Auto-Recharge**: Runs on the 1st of every month at 10:00 AM, simulating a ₹499 mobile recharge with a 24-hour advance notification.

The app also allows users to create custom actions through a form UI, view execution history with success/failure filtering, manually trigger actions for testing, and pause/resume actions.
