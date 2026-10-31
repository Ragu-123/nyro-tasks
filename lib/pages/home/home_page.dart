import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tasks/pages/tabs/today_tab.dart';
import 'package:tasks/pages/tabs/timetable_tab.dart';
import 'package:tasks/pages/tabs/revisit_tab.dart';
import 'package:tasks/pages/tabs/quizzes_tab.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/services/notification_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentNavIndex = 0;
  DateTime _currentDate = DateTime.now();

  // Scroll tracking for circular pacing ring in App Bar
  final ScrollController _todayScrollController = ScrollController();
  bool _showAppBarPacingRing = false;
  double _todayProgress = 0.0;

  // Global filters & badge counts
  String _selectedSubject = 'All Subjects';
  List<String> _availableSubjects = ['All Subjects'];
  Map<String, int> _badgeCounts = {'due_revisits': 0, 'pending_quizzes': 0};

  @override
  void initState() {
    super.initState();
    _todayScrollController.addListener(_onTodayScroll);
    _loadGlobalData();
  }

  @override
  void dispose() {
    _todayScrollController.removeListener(_onTodayScroll);
    _todayScrollController.dispose();
    super.dispose();
  }

  void _onTodayScroll() {
    final offset = _todayScrollController.offset;
    final shouldShow = offset > 80;
    if (shouldShow != _showAppBarPacingRing) {
      setState(() => _showAppBarPacingRing = shouldShow);
    }
  }

  Future<void> _loadGlobalData() async {
    final subjs = await DatabaseService.instance.getAllDistinctSubjects();
    final badges = await DatabaseService.instance.getBadgeCounts();
    final pacing = await DatabaseService.instance.getDailyPacing(_currentDate);

    final target = (pacing['target_hours'] as num?)?.toDouble() ?? 8.0;
    final watched = (pacing['watched_hours'] as num?)?.toDouble() ?? 0.0;
    final progress = target > 0 ? (watched / target).clamp(0.0, 1.0) : 0.0;

    if (mounted) {
      setState(() {
        _availableSubjects = subjs;
        _badgeCounts = badges;
        _todayProgress = progress;
      });
    }
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentDate,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2028, 12, 31),
    );
    if (picked != null) {
      setState(() => _currentDate = picked);
      _loadGlobalData();
    }
  }

  // --- Google Tasks Style Add Reminder / Task Flow ---

  void _showNewTaskBottomSheet() {
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);
    bool hasTime = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final formattedDate = DateFormat('EEE, d MMM').format(selectedDate);
            final formattedTime = selectedTime.format(context);

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 16,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    decoration: const InputDecoration(
                      hintText: 'New task / reminder',
                      hintStyle: TextStyle(fontSize: 16, color: googleTextSecondary),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Date and Time Chips (Google Tasks Flow)
                  Row(
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.calendar_today, size: 14, color: googleBlue),
                        label: Text(formattedDate, style: const TextStyle(fontSize: 12, color: googleBlue)),
                        backgroundColor: const Color(0xFFF0F4F9),
                        side: BorderSide.none,
                        onPressed: () async {
                          final pDate = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2026, 1, 1),
                            lastDate: DateTime(2028, 12, 31),
                          );
                          if (pDate != null) {
                            setSheetState(() => selectedDate = pDate);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(Icons.access_time, size: 14, color: googleBlue),
                        label: Text(hasTime ? formattedTime : 'Set time', style: const TextStyle(fontSize: 12, color: googleBlue)),
                        backgroundColor: const Color(0xFFF0F4F9),
                        side: BorderSide.none,
                        onPressed: () async {
                          final pTime = await showTimePicker(
                            context: context,
                            initialTime: selectedTime,
                          );
                          if (pTime != null) {
                            setSheetState(() {
                              selectedTime = pTime;
                              hasTime = true;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel', style: TextStyle(color: googleTextSecondary)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final text = titleController.text.trim();
                          if (text.isNotEmpty) {
                            final scheduled = DateTime(
                              selectedDate.year,
                              selectedDate.month,
                              selectedDate.day,
                              hasTime ? selectedTime.hour : 9,
                              hasTime ? selectedTime.minute : 0,
                            );

                            final id = await DatabaseService.instance.addCustomReminder(text, scheduled);
                            await NotificationService.instance.scheduleReminder(
                              id: id,
                              title: 'NYRO Study Task',
                              body: text,
                              scheduledDate: scheduled,
                            );
                            _loadGlobalData();
                          }
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: googleBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- Alerts & Notifications Modal Sheet ---

  void _showAlertsSheet() async {
    final alertSettings = await DatabaseService.instance.getAlertSettings();
    final reminders = await DatabaseService.instance.getCustomReminders();

    bool morningBrief = (alertSettings['morning_brief'] as num?)?.toInt() == 1;
    bool revisitAlerts = (alertSettings['revisit_alerts'] as num?)?.toInt() == 1;
    bool backlogShield = (alertSettings['backlog_shield'] as num?)?.toInt() == 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Alerts & Study Routine',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: googleTextPrimary),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: googleTextSecondary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 1, thickness: 1, color: googleHairline),
                  const SizedBox(height: 12),

                  Expanded(
                    child: ListView(
                      children: [
                        const Text(
                          'DAILY STUDY NOTIFICATIONS',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleTextSecondary, letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 8),

                        // 5:00 AM Morning Brief
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Morning Brief (05:00 AM)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Daily wake-up prompt with targets and due recall items', style: TextStyle(fontSize: 12, color: googleTextSecondary)),
                          value: morningBrief,
                          activeColor: googleBlue,
                          onChanged: (val) async {
                            setSheetState(() => morningBrief = val);
                            await DatabaseService.instance.updateAlertSettings(
                              morningBrief: val,
                              revisitAlerts: revisitAlerts,
                              backlogShield: backlogShield,
                            );
                            await NotificationService.instance.scheduleDailySessionAlerts(
                              morning: val,
                              afternoon: revisitAlerts,
                              evening: backlogShield,
                            );
                          },
                        ),

                        // 1:30 PM Afternoon Session
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Afternoon Session (01:30 PM)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Afternoon & Aptitude block study reminder', style: TextStyle(fontSize: 12, color: googleTextSecondary)),
                          value: revisitAlerts,
                          activeColor: googleBlue,
                          onChanged: (val) async {
                            setSheetState(() => revisitAlerts = val);
                            await DatabaseService.instance.updateAlertSettings(
                              morningBrief: morningBrief,
                              revisitAlerts: val,
                              backlogShield: backlogShield,
                            );
                            await NotificationService.instance.scheduleDailySessionAlerts(
                              morning: morningBrief,
                              afternoon: val,
                              evening: backlogShield,
                            );
                          },
                        ),

                        // 7:00 PM Evening Review
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Evening Review (07:00 PM)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Review progress and clear Day 1/4/7 recall checkpoints', style: TextStyle(fontSize: 12, color: googleTextSecondary)),
                          value: backlogShield,
                          activeColor: googleBlue,
                          onChanged: (val) async {
                            setSheetState(() => backlogShield = val);
                            await DatabaseService.instance.updateAlertSettings(
                              morningBrief: morningBrief,
                              revisitAlerts: revisitAlerts,
                              backlogShield: val,
                            );
                            await NotificationService.instance.scheduleDailySessionAlerts(
                              morning: morningBrief,
                              afternoon: revisitAlerts,
                              evening: val,
                            );
                          },
                        ),

                        const SizedBox(height: 16),
                        const Divider(height: 1, thickness: 1, color: googleHairline),
                        const SizedBox(height: 16),

                        // Custom Google Tasks Reminders List
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'CUSTOM REMINDERS',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleTextSecondary, letterSpacing: 0.6),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.add, size: 16, color: googleBlue),
                              label: const Text('Add', style: TextStyle(fontSize: 12, color: googleBlue)),
                              onPressed: () {
                                Navigator.pop(context);
                                _showNewTaskBottomSheet();
                              },
                            ),
                          ],
                        ),
                        if (reminders.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('No custom reminders active.', style: TextStyle(fontSize: 13, color: googleTextSecondary)),
                            ),
                          )
                        else
                          ...reminders.map((r) {
                            final id = r['id'] as int;
                            final text = r['text'] ?? '';
                            final remindAt = r['remind_at'] ?? '';
                            String timeStr = remindAt;
                            try {
                              timeStr = DateFormat('d MMM, hh:mm a').format(DateTime.parse(remindAt));
                            } catch (_) {}

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.notifications_active_outlined, size: 20, color: googleBlue),
                              title: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                              subtitle: Text(timeStr, style: const TextStyle(fontSize: 12, color: googleTextSecondary)),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: googleTextSecondary),
                                onPressed: () async {
                                  await DatabaseService.instance.deleteCustomReminder(id);
                                  await NotificationService.instance.cancelNotification(id);
                                  final updated = await DatabaseService.instance.getCustomReminders();
                                  setSheetState(() {
                                    reminders.clear();
                                    reminders.addAll(updated);
                                  });
                                  _loadGlobalData();
                                },
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('EEE, d MMM').format(_currentDate);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const Text(
              'Tasks',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: googleTextPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 8),

            // Animated circular progress indicator in App Bar (Appears when scrolled down)
            if (_currentNavIndex == 0 && _showAppBarPacingRing) ...[
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  value: _todayProgress,
                  strokeWidth: 2.5,
                  backgroundColor: const Color(0xFFF1F3F4),
                  valueColor: const AlwaysStoppedAnimation<Color>(googleBlue),
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Date Picker Chip
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: googleTextPrimary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_drop_down, size: 16, color: googleTextSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Contextual Subject Filter Dropdown (for Timetable, Revisit, Quizzes)
          if (_currentNavIndex != 0) ...[
            PopupMenuButton<String>(
              initialValue: _selectedSubject,
              tooltip: 'Filter by Subject',
              onSelected: (val) {
                setState(() => _selectedSubject = val);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: googleBorder),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedSubject == 'All Subjects' ? 'Filter' : _selectedSubject.split(' ').first,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: googleBlue),
                    ),
                    const Icon(Icons.arrow_drop_down, size: 14, color: googleBlue),
                  ],
                ),
              ),
              itemBuilder: (context) {
                return _availableSubjects.map((s) {
                  return PopupMenuItem<String>(
                    value: s,
                    child: Text(s, style: TextStyle(fontSize: 13, fontWeight: s == _selectedSubject ? FontWeight.bold : FontWeight.normal)),
                  );
                }).toList();
              },
            ),
            const SizedBox(width: 4),
          ],

          // Jump to Today action
          IconButton(
            icon: const Icon(Icons.today, size: 20, color: googleBlue),
            tooltip: 'Jump to Today',
            onPressed: () {
              setState(() => _currentDate = DateTime.now());
              _loadGlobalData();
            },
          ),

          // Google Bell Icon with Live Badge Dot for Alerts & Reminders
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none, size: 22, color: googleTextPrimary),
                tooltip: 'Alerts & Reminders',
                onPressed: _showAlertsSheet,
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: googleAmber,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),

      // 4 Main Tab Views
      body: IndexedStack(
        index: _currentNavIndex,
        children: [
          TodayTab(
            currentDate: _currentDate,
            onDataChanged: _loadGlobalData,
            scrollController: _todayScrollController,
          ),
          TimetableTab(
            onDataChanged: _loadGlobalData,
            selectedSubject: _selectedSubject,
          ),
          RevisitTab(
            onDataChanged: _loadGlobalData,
            selectedSubject: _selectedSubject,
          ),
          QuizzesTab(
            onDataChanged: _loadGlobalData,
            selectedSubject: _selectedSubject,
          ),
        ],
      ),

      // Quick "+" Floating Action Button
      floatingActionButton: FloatingActionButton(
        elevation: 3.0,
        backgroundColor: Colors.white,
        foregroundColor: googleBlue,
        onPressed: _showNewTaskBottomSheet,
        child: const Icon(Icons.add, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // Clean 4-Item Bottom Navigation Bar
      bottomNavigationBar: BottomAppBar(
        elevation: 8.0,
        color: Colors.white,
        notchMargin: 6.0,
        shape: const CircularNotchedRectangle(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.access_time, 'Today', 0),
            _buildNavItem(1, Icons.calendar_month_outlined, 'Timetable', 0),
            const SizedBox(width: 44), // FAB gap
            _buildNavItem(2, Icons.replay, 'Revisit', _badgeCounts['due_revisits'] ?? 0),
            _buildNavItem(3, Icons.check_circle_outline, 'Quizzes', _badgeCounts['pending_quizzes'] ?? 0),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, int badgeCount) {
    final isSelected = _currentNavIndex == index;
    final color = isSelected ? googleBlue : googleTextSecondary;

    return InkWell(
      onTap: () {
        setState(() => _currentNavIndex = index);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 22),
                if (badgeCount > 0)
                  Positioned(
                    top: -2,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: googleAmber,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : badgeCount.toString(),
                        style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
