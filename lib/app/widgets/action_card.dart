import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:action_scheduler_sdk/action_scheduler_sdk.dart';
import '../theme.dart';

/// A card widget displaying a scheduled action's summary.
class ActionCard extends StatelessWidget {
  final ScheduledAction action;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onToggle;

  const ActionCard({
    super.key,
    required this.action,
    this.onTap,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildIcon(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (action.description != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            action.description!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: action.isActive,
                    onChanged: onToggle,
                    activeTrackColor: AppTheme.activeColor,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Schedule description
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    action.schedule.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Next run info
              Row(
                children: [
                  Icon(
                    Icons.upcoming_outlined,
                    size: 16,
                    color: action.isActive
                        ? AppTheme.activeColor
                        : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    action.isActive
                        ? 'Next: ${_formatNextRun(action.nextRunAt)}'
                        : 'Paused',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: action.isActive
                          ? AppTheme.activeColor
                          : Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  if (action.notification != null)
                    Icon(
                      Icons.notifications_active_outlined,
                      size: 16,
                      color: Colors.grey.shade500,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    IconData icon;
    Color color;

    switch (action.schedule.type) {
      case ScheduleType.daily:
        icon = Icons.today;
        color = const Color(0xFF6C5CE7);
        break;
      case ScheduleType.weekly:
        icon = Icons.view_week;
        color = const Color(0xFF0984E3);
        break;
      case ScheduleType.monthly:
        icon = Icons.calendar_month;
        color = const Color(0xFFE17055);
        break;
      case ScheduleType.interval:
        icon = Icons.timer;
        color = const Color(0xFF00B894);
        break;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }

  String _formatNextRun(DateTime? nextRun) {
    if (nextRun == null) return 'Not scheduled';
    final now = DateTime.now();
    final diff = nextRun.difference(now);

    if (diff.inDays > 1) {
      return DateFormat('MMM d, h:mm a').format(nextRun);
    } else if (diff.inHours > 1) {
      return 'In ${diff.inHours}h ${diff.inMinutes % 60}m';
    } else if (diff.inMinutes > 1) {
      return 'In ${diff.inMinutes}m';
    } else if (diff.isNegative) {
      return 'Overdue';
    } else {
      return 'Very soon';
    }
  }
}
