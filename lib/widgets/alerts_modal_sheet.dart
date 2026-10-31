import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/services/notification_service.dart';
import 'package:tasks/utils/theme.dart';

class AlertsModalSheet extends StatefulWidget {
  final VoidCallback onDataChanged;
  final VoidCallback onOpenAddReminder;

  const AlertsModalSheet({
    Key? key,
    required this.onDataChanged,
    required this.onOpenAddReminder,
  }) : super(key: key);

  @override
  _AlertsModalSheetState createState() => _AlertsModalSheetState();
}

class _AlertsModalSheetState extends State<AlertsModalSheet> {
  late PageController _pageController;
  int _activeSubTab = 0; // 0: Reminders, 1: Daily Study Routine

  List<Map<String, dynamic>> _reminders = [];
  bool _morningBrief = true;
  bool _afternoonSession = true;
  bool _eveningReview = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadAlertsData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadAlertsData() async {
    setState(() => _isLoading = true);
    final alertSettings = await DatabaseService.instance.getAlertSettings();
    final reminders = await DatabaseService.instance.getCustomReminders();

    if (mounted) {
      setState(() {
        _morningBrief = (alertSettings['morning_brief'] as num?)?.toInt() == 1;
        _afternoonSession = (alertSettings['revisit_alerts'] as num?)?.toInt() == 1;
        _eveningReview = (alertSettings['backlog_shield'] as num?)?.toInt() == 1;
        _reminders = reminders;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteReminder(int id) async {
    await DatabaseService.instance.deleteCustomReminder(id);
    await NotificationService.instance.cancelNotification(id);
    await _loadAlertsData();
    widget.onDataChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder deleted'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _requestNotificationPermission() async {
    final granted = await NotificationService.instance.requestPermissions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted ? 'Notification permissions granted!' : 'Permission status updated'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E2EC),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Alerts & Routine',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: googleTextPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: googleTextSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Swipeable Sub-Tabs Indicator (Reminders | Daily Routine)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  _buildSubTabButton(0, 'Reminders', _reminders.length),
                  _buildSubTabButton(1, 'Daily Study Routine', 3),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: googleHairline),

          // Content PageView
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: googleBlue))
                : PageView(
                    controller: _pageController,
                    onPageChanged: (idx) => setState(() => _activeSubTab = idx),
                    children: [
                      _buildRemindersPage(),
                      _buildDailyRoutinePage(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabButton(int index, String label, int count) {
    final isSelected = _activeSubTab == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _activeSubTab = index);
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? googleBlue : googleTextSecondary,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? googleBlue : const Color(0xFFDADCE0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : googleTextSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- Page 0: Reminders ---

  Widget _buildRemindersPage() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'YOUR REMINDERS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: googleTextSecondary,
                  letterSpacing: 0.6,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16, color: googleBlue),
                label: const Text('Add Reminder', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue)),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onOpenAddReminder();
                },
              ),
            ],
          ),
        ),

        if (_reminders.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            child: const Center(
              child: Text(
                'No custom reminders scheduled.\nTap Add Reminder to set a date and time.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: googleTextSecondary, height: 1.4),
              ),
            ),
          )
        else
          ..._reminders.map((r) {
            final id = r['id'] as int;
            final text = r['text'] ?? '';
            final remindAt = r['remind_at'] ?? '';
            String timeStr = remindAt;
            try {
              timeStr = DateFormat('EEE, d MMM • hh:mm a').format(DateTime.parse(remindAt));
            } catch (_) {}

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.schedule, size: 18, color: googleBlue),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              text,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: googleTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              timeStr,
                              style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: googleTextSecondary),
                        tooltip: 'Delete',
                        onPressed: () => _deleteReminder(id),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 52),
                  child: Divider(height: 1, thickness: 1, color: googleHairline),
                ),
              ],
            );
          }),
        const SizedBox(height: 40),
      ],
    );
  }

  // --- Page 1: Daily Study Routine ---

  Widget _buildDailyRoutinePage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        // Permission Request Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: googleHairline),
          ),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_outlined, size: 20, color: googleBlue),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Enable Android notification permissions for alarm delivery',
                  style: TextStyle(fontSize: 12, color: googleTextPrimary),
                ),
              ),
              OutlinedButton(
                onPressed: _requestNotificationPermission,
                style: OutlinedButton.styleFrom(
                  foregroundColor: googleBlue,
                  side: const BorderSide(color: googleBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Permission', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        const Text(
          'AUTOMATED SCHEDULED SESSIONS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: googleTextSecondary,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),

        // 1. 05:00 AM Morning Brief
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Morning Brief (05:00 AM)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: const Text('Daily wake-up prompt with today’s lecture targets & due recall drops', style: TextStyle(fontSize: 12, color: googleTextSecondary)),
          value: _morningBrief,
          activeColor: googleBlue,
          onChanged: (val) async {
            setState(() => _morningBrief = val);
            await DatabaseService.instance.updateAlertSettings(
              morningBrief: val,
              revisitAlerts: _afternoonSession,
              backlogShield: _eveningReview,
            );
            await NotificationService.instance.scheduleDailySessionAlerts(
              morning: val,
              afternoon: _afternoonSession,
              evening: _eveningReview,
            );
          },
        ),
        const Divider(height: 1, thickness: 1, color: googleHairline),

        // 2. 01:30 PM Afternoon Session
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Afternoon Session (01:30 PM)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: const Text('Afternoon & Aptitude block study reminder', style: TextStyle(fontSize: 12, color: googleTextSecondary)),
          value: _afternoonSession,
          activeColor: googleBlue,
          onChanged: (val) async {
            setState(() => _afternoonSession = val);
            await DatabaseService.instance.updateAlertSettings(
              morningBrief: _morningBrief,
              revisitAlerts: val,
              backlogShield: _eveningReview,
            );
            await NotificationService.instance.scheduleDailySessionAlerts(
              morning: _morningBrief,
              afternoon: val,
              evening: _eveningReview,
            );
          },
        ),
        const Divider(height: 1, thickness: 1, color: googleHairline),

        // 3. 07:00 PM Evening Review
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Evening Review (07:00 PM)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: const Text('Wrap up today’s lectures, log tricky quiz mistakes, and clear recall checkpoints', style: TextStyle(fontSize: 12, color: googleTextSecondary)),
          value: _eveningReview,
          activeColor: googleBlue,
          onChanged: (val) async {
            setState(() => _eveningReview = val);
            await DatabaseService.instance.updateAlertSettings(
              morningBrief: _morningBrief,
              revisitAlerts: _afternoonSession,
              backlogShield: val,
            );
            await NotificationService.instance.scheduleDailySessionAlerts(
              morning: _morningBrief,
              afternoon: _afternoonSession,
              evening: val,
            );
          },
        ),
      ],
    );
  }
}
