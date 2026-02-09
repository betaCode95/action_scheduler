import 'package:action_scheduler_sdk/action_scheduler_sdk.dart';

/// Pre-configured sample actions that demonstrate SDK capabilities.
///
/// These are the two required example scheduled actions:
/// 1. Daily DigiGold Auto-Save (every day at 9 AM)
/// 2. Monthly Auto-Recharge (1st of every month at 10 AM)

@pragma('vm:entry-point')
class SampleActions {
  /// Daily DigiGold Auto-Save
  ///
  /// Demonstrates a daily schedule with notification.
  static ScheduledAction dailyDigiGoldSave() {
    return ScheduledAction(
      id: 'daily-digigold-save',
      name: 'Daily DigiGold Save',
      description: 'Auto-save \u20B9100 to DigiGold every day',
      schedule: const Schedule.daily(hour: 9, minute: 0),
      notification: const NotificationConfig(
        title: 'DigiGold Auto-Save',
        body: 'Your daily \u20B9100 DigiGold save will run at 9:00 AM',
        leadTime: Duration(hours: 1),
      ),
      metadata: {'amount': '100', 'currency': 'INR'},
    );
  }

  /// Monthly Auto-Recharge
  ///
  /// Demonstrates a monthly schedule with 24-hour advance notification.
  static ScheduledAction monthlyAutoRecharge() {
    return ScheduledAction(
      id: 'monthly-auto-recharge',
      name: 'Monthly Auto-Recharge',
      description: 'Auto-recharge \u20B9499 on the 1st of every month',
      schedule: const Schedule.monthly(day: 1, hour: 10, minute: 0),
      notification: const NotificationConfig(
        title: 'Auto-Recharge Reminder',
        body:
            'Your monthly \u20B9499 recharge will process tomorrow at 10:00 AM',
        leadTime: Duration(hours: 24),
      ),
      metadata: {'amount': '499', 'plan': 'monthly'},
    );
  }

  /// Returns all sample actions.
  static List<ScheduledAction> all() {
    return [
      dailyDigiGoldSave(),
      monthlyAutoRecharge(),
    ];
  }

  /// The action handler that processes scheduled actions.
  ///
  /// This is what the app developer provides to define what happens
  /// when each action is due. The SDK calls this function with the
  /// action ID and metadata when an action's scheduled time arrives.
  @pragma('vm:entry-point')
  static Future<bool> handler(
      String actionId, Map<String, String>? metadata) async {
    switch (actionId) {
      case 'daily-digigold-save':
        return _handleDiGiGoldSave(metadata);

      case 'monthly-auto-recharge':
        return _handleAutoRecharge(metadata);

      default:
        // For user-created actions, simulate a generic task
        return _handleGenericAction(actionId, metadata);
    }
  }

  /// Simulates saving to DigiGold.
  @pragma('vm:entry-point')
  static Future<bool> _handleDiGiGoldSave(Map<String, String>? metadata) async {
    final amount = metadata?['amount'] ?? '100';
    // Simulate an API call to save to DigiGold
    await Future.delayed(const Duration(milliseconds: 800));
    // ignore: avoid_print
    print('[DigiGold] Saved \u20B9$amount to DigiGold successfully');
    return true;
  }

  /// Simulates processing an auto-recharge.
  @pragma('vm:entry-point')
  static Future<bool> _handleAutoRecharge(Map<String, String>? metadata) async {
    final amount = metadata?['amount'] ?? '499';
    // Simulate an API call to process recharge
    await Future.delayed(const Duration(milliseconds: 1200));
    // ignore: avoid_print
    print('[AutoRecharge] Recharged \u20B9$amount successfully');
    return true;
  }

  /// Handles user-created generic actions.
  @pragma('vm:entry-point')
  static Future<bool> _handleGenericAction(
      String actionId, Map<String, String>? metadata) async {
    await Future.delayed(const Duration(milliseconds: 500));
    // ignore: avoid_print
    print('[Generic] Executed action: $actionId');
    return true;
  }
}
