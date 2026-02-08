import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:action_scheduler_sdk/action_scheduler_sdk.dart';
import '../theme.dart';
import '../widgets/execution_tile.dart';

/// Screen showing detailed information about a scheduled action,
/// including its configuration, statistics, and execution history.
class ActionDetailScreen extends StatefulWidget {
  final String actionId;

  const ActionDetailScreen({super.key, required this.actionId});

  @override
  State<ActionDetailScreen> createState() => _ActionDetailScreenState();
}

class _ActionDetailScreenState extends State<ActionDetailScreen> {
  ScheduledAction? _action;
  List<ExecutionRecord> _logs = [];
  Map<String, int> _stats = {};
  bool _loading = true;
  bool _triggering = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final action = await ActionScheduler.instance.getAction(widget.actionId);
    final logs =
        await ActionScheduler.instance.getExecutionLogs(widget.actionId);
    final stats =
        await ActionScheduler.instance.getExecutionStats(widget.actionId);

    if (mounted) {
      setState(() {
        _action = action;
        _logs = logs;
        _stats = stats;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_action?.name ?? 'Action Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _action != null ? _confirmDelete : null,
            tooltip: 'Delete Action',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _action == null
              ? const Center(child: Text('Action not found'))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 100),
                    children: [
                      _buildInfoSection(theme),
                      _buildStatsSection(theme),
                      _buildActionsSection(theme),
                      _buildHistorySection(theme),
                    ],
                  ),
                ),
    );
  }

  Widget _buildInfoSection(ThemeData theme) {
    final action = _action!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Configuration',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const Divider(height: 24),
              _infoRow('ID', action.id),
              _infoRow('Schedule', action.schedule.description),
              _infoRow(
                'Status',
                action.isActive ? 'Active' : 'Paused',
                valueColor:
                    action.isActive ? AppTheme.activeColor : AppTheme.pausedColor,
              ),
              _infoRow(
                'Created',
                DateFormat('MMM d, yyyy h:mm a').format(action.createdAt),
              ),
              if (action.lastRunAt != null)
                _infoRow(
                  'Last Run',
                  DateFormat('MMM d, yyyy h:mm a').format(action.lastRunAt!),
                ),
              if (action.nextRunAt != null)
                _infoRow(
                  'Next Run',
                  DateFormat('MMM d, yyyy h:mm a').format(action.nextRunAt!),
                ),
              if (action.notification != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.notifications_active,
                        size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      'Notification: ${action.notification!.leadTime.inMinutes} min before',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.amber.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.analytics_outlined,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Execution Statistics',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      'Total',
                      '${_stats['total'] ?? 0}',
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statCard(
                      'Success',
                      '${_stats['successes'] ?? 0}',
                      AppTheme.successColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statCard(
                      'Failed',
                      '${_stats['failures'] ?? 0}',
                      AppTheme.failedColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statCard(
                      'Avg Time',
                      '${_stats['avgDurationMs'] ?? 0}ms',
                      Colors.purple,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionsSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _triggering ? null : _triggerNow,
              icon: _triggering
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_triggering ? 'Running...' : 'Run Now'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _toggleActive(),
              icon: Icon(
                _action!.isActive ? Icons.pause : Icons.play_arrow,
              ),
              label: Text(_action!.isActive ? 'Pause' : 'Resume'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(Icons.history, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Execution History',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_logs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No executions yet',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          )
        else
          ..._logs.map((log) => ExecutionTile(record: log)),
      ],
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.black87,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerNow() async {
    setState(() => _triggering = true);
    try {
      final result =
          await ActionScheduler.instance.triggerNow(widget.actionId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.isSuccess
                ? 'Action executed successfully (${result.durationMs}ms)'
                : 'Action failed: ${result.errorMessage}'),
            backgroundColor:
                result.isSuccess ? AppTheme.successColor : AppTheme.failedColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.failedColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _triggering = false);
      await _loadData();
    }
  }

  Future<void> _toggleActive() async {
    if (_action!.isActive) {
      await ActionScheduler.instance.pause(widget.actionId);
    } else {
      await ActionScheduler.instance.resume(widget.actionId);
    }
    await _loadData();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Action'),
        content: Text(
          'Are you sure you want to delete "${_action!.name}"? '
          'This will also remove all execution history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.failedColor,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ActionScheduler.instance.unregister(widget.actionId);
      if (mounted) Navigator.of(context).pop();
    }
  }
}
