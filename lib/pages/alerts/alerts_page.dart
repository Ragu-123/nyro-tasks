import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/services/notification_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/widgets/google_checkbox.dart';
import 'package:tasks/widgets/top_banner_notification.dart';

class AlertsPage extends StatefulWidget {
  final VoidCallback onDataChanged;
  final VoidCallback onOpenAddReminder;

  const AlertsPage({
    Key? key,
    required this.onDataChanged,
    required this.onOpenAddReminder,
  }) : super(key: key);

  @override
  _AlertsPageState createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  List<Map<String, dynamic>> _reminders = [];
  bool _isLoading = true;
  bool _isCompletedExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);
    final reminders = await DatabaseService.instance.getCustomReminders();
    if (mounted) {
      setState(() {
        _reminders = reminders;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteReminder(int id) async {
    await DatabaseService.instance.deleteCustomReminder(id);
    await NotificationService.instance.cancelNotification(id);
    await _loadAlerts();
    widget.onDataChanged();
    if (mounted) {
      TopBanner.show(
        context,
        title: 'Alarm Deleted',
        message: 'Scheduled study alert removed.',
        icon: Icons.delete_outline_rounded,
        color: googleRed,
      );
    }
  }

  Future<void> _toggleReminder(int id, bool completed) async {
    await DatabaseService.instance.toggleReminderStatus(id, completed);
    await _loadAlerts();
    widget.onDataChanged();
    if (mounted) {
      TopBanner.show(
        context,
        title: completed ? 'Alarm Completed' : 'Alarm Active',
        message: completed ? 'Moved to completed schedule' : 'Restored to active reminders',
        icon: completed ? Icons.task_alt_rounded : Icons.alarm_on_rounded,
        color: completed ? googleGreen : googleBlue,
      );
    }
  }

  Future<void> _openAlarmEditor(Map<String, dynamic> reminder) async {
    final int id = reminder['id'] as int;
    final String initialText = reminder['text'] ?? 'Study Alarm';
    final String remindAtStr = reminder['remind_at'] ?? DateTime.now().toIso8601String();
    final DateTime initialDate = DateTime.tryParse(remindAtStr) ?? DateTime.now();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AlarmEditorSheet(
        id: id,
        initialText: initialText,
        initialDateTime: initialDate,
        onSave: (newText, newDateTime) async {
          await DatabaseService.instance.updateCustomReminder(
            id: id,
            text: newText,
            remindAt: newDateTime,
          );
          await NotificationService.instance.scheduleReminder(
            id: id,
            title: 'Study Reminder',
            body: newText,
            scheduledDate: newDateTime,
          );
          await _loadAlerts();
          widget.onDataChanged();
          if (mounted) {
            TopBanner.show(
              context,
              title: 'Alarm Saved',
              message: '$newText • ${DateFormat('d MMM, hh:mm a').format(newDateTime)}',
              icon: Icons.alarm_on_rounded,
              color: googleGreen,
            );
          }
        },
        onDelete: () => _deleteReminder(id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _reminders.where((r) => (r['status'] as String?)?.toUpperCase() != 'COMPLETED').toList();
    final completed = _reminders.where((r) => (r['status'] as String?)?.toUpperCase() == 'COMPLETED').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: googleTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Alerts & Alarms',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: googleTextPrimary,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_alarm_rounded, color: googleBlue),
            tooltip: 'Add Alarm',
            onPressed: widget.onOpenAddReminder,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: googleBlue))
          : _reminders.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                  children: [
                    // Active / Pending Alarms
                    if (pending.isNotEmpty) ...[
                      ...pending.map((r) => _buildAlarmCard(r, isCompleted: false)),
                    ] else if (completed.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                        child: Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: googleGreen.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.task_alt_rounded, color: googleGreen, size: 28),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'All Alarms Completed!',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: googleTextPrimary),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'You have completed all active study alarms.',
                                style: TextStyle(fontSize: 12, color: googleTextSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // Completed Section Accordion (like Today page)
                    if (completed.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => setState(() => _isCompletedExpanded = !_isCompletedExpanded),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                _isCompletedExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                                size: 20,
                                color: googleTextSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Completed (${completed.length})',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: googleTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isCompletedExpanded)
                        ...completed.map((r) => _buildAlarmCard(r, isCompleted: true)),
                    ],
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: googleBlue,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.add, size: 20),
        label: const Text('Add Alarm / Reminder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        onPressed: widget.onOpenAddReminder,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: googleBlue.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.alarm_off_outlined, size: 36, color: googleBlue),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Scheduled Alarms',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: googleTextPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Set revision alarms and test reminders with exact minute notification bells.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: googleTextSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: widget.onOpenAddReminder,
              icon: const Icon(Icons.add_alarm_rounded, size: 18),
              label: const Text('Create New Alarm'),
              style: ElevatedButton.styleFrom(
                backgroundColor: googleBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmCard(Map<String, dynamic> reminder, {required bool isCompleted}) {
    final id = reminder['id'] as int;
    final text = reminder['text'] ?? 'Study Alarm';
    final remindAtStr = reminder['remind_at'] ?? '';

    DateTime remindAt = DateTime.now();
    try {
      remindAt = DateTime.parse(remindAtStr);
    } catch (_) {}

    final timeFormatted = DateFormat('h:mm a').format(remindAt).toLowerCase();
    final dateFormatted = DateFormat('EEE, d MMM').format(remindAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: googleHairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openAlarmEditor(reminder),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              children: [
                // Completed Checkbox
                GoogleCheckbox(
                  value: isCompleted,
                  onChanged: (val) => _toggleReminder(id, val),
                ),
                const SizedBox(width: 10),

                // Time, Date & Title
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            timeFormatted,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isCompleted ? googleTextSecondary : googleTextPrimary,
                              decoration: isCompleted ? TextDecoration.lineThrough : null,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            dateFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isCompleted ? googleBorder : googleTextSecondary,
                              decoration: isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isCompleted ? googleTextSecondary : googleTextPrimary,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Three dots / Edit button
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded, color: googleTextSecondary, size: 20),
                  tooltip: 'Alarm Options',
                  onPressed: () => _openAlarmEditor(reminder),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Google Clock / Android Alarm Style Bottom Sheet Editor
class _AlarmEditorSheet extends StatefulWidget {
  final int id;
  final String initialText;
  final DateTime initialDateTime;
  final Future<void> Function(String newText, DateTime newDateTime) onSave;
  final VoidCallback onDelete;

  const _AlarmEditorSheet({
    Key? key,
    required this.id,
    required this.initialText,
    required this.initialDateTime,
    required this.onSave,
    required this.onDelete,
  }) : super(key: key);

  @override
  __AlarmEditorSheetState createState() => __AlarmEditorSheetState();
}

class __AlarmEditorSheetState extends State<_AlarmEditorSheet> {
  late TextEditingController _nameController;
  late TimeOfDay _selectedTime;
  late DateTime _selectedDate;
  bool _vibrate = true;
  bool _isSaving = false;

  final Set<int> _selectedDays = {};
  final List<String> _dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialText);
    _selectedTime = TimeOfDay.fromDateTime(widget.initialDateTime);
    _selectedDate = widget.initialDateTime;
    _selectedDays.add(widget.initialDateTime.weekday % 7);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: googleBlue,
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: googleTextPrimary,
              ),
            ),
            child: child!,
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(now) ? now : _selectedDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: googleBlue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: googleTextPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedDays.clear();
        _selectedDays.add(picked.weekday % 7);
      });
    }
  }

  String _formatUpcomingMessage() {
    final now = DateTime.now();
    final target = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    if (target.isBefore(now)) {
      return 'Past alarm · Set a future time';
    }

    final diff = target.difference(now);
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;

    if (hours == 0 && mins < 60) {
      return 'Upcoming in $mins minute${mins == 1 ? "" : "s"}';
    } else if (hours < 24 && target.day == now.day) {
      return 'Upcoming today at ${_formatTimeDisplay()}';
    } else if (hours < 48 && target.day == now.day + 1) {
      return 'Upcoming tomorrow at ${_formatTimeDisplay()}';
    } else {
      return 'Scheduled for ${DateFormat('EEE, d MMM • h:mm a').format(target)}';
    }
  }

  String _formatTimeDisplay() {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, _selectedTime.hour, _selectedTime.minute);
    return DateFormat('h:mm a').format(dt).toLowerCase();
  }

  Future<void> _handleSave() async {
    final newText = _nameController.text.trim().isEmpty ? 'Study Alarm' : _nameController.text.trim();
    final newDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    setState(() => _isSaving = true);
    await widget.onSave(newText, newDateTime);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = _formatTimeDisplay();
    final upcomingMsg = _formatUpcomingMessage();

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E2EC),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 1. Time Display with "Edit" Button (Google Clock style)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _pickTime,
                    child: Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w400,
                        color: googleTextPrimary,
                        letterSpacing: -1.5,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _pickTime,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: googleBlue,
                      side: const BorderSide(color: googleBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('Edit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Day Selector Pills (S M T W T F S)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (index) {
                  final isSelected = _selectedDays.contains(index);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedDays.remove(index);
                        } else {
                          _selectedDays.add(index);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected ? googleBlue : const Color(0xFFF1F3F4),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _dayLabels[index],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : googleTextSecondary,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),

              // 3. Upcoming Alarm Info & Calendar Pick
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 16, color: googleTextSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            upcomingMsg,
                            style: const TextStyle(fontSize: 12, color: googleTextSecondary, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 14, color: googleBlue),
                    label: const Text('Schedule Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 4. Detail Options Card (Alarm Name, Sound, Vibrate)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: googleHairline),
                ),
                child: Column(
                  children: [
                    // Alarm Name Field
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.label_outline_rounded, size: 20, color: googleTextSecondary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: googleTextPrimary),
                              decoration: const InputDecoration(
                                hintText: 'Alarm name (e.g. GATE CS Revision)',
                                border: InputBorder.none,
                                hintStyle: TextStyle(fontSize: 13, color: googleBorder),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, thickness: 1, color: googleHairline),

                    // Sound Info
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.notifications_none_rounded, size: 20, color: googleTextSecondary),
                          SizedBox(width: 14),
                          Text('Sound', style: TextStyle(fontSize: 14, color: googleTextPrimary)),
                          Spacer(),
                          Text('Default (study chime)', style: TextStyle(fontSize: 12, color: googleTextSecondary)),
                        ],
                      ),
                    ),
                    const Divider(height: 1, thickness: 1, color: googleHairline),

                    // Vibrate Switch
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.vibration_rounded, size: 20, color: googleTextSecondary),
                          const SizedBox(width: 14),
                          const Text('Vibrate', style: TextStyle(fontSize: 14, color: googleTextPrimary)),
                          const Spacer(),
                          Switch(
                            value: _vibrate,
                            activeColor: googleBlue,
                            onChanged: (val) => setState(() => _vibrate = val),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 5. Bottom Actions: Delete (Left) and Save (Right)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Subtle Delete Button on Bottom Left (Google Clock style)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onDelete();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: googleRed,
                      backgroundColor: const Color(0xFFFDE8E8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: googleRed),
                    label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),

                  // Solid Save Button on Bottom Right
                  ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: googleBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
