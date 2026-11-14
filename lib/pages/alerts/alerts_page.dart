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

  // Daily study routine settings
  bool _morningEnabled = true;
  bool _afternoonEnabled = true;
  bool _eveningEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);
    try {
      // 1. Automatically complete expired past reminders
      await DatabaseService.instance.autoCompleteExpiredReminders();

      // 2. Load latest custom reminders
      final reminders = await DatabaseService.instance.getCustomReminders();

      // 3. Load daily routine settings
      final settings = await DatabaseService.instance.getAlertSettings();
      final morning = (settings['morning_brief'] as int? ?? 1) == 1;
      final afternoon = (settings['afternoon_session'] as int? ?? 1) == 1;
      final evening = (settings['evening_review'] as int? ?? 1) == 1;

      if (mounted) {
        setState(() {
          _reminders = reminders;
          _morningEnabled = morning;
          _afternoonEnabled = afternoon;
          _eveningEnabled = evening;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading alerts: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleRoutine({
    bool? morning,
    bool? afternoon,
    bool? evening,
    required String title,
  }) async {
    final newMorning = morning ?? _morningEnabled;
    final newAfternoon = afternoon ?? _afternoonEnabled;
    final newEvening = evening ?? _eveningEnabled;

    setState(() {
      _morningEnabled = newMorning;
      _afternoonEnabled = newAfternoon;
      _eveningEnabled = newEvening;
    });

    await DatabaseService.instance.setDailyRoutineSettings(
      morning: newMorning,
      afternoon: newAfternoon,
      evening: newEvening,
    );

    await NotificationService.instance.scheduleDailySessionAlerts(
      morning: newMorning,
      afternoon: newAfternoon,
      evening: newEvening,
    );

    final bool isEnabled = (morning ?? afternoon ?? evening) ?? false;
    if (mounted) {
      TopBanner.show(
        context,
        title: isEnabled ? '$title Enabled' : '$title Disabled',
        message: isEnabled
            ? 'Scheduled recurring notification active.'
            : 'Notification turned off.',
        icon: isEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
        color: isEnabled ? googleBlue : googleTextSecondary,
      );
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

  Future<void> _toggleReminder(
    int id,
    bool completed, {
    String? repeatDays,
    String? remindAtStr,
    String? text,
  }) async {
    await DatabaseService.instance.toggleReminderStatus(id, completed);
    if (completed) {
      await NotificationService.instance.cancelReminder(id);
    } else if (remindAtStr != null && text != null) {
      final dt = DateTime.tryParse(remindAtStr) ?? DateTime.now();
      await NotificationService.instance.scheduleReminder(
        id: id,
        title: 'Study Reminder',
        body: text,
        scheduledDate: dt,
        repeatDays: repeatDays,
      );
    }
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

  Future<void> _openNewAlarmEditor() async {
    final now = DateTime.now();
    final initialDate = now.add(const Duration(minutes: 30));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AlarmEditorSheet(
        id: null,
        initialText: 'Study Alarm',
        initialDateTime: initialDate,
        initialRepeatDays: null,
        onSave: (newText, newDateTime, newRepeatDays) async {
          final id = await DatabaseService.instance.addCustomReminder(
            newText,
            newDateTime,
            repeatDays: newRepeatDays,
          );
          await NotificationService.instance.scheduleReminder(
            id: id,
            title: 'Study Reminder',
            body: newText,
            scheduledDate: newDateTime,
            repeatDays: newRepeatDays,
          );
          await _loadAlerts();
          widget.onDataChanged();
          if (mounted) {
            TopBanner.show(
              context,
              title: 'Alarm Created',
              message: '$newText • ${DateFormat('d MMM, hh:mm a').format(newDateTime)}',
              icon: Icons.alarm_on_rounded,
              color: googleGreen,
            );
          }
        },
        onDelete: null,
      ),
    );
  }

  Future<void> _openAlarmEditor(Map<String, dynamic> reminder) async {
    final int id = reminder['id'] as int;
    final String initialText = reminder['text'] ?? 'Study Alarm';
    final String remindAtStr = reminder['remind_at'] ?? DateTime.now().toIso8601String();
    final DateTime initialDate = DateTime.tryParse(remindAtStr) ?? DateTime.now();
    final String? repeatDays = reminder['repeat_days'] as String?;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AlarmEditorSheet(
        id: id,
        initialText: initialText,
        initialDateTime: initialDate,
        initialRepeatDays: repeatDays,
        onSave: (newText, newDateTime, newRepeatDays) async {
          await DatabaseService.instance.updateCustomReminder(
            id: id,
            text: newText,
            remindAt: newDateTime,
            repeatDays: newRepeatDays,
          );
          await NotificationService.instance.scheduleReminder(
            id: id,
            title: 'Study Reminder',
            body: newText,
            scheduledDate: newDateTime,
            repeatDays: newRepeatDays,
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
            onPressed: _openNewAlarmEditor,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: googleBlue))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              children: [
                // 1. Daily Study Routine Section
                _buildDailyRoutineSection(),

                // 2. Custom Alarms Header
                _buildCustomAlarmsHeader(pending.length),

                // 3. Custom Alarms List or Empty Indicator
                if (pending.isNotEmpty) ...[
                  ...pending.map((r) => _buildAlarmCard(r, isCompleted: false)),
                ] else if (completed.isNotEmpty) ...[
                  _buildAllCompletedCard(),
                ] else ...[
                  _buildEmptyCustomAlarms(),
                ],

                // 4. Completed Section Accordion
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
        onPressed: _openNewAlarmEditor,
      ),
    );
  }

  Widget _buildDailyRoutineSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: googleBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.schedule_rounded, color: googleBlue, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Study Routine',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: googleTextPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Automated daily alerts for structured GATE prep',
                        style: TextStyle(
                          fontSize: 12,
                          color: googleTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: googleHairline),
          _buildRoutineRow(
            icon: Icons.wb_sunny_outlined,
            iconColor: const Color(0xFFE37400),
            title: 'Morning Brief',
            time: '05:00 AM',
            description: 'Target lectures and Ebbinghaus recall items',
            enabled: _morningEnabled,
            onChanged: (val) => _toggleRoutine(morning: val, title: 'Morning Brief'),
          ),
          const Divider(height: 1, thickness: 1, color: googleHairline),
          _buildRoutineRow(
            icon: Icons.light_mode_outlined,
            iconColor: const Color(0xFF1A73E8),
            title: 'Afternoon Session',
            time: '01:30 PM',
            description: 'Midday focus block and aptitude practice',
            enabled: _afternoonEnabled,
            onChanged: (val) => _toggleRoutine(afternoon: val, title: 'Afternoon Session'),
          ),
          const Divider(height: 1, thickness: 1, color: googleHairline),
          _buildRoutineRow(
            icon: Icons.nightlight_outlined,
            iconColor: const Color(0xFF5F6368),
            title: 'Evening Review',
            time: '07:00 PM',
            description: 'Daily progress review and recall checkpoints',
            enabled: _eveningEnabled,
            onChanged: (val) => _toggleRoutine(evening: val, title: 'Evening Review'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutineRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String time,
    required String description,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: googleTextPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: enabled ? googleBlue.withOpacity(0.08) : const Color(0xFFF1F3F4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        time,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: enabled ? googleBlue : googleTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: googleTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            activeColor: googleBlue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildCustomAlarmsHeader(int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text(
                'Custom Study Alarms',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: googleTextSecondary,
                  letterSpacing: 0.2,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: googleBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: googleBlue,
                    ),
                  ),
                ),
              ],
            ],
          ),
          TextButton.icon(
            onPressed: _openNewAlarmEditor,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            icon: const Icon(Icons.add, size: 16, color: googleBlue),
            label: const Text(
              'New Alarm',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCustomAlarms() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: googleHairline),
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: googleBlue.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.alarm_off_outlined, color: googleBlue, size: 28),
            ),
            const SizedBox(height: 12),
            const Text(
              'No Custom Alarms Scheduled',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: googleTextPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Add custom alarms for specific revision topics, mock tests, or study blocks.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: googleTextSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _openNewAlarmEditor,
              icon: const Icon(Icons.add_alarm_rounded, size: 16, color: googleBlue),
              label: const Text('Add Alarm / Reminder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: googleBlue)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: googleBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllCompletedCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: googleHairline),
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: googleGreen.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.task_alt_rounded, color: googleGreen, size: 24),
            ),
            const SizedBox(height: 10),
            const Text(
              'All Alarms Completed',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: googleTextPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'All active alarms have been cleared or expired into completed.',
              style: TextStyle(fontSize: 12, color: googleTextSecondary),
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
    final String? repeatDays = reminder['repeat_days'] as String?;

    DateTime remindAt = DateTime.now();
    try {
      remindAt = DateTime.parse(remindAtStr);
    } catch (_) {}

    final timeFormatted = DateFormat('h:mm a').format(remindAt).toLowerCase();
    final dateFormatted = DateFormat('EEE, d MMM').format(remindAt);

    // Compute recurring routine label if days are configured
    String? routineBadgeText;
    if (repeatDays != null && repeatDays.trim().isNotEmpty) {
      final days = repeatDays
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .where((d) => d >= 0 && d <= 6)
          .toSet();
      if (days.length == 7) {
        routineBadgeText = 'Daily';
      } else if (days.length == 5 && {1, 2, 3, 4, 5}.every(days.contains)) {
        routineBadgeText = 'Mon–Fri';
      } else if (days.length == 2 && {0, 6}.every(days.contains)) {
        routineBadgeText = 'Weekends';
      } else if (days.isNotEmpty) {
        const shortNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        final sorted = days.toList()..sort();
        routineBadgeText = sorted.map((d) => shortNames[d]).join(', ');
      }
    }

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
                  onChanged: (val) => _toggleReminder(
                    id,
                    val,
                    repeatDays: repeatDays,
                    remindAtStr: remindAtStr,
                    text: text,
                  ),
                ),
                const SizedBox(width: 12),

                // Note (Title) & Time/Date Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Prominent Note / Title
                      Text(
                        text,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isCompleted ? googleTextSecondary : googleTextPrimary,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Formatted time, routine badge, or date below as subtitle
                      Row(
                        children: [
                          Icon(
                            routineBadgeText != null ? Icons.repeat_rounded : Icons.access_time_rounded,
                            size: 14,
                            color: isCompleted ? googleBorder : googleBlue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeFormatted,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isCompleted ? googleTextSecondary : googleBlue,
                              decoration: isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '•',
                            style: TextStyle(
                              fontSize: 11,
                              color: isCompleted ? googleBorder : googleTextSecondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (routineBadgeText != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isCompleted
                                    ? const Color(0xFFF1F3F4)
                                    : googleBlue.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                routineBadgeText,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isCompleted ? googleBorder : googleBlue,
                                ),
                              ),
                            ),
                          ] else ...[
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
                        ],
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
  final int? id;
  final String initialText;
  final DateTime initialDateTime;
  final String? initialRepeatDays;
  final Future<void> Function(String newText, DateTime newDateTime, String? newRepeatDays) onSave;
  final VoidCallback? onDelete;

  const _AlarmEditorSheet({
    Key? key,
    this.id,
    required this.initialText,
    required this.initialDateTime,
    this.initialRepeatDays,
    required this.onSave,
    this.onDelete,
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

    if (widget.initialRepeatDays != null && widget.initialRepeatDays!.trim().isNotEmpty) {
      final days = widget.initialRepeatDays!
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .where((d) => d >= 0 && d <= 6);
      _selectedDays.addAll(days);
    } else {
      _selectedDays.add(widget.initialDateTime.weekday % 7);
    }
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

    // If day routine pills are selected, show recurring schedule
    if (_selectedDays.isNotEmpty) {
      if (_selectedDays.length == 7) {
        return 'Repeats daily at ${_formatTimeDisplay()}';
      }
      final weekdays = {1, 2, 3, 4, 5};
      final weekends = {0, 6};
      if (_selectedDays.length == 5 && weekdays.every(_selectedDays.contains)) {
        return 'Repeats weekdays (Mon–Fri) at ${_formatTimeDisplay()}';
      }
      if (_selectedDays.length == 2 && weekends.every(_selectedDays.contains)) {
        return 'Repeats weekends at ${_formatTimeDisplay()}';
      }
      const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      final sorted = _selectedDays.toList()..sort();
      final dayNames = sorted.map((d) => names[d]).join(', ');
      return 'Repeats $dayNames at ${_formatTimeDisplay()}';
    }

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

    // Collect selected routine day pills (0=Sun, 1=Mon, ..., 6=Sat)
    final sortedDays = _selectedDays.toList()..sort();
    final String? newRepeatDays = sortedDays.isNotEmpty ? sortedDays.join(',') : null;

    setState(() => _isSaving = true);
    try {
      await widget.onSave(newText, newDateTime, newRepeatDays);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving alarm: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        TopBanner.show(
          context,
          title: 'Error Saving Alarm',
          message: e.toString(),
          icon: Icons.error_outline_rounded,
          color: googleRed,
        );
      }
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
                        Icon(
                          _selectedDays.isNotEmpty ? Icons.repeat_rounded : Icons.access_time_rounded,
                          size: 16,
                          color: googleTextSecondary,
                        ),
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

              // 5. Bottom Actions: Delete or Cancel (Left) and Save (Right)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.onDelete != null) ...[
                    // Subtle Delete Button on Bottom Left (Google Clock style)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onDelete!();
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
                  ] else ...[
                    // Cancel Button for New Alarm
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: googleTextSecondary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ],

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
