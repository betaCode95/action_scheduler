/// Action Scheduler SDK
///
/// A cross-platform SDK for scheduling and running local tasks on mobile devices.
/// Supports background execution via Android AlarmManager and iOS BGTaskScheduler.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:action_scheduler_sdk/action_scheduler_sdk.dart';
///
/// @pragma('vm:entry-point')
/// void backgroundCallback() {
///   ActionScheduler.executeInBackground(myHandler);
/// }
///
/// Future<bool> myHandler(String actionId, Map<String, String>? metadata) async {
///   // Handle the action
///   return true;
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
