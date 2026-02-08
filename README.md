# Action Scheduler SDK

A cross-platform Flutter SDK for scheduling and running tasks locally on mobile devices with flexible recurrence rules.

## Features

- **Flexible Scheduling**: Daily, weekly, monthly, and custom interval recurrence patterns
- **Persistent Storage**: Actions and execution history stored in SQLite, surviving app restarts
- **Startup Recovery**: Detects missed executions and catches up automatically
- **Execution Logging**: Complete audit trail of all task runs with status, duration, and error details
- **Pre-Action Notifications**: Configurable reminders before tasks execute (e.g., 1 hour, 24 hours before)
- **Simple API**: Single `ActionScheduler` class with intuitive methods
- **Observable**: Streams for real-time UI updates on action and execution changes

## Quick Start

```dart
import 'package:action_scheduler_sdk/action_scheduler_sdk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize the SDK
  await ActionScheduler.initialize();

  // 2. Register your action handler
  ActionScheduler.instance.onActionDue = (actionId, metadata) async {
    switch (actionId) {
      case 'daily-save':
        await performDailySave();
        return true; // success
      case 'monthly-recharge':
        await performRecharge();
        return true;
      default:
        return false; // unknown action
    }
  };

  // 3. Register a scheduled action
  await ActionScheduler.instance.register(
    ScheduledAction(
      id: 'daily-save',
      name: 'Daily DigiGold Save',
      description: 'Auto-save ₹100 to DigiGold every day',
      schedule: Schedule.daily(hour: 9, minute: 0),
      notification: NotificationConfig(
        title: 'DigiGold Auto-Save',
        body: 'Your daily save will run at 9:00 AM',
        leadTime: Duration(hours: 1),
      ),
    ),
  );

  // 4. Start the scheduler (performs recovery + begins checking)
  await ActionScheduler.instance.start();

  runApp(MyApp());
}
```

## SDK API Reference

### Initialization

| Method | Description |
|--------|-------------|
| `ActionScheduler.initialize()` | Initialize the SDK (call once in `main()`) |
| `ActionScheduler.instance` | Access the singleton instance |

### Action Management

| Method | Description |
|--------|-------------|
| `register(action)` | Register a new scheduled action |
| `update(action)` | Update an existing action's configuration |
| `unregister(actionId)` | Remove an action and its history |
| `pause(actionId)` | Temporarily disable an action |
| `resume(actionId)` | Re-enable a paused action |
| `triggerNow(actionId)` | Manually execute an action immediately |

### Querying

| Method | Description |
|--------|-------------|
| `getAllActions()` | Get all registered actions |
| `getActiveActions()` | Get only active actions |
| `getAction(actionId)` | Get a single action by ID |
| `getExecutionLogs(actionId)` | Get execution history for an action |
| `getAllExecutionLogs()` | Get all execution logs |
| `getFailedExecutions()` | Get only failed/missed executions |
| `getExecutionStats(actionId)` | Get aggregated stats (total, success, fail, avg duration) |

### Lifecycle

| Method | Description |
|--------|-------------|
| `start()` | Begin scheduling (recovery + periodic checks) |
| `stop()` | Stop the scheduler |
| `dispose()` | Release all resources |
| `pruneExecutionLogs()` | Clean up old logs |

### Schedule Types

```dart
Schedule.daily(hour: 9, minute: 0)              // Every day at 9:00 AM
Schedule.weekly(day: 1, hour: 9, minute: 0)     // Every Monday at 9:00 AM
Schedule.monthly(day: 1, hour: 10, minute: 0)   // 1st of every month at 10:00 AM
Schedule.every(Duration(hours: 6))              // Every 6 hours
```

## Sample App

The included sample app demonstrates:

- **Daily DigiGold Auto-Save**: Runs daily at 9 AM with 1-hour advance notification
- **Monthly Auto-Recharge**: Runs on the 1st of every month with 24-hour advance notification
- Creating custom actions through a form UI
- Viewing execution history with success/failure filtering
- Manually triggering actions for testing
- Pausing and resuming actions

### Running the Sample App

```bash
flutter pub get
flutter run
```

## Architecture

See [DESIGN_DOCUMENT.md](DESIGN_DOCUMENT.md) for the full architecture and design rationale.

## Project Structure

```
action_scheduler/
├── packages/
│   └── action_scheduler_sdk/      # Standalone SDK package
│       ├── pubspec.yaml           # SDK's own dependencies
│       ├── lib/
│       │   ├── action_scheduler_sdk.dart  # Public barrel export
│       │   └── src/               # SDK internals
│       │       ├── models/        # Data models
│       │       ├── engine/        # Scheduling & execution engine
│       │       ├── persistence/   # SQLite storage layer
│       │       └── notifications/ # Local notification management
│       └── test/                  # SDK-level tests
├── lib/                           # Sample app
│   ├── main.dart
│   └── app/
│       ├── screens/               # App screens
│       ├── widgets/               # Reusable UI components
│       └── sample_actions.dart    # Example action definitions
└── pubspec.yaml                   # Depends on SDK via path
```

### Using the SDK in another project

```yaml
# Add to your pubspec.yaml
dependencies:
  action_scheduler_sdk:
    path: path/to/packages/action_scheduler_sdk
```
