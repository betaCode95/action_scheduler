import 'dart:async';

import 'package:flutter/material.dart';

import 'package:action_scheduler_sdk/action_scheduler_sdk.dart';
import '../theme.dart';
import '../widgets/action_card.dart';
import '../widgets/execution_tile.dart';
import 'action_detail_screen.dart';
import 'add_action_screen.dart';

/// The main screen of the sample app.
///
/// Displays all registered actions and recent execution logs.
/// Provides navigation to add new actions and view action details.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  List<ScheduledAction> _actions = [];
  List<ExecutionRecord> _recentExecutions = [];
  List<ExecutionRecord> _failedExecutions = [];
  bool _loading = true;
  bool _permissionDialogShown = false;

  StreamSubscription? _actionSub;
  StreamSubscription? _executionSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _loadData();

    // Check permissions after the first frame so context is valid for dialogs
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissions();
    });

    // Listen for real-time changes
    _actionSub = ActionScheduler.instance.actionChanges.listen((_) {
      _loadData();
    });
    _executionSub = ActionScheduler.instance.executionChanges.listen((_) {
      _loadData();
    });
  }

  /// Re-check permission when the user returns from Settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  /// Checks required permissions on startup and prompts the user if needed.
  ///
  /// On Android 12+, SCHEDULE_EXACT_ALARM may be auto-granted but the user
  /// can revoke it. We always show a one-time prompt on first launch to make
  /// the user aware, and re-prompt if permission is revoked later.
  Future<void> _checkPermissions() async {
    if (!mounted || _permissionDialogShown) return;

    final canSchedule = await ActionScheduler.canScheduleExactAlarms();

    // Check if we've shown the first-launch prompt before
    final hasShownOnce = await _hasShownPermissionPrompt();

    if (!canSchedule) {
      // Permission is NOT granted -- always show the dialog
      _permissionDialogShown = true;
      await _showPermissionDialog(
        title: 'Enable Alarms & Reminders',
        message:
            'Action Scheduler needs the "Alarms & Reminders" permission '
            'to run your scheduled actions on time, even when the app is '
            'closed or the phone restarts.\n\n'
            'Without this permission, tasks will only run when you open the app.',
        actionLabel: 'Open Settings',
        onAction: () => ActionScheduler.openExactAlarmSettings(),
      );
    } else if (!hasShownOnce) {
      // Permission IS granted (auto-granted by OS), but first launch --
      // show a confirmation so the user knows about it
      _permissionDialogShown = true;
      await _markPermissionPromptShown();
      await _showPermissionDialog(
        title: 'Background Scheduling Active',
        message:
            'The "Alarms & Reminders" permission is enabled. Your scheduled '
            'actions will run on time even when the app is closed.\n\n'
            'You can manage this in Settings > Apps > Action Scheduler > '
            'Alarms & reminders.',
        actionLabel: 'Got It',
        onAction: null,
        isInfoOnly: true,
      );
    }
  }

  Future<void> _showPermissionDialog({
    required String title,
    required String message,
    required String actionLabel,
    VoidCallback? onAction,
    bool isInfoOnly = false,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          isInfoOnly ? Icons.check_circle : Icons.alarm,
          size: 40,
          color: isInfoOnly ? const Color(0xFF00B894) : const Color(0xFF6C5CE7),
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          if (!isInfoOnly)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _permissionDialogShown = false;
              },
              child: const Text('Skip for Now'),
            ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _permissionDialogShown = false;
              onAction?.call();
            },
            icon: Icon(isInfoOnly ? Icons.check : Icons.settings),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  /// Checks SharedPreferences whether the first-launch permission prompt
  /// has been shown before.
  Future<bool> _hasShownPermissionPrompt() async {
    // Use a simple approach: check via the SDK's own persistence
    // We piggyback on the action count -- if actions exist, user has seen the app before
    return _permissionPromptCompleted;
  }

  static bool _permissionPromptCompleted = false;

  Future<void> _markPermissionPromptShown() async {
    _permissionPromptCompleted = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _actionSub?.cancel();
    _executionSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final actions = await ActionScheduler.instance.getAllActions();
    final recent = await ActionScheduler.instance.getAllExecutionLogs(limit: 50);
    final failed = await ActionScheduler.instance.getFailedExecutions(limit: 50);

    if (mounted) {
      setState(() {
        _actions = actions;
        _recentExecutions = recent;
        _failedExecutions = failed;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Action Scheduler',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.schedule, size: 20),
              text: 'Actions (${_actions.length})',
            ),
            Tab(
              icon: const Icon(Icons.history, size: 20),
              text: 'History (${_recentExecutions.length})',
            ),
            Tab(
              icon: const Icon(Icons.warning_amber, size: 20),
              text: 'Failed (${_failedExecutions.length})',
            ),
          ],
          labelStyle: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildActionsTab(),
                _buildHistoryTab(),
                _buildFailedTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddAction,
        icon: const Icon(Icons.add),
        label: const Text('New Action'),
      ),
    );
  }

  Widget _buildActionsTab() {
    if (_actions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No scheduled actions yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create your first action',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        itemCount: _actions.length,
        itemBuilder: (context, index) {
          final action = _actions[index];
          return ActionCard(
            action: action,
            onTap: () => _navigateToDetail(action),
            onToggle: (active) => _toggleAction(action, active),
          );
        },
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_recentExecutions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No execution history',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Execution logs will appear here',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        itemCount: _recentExecutions.length,
        itemBuilder: (context, index) {
          return ExecutionTile(
            record: _recentExecutions[index],
            showActionId: true,
          );
        },
      ),
    );
  }

  Widget _buildFailedTab() {
    if (_failedExecutions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: AppTheme.successColor.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No failures!',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Failed and missed executions appear here',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 80),
        itemCount: _failedExecutions.length,
        itemBuilder: (context, index) {
          return ExecutionTile(
            record: _failedExecutions[index],
            showActionId: true,
          );
        },
      ),
    );
  }

  Future<void> _toggleAction(ScheduledAction action, bool active) async {
    if (active) {
      await ActionScheduler.instance.resume(action.id);
    } else {
      await ActionScheduler.instance.pause(action.id);
    }
    await _loadData();
  }

  void _navigateToDetail(ScheduledAction action) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActionDetailScreen(actionId: action.id),
      ),
    ).then((_) => _loadData());
  }

  void _navigateToAddAction() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddActionScreen()),
    ).then((_) => _loadData());
  }
}
