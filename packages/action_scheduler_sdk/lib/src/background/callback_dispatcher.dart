import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../engine/task_runner.dart';
import '../persistence/action_repository.dart';
import '../persistence/database_provider.dart';
import '../persistence/execution_repository.dart';
import 'background_channel.dart';

/// Internal callback dispatcher that runs in a headless Flutter engine.
///
/// This is invoked by native code (Android AlarmReceiver / iOS BGTaskHandler)
/// when a scheduled alarm fires. It:
/// 1. Initializes a minimal Flutter binding (no UI)
/// 2. Opens the SQLite database
/// 3. Queries for due actions and executes them
/// 4. Signals completion back to native
///
/// The [actionHandler] is the app developer's top-level function that
/// defines what each action does.
@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();

  BackgroundChannel.setMethodCallHandler((call) async {
    if (call.method == 'executeBackgroundTask') {
      final callbackRawHandle = call.arguments['callbackHandle'] as int;
      final callbackHandle = CallbackHandle.fromRawHandle(callbackRawHandle);
      final handler = PluginUtilities.getCallbackFromHandle(callbackHandle);

      if (handler != null && handler is ActionHandler) {
        // Initialize persistence in this headless isolate
        final dbProvider = DatabaseProvider();
        final actionRepo = ActionRepository(dbProvider);
        final executionRepo = ExecutionRepository(dbProvider);
        final taskRunner = TaskRunner(actionRepo, executionRepo);

        taskRunner.registerHandler(handler);
        await taskRunner.runDueActions();
        await dbProvider.close();
      }

      // Signal native that we're done
      await BackgroundChannel.backgroundTaskComplete();
    }
  });
}
