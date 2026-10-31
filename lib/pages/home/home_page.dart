import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tasks/pages/tabs/today_tab.dart';
import 'package:tasks/pages/tabs/timetable_tab.dart';
import 'package:tasks/pages/tabs/revisit_tab.dart';
import 'package:tasks/pages/tabs/quizzes_tab.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/services/notification_service.dart';
import 'package:tasks/widgets/alerts_modal_sheet.dart';
import 'package:tasks/widgets/cloud_sync_modal_sheet.dart';
import 'package:tasks/widgets/subject_filter_modal_sheet.dart';

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

  bool get _isCurrentDateToday {
    final now = DateTime.now();
    return _currentDate.year == now.year &&
        _currentDate.month == now.month &&
        _currentDate.day == now.day;
  }

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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                        avatar: const Icon(Icons.calendar_today_rounded, size: 14, color: googleBlue),
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
                        avatar: const Icon(Icons.access_time_rounded, size: 14, color: googleBlue),
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
                            final now = DateTime.now();
                            final isSelectedToday = selectedDate.year == now.year &&
                                selectedDate.month == now.month &&
                                selectedDate.day == now.day;

                            DateTime scheduled;
                            if (hasTime) {
                              scheduled = DateTime(
                                selectedDate.year,
                                selectedDate.month,
                                selectedDate.day,
                                selectedTime.hour,
                                selectedTime.minute,
                              );
                              // If user picked a time in the past or right now on today,
                              // set to 10 seconds in the future so it fires immediately
                              if (scheduled.isBefore(now)) {
                                scheduled = now.add(const Duration(seconds: 10));
                              }
                            } else {
                              // If no time picked:
                              // If today, default to 15 mins from now
                              if (isSelectedToday) {
                                scheduled = now.add(const Duration(minutes: 15));
                              } else {
                                scheduled = DateTime(
                                  selectedDate.year,
                                  selectedDate.month,
                                  selectedDate.day,
                                  9,
                                  0,
                                );
                              }
                            }

                            final id = await DatabaseService.instance.addCustomReminder(text, scheduled);
                            await NotificationService.instance.scheduleReminder(
                              id: id,
                              title: 'NYRO Study Task',
                              body: text,
                              scheduledDate: scheduled,
                            );
                            _loadGlobalData();

                            if (mounted) {
                              final formattedAlertTime = DateFormat('d MMM • hh:mm a').format(scheduled);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Reminder scheduled for $formattedAlertTime'),
                                  backgroundColor: googleBlue,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
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

  // --- Alerts & Study Routine Sheet ---

  void _showAlertsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AlertsModalSheet(
        onDataChanged: _loadGlobalData,
        onOpenAddReminder: _showNewTaskBottomSheet,
      ),
    );
  }

  // --- Cloud Sync Bottom Sheet (Drop-up Drawer) ---

  void _showCloudSyncSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CloudSyncModalSheet(
        onSyncCompleted: _loadGlobalData,
      ),
    );
  }

  // --- Subject Filter Bottom Sheet ---

  void _showSubjectFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SubjectFilterModalSheet(
        subjects: _availableSubjects,
        selectedSubject: _selectedSubject,
        onSubjectSelected: (subj) {
          setState(() => _selectedSubject = subj);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 20,
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
            if (_currentNavIndex == 0 && _showAppBarPacingRing) ...[
              const SizedBox(width: 8),
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
            ],
          ],
        ),
        actions: [
          // Jump to Today action (appears only when viewing past/future dates)
          if (!_isCurrentDateToday) ...[
            InkWell(
              onTap: () {
                setState(() => _currentDate = DateTime.now());
                _loadGlobalData();
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.today_rounded, size: 14, color: googleBlue),
                    SizedBox(width: 4),
                    Text(
                      'Today',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleBlue),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],

          // Minimal Date Picker calendar button
          IconButton(
            icon: const Icon(Icons.event_outlined, size: 21, color: googleTextPrimary),
            tooltip: 'Select Date',
            onPressed: _pickDate,
          ),

          // Cloud Sync button (Hugging Face sync drop-up drawer)
          IconButton(
            icon: const Icon(Icons.cloud_sync_outlined, size: 22, color: googleTextPrimary),
            tooltip: 'Cloud Sync',
            onPressed: _showCloudSyncSheet,
          ),

          // Google Bell Icon with Live Badge Dot for Alerts & Reminders
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded, size: 22, color: googleTextPrimary),
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
            onJumpToToday: () {
              setState(() => _currentDate = DateTime.now());
              _loadGlobalData();
            },
            onOpenTimetable: () => setState(() => _currentNavIndex = 1),
          ),
          TimetableTab(
            onDataChanged: _loadGlobalData,
            selectedSubject: _selectedSubject,
            onOpenFilter: _showSubjectFilterSheet,
          ),
          RevisitTab(
            onDataChanged: _loadGlobalData,
            selectedSubject: _selectedSubject,
            onOpenFilter: _showSubjectFilterSheet,
          ),
          QuizzesTab(
            onDataChanged: _loadGlobalData,
            selectedSubject: _selectedSubject,
            onOpenFilter: _showSubjectFilterSheet,
          ),
        ],
      ),

      // Quick "+" Floating Action Button (Google Tasks style center-docked)
      floatingActionButton: FloatingActionButton(
        elevation: 3.0,
        backgroundColor: Colors.white,
        foregroundColor: googleBlue,
        onPressed: _showNewTaskBottomSheet,
        tooltip: 'New Task / Reminder',
        child: const Icon(Icons.add_rounded, size: 28),
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
            _buildNavItem(0, Icons.access_time_rounded, 'Today', 0),
            _buildNavItem(1, Icons.calendar_month_outlined, 'Timetable', 0),
            const SizedBox(width: 44), // FAB gap
            _buildNavItem(2, Icons.replay_rounded, 'Revisit', _badgeCounts['due_revisits'] ?? 0),
            _buildNavItem(3, Icons.check_circle_outline_rounded, 'Quizzes', _badgeCounts['pending_quizzes'] ?? 0),
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
