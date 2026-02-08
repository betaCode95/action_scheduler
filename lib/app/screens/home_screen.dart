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
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ScheduledAction> _actions = [];
  List<ExecutionRecord> _recentExecutions = [];
  List<ExecutionRecord> _failedExecutions = [];
  bool _loading = true;

  StreamSubscription? _actionSub;
  StreamSubscription? _executionSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();

    // Listen for real-time changes
    _actionSub = ActionScheduler.instance.actionChanges.listen((_) {
      _loadData();
    });
    _executionSub = ActionScheduler.instance.executionChanges.listen((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
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
