# Action Scheduler SDK — Design Document

## 1. Overview

The Action Scheduler SDK is a cross-platform Flutter plugin that enables mobile developers to schedule and execute recurring tasks locally on the device. The SDK handles **when** to run a task, while the app developer defines **what** the task does via a simple callback.

**Platform support**: Android (AlarmManager for background execution) and iOS (BGTaskScheduler for background execution). The Dart scheduling logic, persistence, and API are fully shared across both platforms.

**Sample app**: Included in the repository with two example scheduled actions:
1. **Daily DigiGold Auto-Save** — Runs every day at 9:00 AM with a 1-hour advance notification
2. **Monthly Auto-Recharge** — Runs on the 1st of every month at 10:00 AM with a 24-hour advance notification

---

## 2. Architecture

### 2.1 Layered Architecture

The SDK follows a layered design with a Facade pattern. App developers interact only with the `ActionScheduler` singleton. All internals are hidden.

```
┌───────────────────────────────────────────────────────────────┐
│                      App Developer Code                       │
│                                                               │
│   register()   onActionDue = handler   getExecutionLogs()     │
│       │                │                      │               │
├───────┼────────────────┼──────────────────────┼───────────────┤
│       ▼                ▼                      ▼               │
│  ┌────────────────────────────────────────────────────────┐   │
│  │              ActionScheduler (Facade)                   │   │
│  │  Singleton entry point — manages lifecycle, routing,    │   │
│  │  and coordination between all internal components       │   │
│  └────────┬──────────┬──────────────┬─────────────────────┘   │
│           │          │              │                          │
│  ┌────────▼───┐ ┌────▼────────┐ ┌──▼──────────────┐          │
│  │ Schedule   │ │ Task        │ │ Notification     │          │
│  │ Evaluator  │ │ Runner      │ │ Service          │          │
│  │            │ │             │ │                  │          │
│  │ Next run   │ │ Execute     │ │ Pre-action       │          │
│  │ time calc  │ │ due tasks   │ │ reminders via    │          │
│  │ Missed run │ │ Record      │ │ flutter_local_   │          │
│  │ detection  │ │ results     │ │ notifications    │          │
│  └────────────┘ └──────┬──────┘ └─────────────────┘          │
│                        │                                      │
│  ┌─────────────────────▼──────────────────────────────────┐   │
│  │               Persistence Layer (SQLite)                │   │
│  │                                                         │   │
│  │  ActionRepository          ExecutionRepository          │   │
│  │  (CRUD for actions)        (CRUD for execution logs)    │   │
│  │                                                         │   │
│  │              DatabaseProvider (schema, connection)       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │            Native Background Layer                      │   │
│  │                                                         │   │
│  │  Android: AlarmManager + BroadcastReceiver + Service    │   │
│  │  iOS:     BGTaskScheduler + BGProcessingTask            │   │
│  │                                                         │   │
│  │  Both start a headless FlutterEngine when the alarm     │   │
│  │  fires, executing the Dart callback without any UI.     │   │
│  └─────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────┘
```

### 2.2 Data Model

```
ScheduledAction                        ExecutionRecord
─────────────────                      ─────────────────
id          (PK)  ──── 1:N ────────▶  id           (PK)
name                                   actionId     (FK)
description                            scheduledTime
schedule: Schedule                     executionTime
isActive                               status (success/failed/missed)
createdAt                              durationMs
lastRunAt                              errorMessage
nextRunAt                              failureReason
notification: NotificationConfig
metadata: Map<String, String>

Schedule                               NotificationConfig
─────────────────                      ─────────────────
type (daily/weekly/monthly/interval)   title
hour, minute                           body
dayOfWeek (for weekly)                 leadTime (Duration, e.g. 30s)
dayOfMonth (for monthly)               enabled
interval (for custom)
```

---

## 3. Persistence, Scheduling, and Observability

### 3.1 Persistence

All data is stored in a local **SQLite database** via the `sqflite` package.

- **Two tables**: `scheduled_actions` (action definitions, schedules, state) and `execution_logs` (full audit trail of every execution attempt)
- **Indexed columns**: `actionId`, `scheduledTime`, and `status` on the execution logs table for fast queries
- **Survives app restarts and device reboots** — the database file persists on disk
- The `DatabaseProvider` auto-reopens the connection if it was closed, handling concurrent access between foreground and background isolates

### 3.2 Scheduling — Three Layers of Defense

The SDK uses a layered approach to ensure tasks run reliably:

| Layer | Mechanism | When it works |
|-------|-----------|---------------|
| **Primary** | Native platform alarms (Android `AlarmManager.setExactAndAllowWhileIdle` / iOS `BGTaskScheduler`) | App killed, phone idle, after reboot |
| **Secondary** | Dart `Timer.periodic` every 30 seconds | App in foreground — instant execution, no engine startup overhead |
| **Safety net** | Startup recovery on `ActionScheduler.start()` | Catches anything the other two layers missed |

