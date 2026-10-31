import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/services/notification_service.dart';
import 'package:tasks/utils/theme.dart';

class RemindersTab extends StatefulWidget {
  const RemindersTab({Key? key}) : super(key: key);

  @override
  _RemindersTabState createState() => _RemindersTabState();
}

class _RemindersTabState extends State<RemindersTab> {
  List<Map<String, dynamic>> _reminders = [];
  bool _isLoading = true;
  bool _morningBriefEnabled = true;
  bool _spacedAlarmsEnabled = true;

  final TextEditingController _textController = TextEditingController();
  DateTime _selectedDateTime = DateTime.now().add(const Duration(hours: 1));

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    setState(() => _isLoading = true);
    final items = await DatabaseService.instance.getCustomReminders();
    if (mounted) {
      setState(() {
        _reminders = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _addReminder() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reminder text')),
      );
      return;
    }

    final id = await DatabaseService.instance.addCustomReminder(text, _selectedDateTime);
    await NotificationService.instance.scheduleReminder(
      id: id,
      title: 'NYRO Study Reminder',
      body: text,
      scheduledDate: _selectedDateTime,
    );

    _textController.clear();
    setState(() {
      _selectedDateTime = DateTime.now().add(const Duration(hours: 1));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reminder scheduled!')),
    );
    await _loadReminders();
  }

  Future<void> _deleteReminder(int id) async {
    await DatabaseService.instance.deleteCustomReminder(id);
    await NotificationService.instance.cancelNotification(id);
    await _loadReminders();
  }

  void _addQuickTime(Duration dur) {
    setState(() {
      _selectedDateTime = DateTime.now().add(dur);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: googleBlue));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Automated Briefings Section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: googleBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AUTOMATED NOTIFICATIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: googleTextSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Morning Brief',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '05:00 AM IST • Today\'s lectures & recall',
                        style: TextStyle(fontSize: 12, color: googleTextSecondary),
                      ),
                    ],
                  ),
                  Switch(
                    value: _morningBriefEnabled,
                    activeColor: googleBlue,
                    onChanged: (val) {
                      setState(() => _morningBriefEnabled = val);
                    },
                  ),
                ],
              ),
              const Divider(height: 16, color: googleBorder),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Spaced Revisit Reminders',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '1, 4, 7, 14, 30 day recall alerts',
                        style: TextStyle(fontSize: 12, color: googleTextSecondary),
                      ),
                    ],
                  ),
                  Switch(
                    value: _spacedAlarmsEnabled,
                    activeColor: googleBlue,
                    onChanged: (val) {
                      setState(() => _spacedAlarmsEnabled = val);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Add Custom Reminder Form
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: googleBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SET CUSTOM REMINDER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: googleTextSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: 'e.g. Solve 10 Predicate Logic PYQs...',
                  hintStyle: const TextStyle(fontSize: 13, color: googleTextSecondary),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFD),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: googleBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: googleBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: googleBlue),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Quick time pills
              Row(
                children: [
                  _buildQuickPill('+30 min', const Duration(minutes: 30)),
                  const SizedBox(width: 6),
                  _buildQuickPill('+1 hr', const Duration(hours: 1)),
                  const SizedBox(width: 6),
                  _buildQuickPill('+2 hrs', const Duration(hours: 2)),
                  const SizedBox(width: 6),
                  _buildQuickPill('Tomorrow', const Duration(days: 1)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Time: ${DateFormat('EEE, d MMM - hh:mm a').format(_selectedDateTime)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: googleTextPrimary),
                  ),
                  ElevatedButton(
                    onPressed: _addReminder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: googleBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    child: const Text('Set Reminder', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Custom Reminders List
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
          child: Text(
            'ACTIVE REMINDERS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: googleTextSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),

        if (_reminders.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: const Text(
              'No custom reminders set.',
              style: TextStyle(fontSize: 13, color: googleTextSecondary),
            ),
          ),

        ..._reminders.map((rem) {
          final id = rem['id'] as int;
          DateTime? dt;
          if (rem['remind_at'] != null) {
            dt = DateTime.tryParse(rem['remind_at']);
          }
          final formattedTime = dt != null
              ? DateFormat('EEE, d MMM - hh:mm a').format(dt)
              : 'Upcoming';

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: googleBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_outlined, color: googleBlue, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rem['text'] ?? '',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formattedTime,
                        style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                  onPressed: () => _deleteReminder(id),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildQuickPill(String label, Duration dur) {
    return InkWell(
      onTap: () => _addQuickTime(dur),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF444746)),
        ),
      ),
    );
  }
}
