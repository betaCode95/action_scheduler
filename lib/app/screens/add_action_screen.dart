import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:action_scheduler_sdk/action_scheduler_sdk.dart';

/// Screen for creating a new scheduled action.
///
/// Allows the user to configure the action's name, schedule type,
/// timing, and optional notification.
class AddActionScreen extends StatefulWidget {
  const AddActionScreen({super.key});

  @override
  State<AddActionScreen> createState() => _AddActionScreenState();
}

class _AddActionScreenState extends State<AddActionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _notifTitleController = TextEditingController();
  final _notifBodyController = TextEditingController();

  ScheduleType _scheduleType = ScheduleType.daily;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  int _dayOfWeek = 1; // Monday
  int _dayOfMonth = 1;
  bool _enableNotification = false;
  int _leadTimeSeconds = 3600; // default: 1 hour
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _notifTitleController.dispose();
    _notifBodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Action'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // --- Basic Info ---
            Text(
              'Basic Information',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Action Name',
                hintText: 'e.g., Daily DigiGold Save',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'e.g., Auto-save to DigiGold account',
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 24),

            // --- Schedule ---
            Text(
              'Schedule',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ScheduleType>(
              segments: const [
                ButtonSegment(
                  value: ScheduleType.daily,
                  label: Text('Daily'),
                  icon: Icon(Icons.today, size: 18),
                ),
                ButtonSegment(
                  value: ScheduleType.weekly,
                  label: Text('Weekly'),
                  icon: Icon(Icons.view_week, size: 18),
                ),
                ButtonSegment(
                  value: ScheduleType.monthly,
                  label: Text('Monthly'),
                  icon: Icon(Icons.calendar_month, size: 18),
                ),
              ],
              selected: {_scheduleType},
              onSelectionChanged: (set) {
                setState(() => _scheduleType = set.first);
              },
            ),
            const SizedBox(height: 16),

            // Time picker
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: const Text('Time'),
              subtitle: Text(_time.format(context)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickTime,
            ),

            // Day of week picker (for weekly)
            if (_scheduleType == ScheduleType.weekly) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _dayOfWeek,
                decoration: const InputDecoration(
                  labelText: 'Day of Week',
                  prefixIcon: Icon(Icons.calendar_view_week),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Monday')),
                  DropdownMenuItem(value: 2, child: Text('Tuesday')),
                  DropdownMenuItem(value: 3, child: Text('Wednesday')),
                  DropdownMenuItem(value: 4, child: Text('Thursday')),
                  DropdownMenuItem(value: 5, child: Text('Friday')),
                  DropdownMenuItem(value: 6, child: Text('Saturday')),
                  DropdownMenuItem(value: 7, child: Text('Sunday')),
                ],
                onChanged: (v) => setState(() => _dayOfWeek = v!),
              ),
            ],

            // Day of month picker (for monthly)
            if (_scheduleType == ScheduleType.monthly) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _dayOfMonth,
                decoration: const InputDecoration(
                  labelText: 'Day of Month',
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                items: List.generate(
                  31,
                  (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('${i + 1}'),
                  ),
                ),
                onChanged: (v) => setState(() => _dayOfMonth = v!),
              ),
            ],

            const SizedBox(height: 24),

            // --- Notification ---
            Text(
              'Notification',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable pre-action notification'),
              subtitle: const Text('Get reminded before the action runs'),
              value: _enableNotification,
              onChanged: (v) => setState(() {
                _enableNotification = v;
                if (v && _notifTitleController.text.isEmpty) {
                  _notifTitleController.text = _nameController.text;
                  _notifBodyController.text =
                      'Your scheduled action will run soon';
                }
              }),
            ),

            if (_enableNotification) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _notifTitleController,
                decoration: const InputDecoration(
                  labelText: 'Notification Title',
                ),
                validator: (v) => _enableNotification &&
                        (v == null || v.trim().isEmpty)
                    ? 'Title is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notifBodyController,
                decoration: const InputDecoration(
                  labelText: 'Notification Body',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _leadTimeSeconds,
                decoration: const InputDecoration(
                  labelText: 'Notify Before',
                  prefixIcon: Icon(Icons.notifications_active),
                ),
                items: const [
                  DropdownMenuItem(value: 30, child: Text('30 seconds before')),
                  DropdownMenuItem(value: 900, child: Text('15 minutes before')),
                  DropdownMenuItem(value: 1800, child: Text('30 minutes before')),
                  DropdownMenuItem(value: 3600, child: Text('1 hour before')),
                  DropdownMenuItem(value: 7200, child: Text('2 hours before')),
                  DropdownMenuItem(value: 86400, child: Text('24 hours before')),
                ],
                onChanged: (v) => setState(() => _leadTimeSeconds = v!),
              ),
            ],

            const SizedBox(height: 32),

            // --- Preview ---
            _buildPreview(theme),

            const SizedBox(height: 24),

            // --- Save button ---
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Saving...' : 'Create Action'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final schedule = _buildSchedule();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule, size: 16),
              const SizedBox(width: 6),
              Text(schedule.description),
            ],
          ),
          if (_enableNotification) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.notifications, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Notification ${_formatLeadTime(_leadTimeSeconds)} before',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Schedule _buildSchedule() {
    switch (_scheduleType) {
      case ScheduleType.daily:
        return Schedule.daily(hour: _time.hour, minute: _time.minute);
      case ScheduleType.weekly:
        return Schedule.weekly(
            day: _dayOfWeek, hour: _time.hour, minute: _time.minute);
      case ScheduleType.monthly:
        return Schedule.monthly(
            day: _dayOfMonth, hour: _time.hour, minute: _time.minute);
      case ScheduleType.interval:
        return Schedule.daily(hour: _time.hour, minute: _time.minute);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  String _formatLeadTime(int seconds) {
    if (seconds < 60) return '$seconds seconds';
    if (seconds < 3600) return '${seconds ~/ 60} minutes';
    if (seconds < 86400) return '${seconds ~/ 3600} hour${seconds >= 7200 ? 's' : ''}';
    return '${seconds ~/ 86400} day${seconds >= 172800 ? 's' : ''}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final schedule = _buildSchedule();

      NotificationConfig? notifConfig;
      if (_enableNotification) {
        notifConfig = NotificationConfig(
          title: _notifTitleController.text.trim(),
          body: _notifBodyController.text.trim(),
          leadTime: Duration(seconds: _leadTimeSeconds),
        );
      }

      final action = ScheduledAction(
        id: const Uuid().v4(),
        name: _nameController.text.trim(),
        description: _descController.text.trim().isNotEmpty
            ? _descController.text.trim()
            : null,
        schedule: schedule,
        notification: notifConfig,
      );

      await ActionScheduler.instance.register(action);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Action created successfully!'),
            backgroundColor: Color(0xFF00B894),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