**Background execution flow**: When a native alarm fires, the OS starts a `BackgroundExecutionService` (Android) or triggers a `BGProcessingTask` (iOS). This service launches a **headless FlutterEngine** (no UI), resolves the developer's Dart callback via `PluginUtilities`, initializes the SQLite database, runs all due actions, records results, and signals completion back to native.

**Startup recovery flow**: On every app launch, the SDK queries all active actions where `nextRunAt < now`. For each, it computes every missed run time, logs them as `ExecutionRecord(status: missed)`, executes the most recent one as a catch-up, and advances `nextRunAt` to the next future occurrence.

### 3.3 Observability

The SDK maintains a complete audit trail:

- **Every execution** (success, failure, or miss) is recorded as an `ExecutionRecord` with timestamp, duration, status, and error details
- **Query APIs**: `getExecutionLogs(actionId)`, `getAllExecutionLogs()`, `getFailedExecutions()`, `getExecutionStats(actionId)` — returns totals, success count, failure count, and average duration
- **Reactive streams**: `actionChanges` and `executionChanges` broadcast real-time updates for UI binding
- **Failure categorization**: `FailureReason` enum distinguishes between callback errors, app not running, device offline, and timeout
- **Log pruning**: `pruneExecutionLogs(retention: Duration(days: 30))` for cleanup

---

## 4. Trade-offs and Assumptions

### Trade-offs

| Decision | Trade-off | Rationale |
|----------|-----------|-----------|
| SQLite over SharedPreferences | More complex setup | Needed for queries, aggregations, and indexed lookups on execution history |
| AlarmManager over WorkManager | Requires `SCHEDULE_EXACT_ALARM` permission on Android 12+ | Provides exact-time execution; WorkManager has a 15-minute minimum interval |
| Headless FlutterEngine for background | ~2-3s startup overhead per background execution | Allows reusing 100% of the Dart SDK logic (DB, scheduling, recording) without duplicating it in native code |
| Single callback handler | Less flexible than per-action callbacks | Simpler API; `switch` on action ID is idiomatic and explicit |
| Sequential task execution | No parallel execution of multiple due actions | Avoids race conditions on the shared database; sufficient for typical mobile task volumes |
| iOS BGProcessingTask timing is approximate | Tasks may run late on iOS | This is an OS-level limitation — no third-party app gets exact background timing on iOS |
| Foreground timer kept as fallback | Slight resource usage when app is open | Provides instant execution without headless engine overhead; belt-and-suspenders with native alarms |

### Assumptions

1. **Tasks are idempotent** — Catch-up execution assumes running a missed action once (even if delayed) is safe
2. **Tasks are lightweight** — Executed on the main Dart isolate; CPU-intensive work should use `compute()` internally
3. **App launches regularly** — Extended inactivity is recovered on next launch, but only the most recent missed run is actually executed (others are logged as missed)
4. **Metadata is simple** — Key-value string pairs; complex data should be stored externally and referenced by ID

---

## 5. Future Scope

| Enhancement | Description |
|-------------|-------------|
| **Retry policy** | Configurable exponential backoff for failed actions with a maximum retry count and dead-letter queue |
| **Action dependencies** | Chaining where Action B runs only after Action A succeeds, with configurable delay |
| **Cron expressions** | Standard cron syntax for advanced scheduling (e.g., `0 9 * * 1-5` for weekdays at 9 AM) |
| **Remote configuration** | Fetch schedule definitions from a server for dynamic updates without app releases |
| **Analytics widget** | Built-in Flutter widget visualizing execution history, success rates, and failure trends |

---

## 6. Project Structure and Sample App

The SDK is a standalone Flutter plugin package under `packages/`, cleanly separated from the sample app. Any Flutter project can depend on it via a path or pub dependency.

```
action_scheduler/
├── packages/action_scheduler_sdk/     # Standalone SDK plugin
│   ├── lib/src/                       # Dart: models, engine, persistence, notifications
│   ├── android/src/                   # Kotlin: AlarmManager, BroadcastReceiver, headless engine
│   ├── ios/Classes/                   # Swift: BGTaskScheduler, headless engine
│   └── test/                          # Unit tests for ScheduleEvaluator
├── lib/                               # Sample app
│   ├── main.dart                      # Entry point with background callback registration
│   └── app/                           # Screens, widgets, theme, sample action definitions
├── DESIGN_DOCUMENT.md
└── README.md
```

The sample app demonstrates: registering actions with schedules, configuring pre-action notifications (including 30-second lead time), viewing execution history across all actions, filtering by failures, manually triggering actions, and pausing/resuming actions — all powered by the SDK's public API.
