import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:action_scheduler_sdk/action_scheduler_sdk.dart';
import '../theme.dart';

/// A list tile displaying a single execution record.
class ExecutionTile extends StatelessWidget {
  final ExecutionRecord record;
  final bool showActionId;

  const ExecutionTile({
    super.key,
    required this.record,
    this.showActionId = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          _buildStatusIcon(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showActionId)
                  Text(
                    record.actionId,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                Text(
                  _statusText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: _statusColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Scheduled: ${DateFormat('MMM d, h:mm a').format(record.scheduledTime)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
                if (record.executionTime != null)
                  Text(
                    'Ran: ${DateFormat('MMM d, h:mm a').format(record.executionTime!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                if (record.errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    record.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.failedColor,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildStatusChip(context),
              if (record.durationMs > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${record.durationMs}ms',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade500,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _statusIcon,
        color: _statusColor,
        size: 18,
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        record.status.name.toUpperCase(),
        style: TextStyle(
          color: _statusColor,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String get _statusText {
    switch (record.status) {
      case ExecutionStatus.success:
        return 'Completed successfully';
      case ExecutionStatus.failed:
        return 'Execution failed';
      case ExecutionStatus.missed:
        return 'Missed execution';
      case ExecutionStatus.skipped:
        return 'Skipped';
    }
  }

  Color get _statusColor {
    switch (record.status) {
      case ExecutionStatus.success:
        return AppTheme.successColor;
      case ExecutionStatus.failed:
        return AppTheme.failedColor;
      case ExecutionStatus.missed:
        return AppTheme.missedColor;
      case ExecutionStatus.skipped:
        return AppTheme.skippedColor;
    }
  }

  IconData get _statusIcon {
    switch (record.status) {
      case ExecutionStatus.success:
        return Icons.check_circle_outline;
      case ExecutionStatus.failed:
        return Icons.error_outline;
      case ExecutionStatus.missed:
        return Icons.warning_amber;
      case ExecutionStatus.skipped:
        return Icons.skip_next;
    }
  }
}
