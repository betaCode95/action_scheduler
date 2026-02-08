/// Action Scheduler SDK
///
/// A cross-platform SDK for scheduling and running local tasks on mobile devices.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:action_scheduler_sdk/action_scheduler_sdk.dart';
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await ActionScheduler.initialize();
///
///   ActionScheduler.instance.onActionDue = (actionId, metadata) async {
///     // Handle the action
///     return true;
///   };
///
///   await ActionScheduler.instance.register(
///     ScheduledAction(
///       id: 'my-action',
///       name: 'My Daily Action',
///       schedule: Schedule.daily(hour: 9, minute: 0),
///     ),
///   );
///
///   ActionScheduler.instance.start();
///   runApp(MyApp());
/// }
/// ```
library;

// Main facade
export 'src/action_scheduler.dart';

// Models
export 'src/models/execution_record.dart';
export 'src/models/notification_config.dart';
export 'src/models/schedule.dart';
export 'src/models/scheduled_action.dart';

// Engine (for advanced usage)
export 'src/engine/schedule_evaluator.dart';
export 'src/engine/task_runner.dart' show ActionHandler;
