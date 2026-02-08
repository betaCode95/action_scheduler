import 'package:flutter/material.dart';

import 'app/sample_actions.dart';
import 'app/screens/home_screen.dart';
import 'app/theme.dart';
import 'package:action_scheduler_sdk/action_scheduler_sdk.dart';

/// Entry point for the Action Scheduler sample app.
///
/// Demonstrates SDK integration with two example scheduled actions:
/// 1. Daily DigiGold Auto-Save (every day at 9 AM)
/// 2. Monthly Auto-Recharge (1st of every month at 10 AM)
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Step 1: Initialize the SDK
  await ActionScheduler.initialize();

  // Step 2: Register the action handler
  // This is where the app developer defines what each action does.
  ActionScheduler.instance.onActionDue = SampleActions.handler;

  // Step 3: Register sample actions (only if not already registered)
  await _registerSampleActions();

  // Step 4: Start the scheduler
  // This performs startup recovery (catches up missed actions)
  // and begins periodic checking for due actions.
  final recovered = await ActionScheduler.instance.start();
  if (recovered > 0) {
    debugPrint('[ActionScheduler] Recovered $recovered missed actions on startup');
  }

  runApp(const ActionSchedulerApp());
}

/// Registers the sample actions if they don't already exist.
Future<void> _registerSampleActions() async {
  for (final sample in SampleActions.all()) {
    final existing = await ActionScheduler.instance.getAction(sample.id);
    if (existing == null) {
      await ActionScheduler.instance.register(sample);
      debugPrint('[ActionScheduler] Registered sample action: ${sample.name}');
    }
  }
}

/// The sample app demonstrating the Action Scheduler SDK.
class ActionSchedulerApp extends StatelessWidget {
  const ActionSchedulerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Action Scheduler',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}
