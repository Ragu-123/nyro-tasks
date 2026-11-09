import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tasks/pages/tabs/today_tab.dart';
import 'package:tasks/pages/tabs/timetable_tab.dart';
import 'package:tasks/pages/tabs/revisit_tab.dart';
import 'package:tasks/pages/tabs/quizzes_tab.dart';
import 'package:tasks/pages/cloud_sync/cloud_sync_page.dart';
import 'package:tasks/pages/settings/settings_page.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/services/notification_service.dart';
import 'package:tasks/services/desktop_log_server_service.dart';
import 'package:tasks/services/app_update_service.dart';
import 'package:tasks/widgets/alerts_modal_sheet.dart';
import 'package:tasks/widgets/subject_filter_modal_sheet.dart';
import 'package:tasks/widgets/notifications_history_sheet.dart';
import 'package:tasks/widgets/add_mistake_modal_sheet.dart';
import 'package:tasks/widgets/top_banner_notification.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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

  StreamSubscription? _serverSubscription;

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
    _initBackgroundServices();
  }

  Future<void> _initBackgroundServices() async {
    // Listen for incoming mistake logs from laptop over LAN
    _serverSubscription = DesktopLogServerService.instance.onMistakeReceived.listen((data) {
      final subject = data['subject'] ?? 'General';
      final topic = data['topic'] ?? 'Question';
      if (mounted) {
        TopBanner.show(
          context,
          title: 'Laptop Mistake Logged',
          message: '$subject • $topic',
          icon: Icons.laptop_chromebook_rounded,
          color: googleAmber,
        );
        _loadGlobalData();
      }
    });

    // Auto-start desktop log server if configured
    final autoStart = await DatabaseService.instance.getAutoStartServer();
    if (autoStart && !DesktopLogServerService.instance.isRunning) {
      await DesktopLogServerService.instance.startServer();
    }

    // Auto-check GitHub updates if configured
    final autoCheck = await DatabaseService.instance.getAutoCheckUpdates();
    if (autoCheck) {
      try {
        final release = await AppUpdateService().checkForUpdate();
        if (release != null && release.isNewerThan(AppUpdateService.currentVersion) && mounted) {
          TopBanner.show(
            context,
            title: 'Update Available: ${release.tagName}',
            message: 'Tap here to download and install.',
            icon: Icons.system_update_rounded,
            color: googleGreen,
            duration: const Duration(seconds: 6),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage(initialSection: 'updates')),
              );
            },
          );
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _serverSubscription?.cancel();
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

  // --- Multi-Type Quick Add Bottom Sheet (Reminder, Schedule, Quizzes, Revisit, Mistake) ---

  void _showNewTaskBottomSheet({String initialType = 'Reminder'}) {
    String selectedType = initialType;

    // Common fields
    final titleController = TextEditingController();
    DateTime selectedDate = _currentDate;
    TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);
    bool hasTime = false;

    // Schedule specific fields
    final scheduleSubjectController = TextEditingController();
    final scheduleLectureController = TextEditingController();
    String? selectedDropdownSubject;
    bool isAddingNewSubject = false;
    double scheduleDurationHours = 1.5;
    String sessionBlock = 'Morning Block';

    // Quiz specific fields
    final quizTitleController = TextEditingController();
    final quizSubjectController = TextEditingController();
    final quizSyllabusController = TextEditingController();
    String? selectedQuizDropdownSubject;
    bool isAddingNewQuizSubject = false;
    String quizType = 'WEEKLY_QUIZ';
    int quizDurationMins = 45;
    int quizTotalMarks = 25;

    // Revisit specific fields
    final revisitTopicController = TextEditingController();
    String revisitStage = 'Day 1 (24h)';
    int revisitDurationMins = 20;

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
            final availableExistingSubjects = _availableSubjects.where((s) => s != 'All Subjects').toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 16,
                left: 20,
                right: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
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
                    const SizedBox(height: 14),

                    // Title header based on type
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          selectedType == 'Schedule'
                              ? 'Schedule Lecture'
                              : (selectedType == 'Quizzes'
                                  ? 'Schedule Quiz / Test'
                                  : (selectedType == 'Revisit'
                                      ? 'Add Revisit Checkpoint'
                                      : 'New Task / Reminder')),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            selectedType.toUpperCase(),
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleBlue),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // --- 1. REMINDER / TASK FORM ---
                    if (selectedType == 'Reminder') ...[
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        decoration: const InputDecoration(
                          hintText: 'What study task would you like to remind?',
                          hintStyle: TextStyle(fontSize: 14, color: googleTextSecondary),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ]

                    // --- 2. SCHEDULE LECTURE FORM ---
                    else if (selectedType == 'Schedule') ...[
                      // Subject selection (Dropdown if subjects exist, otherwise text field)
                      if (availableExistingSubjects.isNotEmpty && !isAddingNewSubject) ...[
                        const Text('SUBJECT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                        const SizedBox(height: 4),
                        Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFD),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: googleBorder),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedDropdownSubject ?? availableExistingSubjects.first,
                              isExpanded: true,
                              icon: const Icon(Icons.arrow_drop_down_rounded, color: googleBlue),
                              style: const TextStyle(fontSize: 13, color: googleTextPrimary, fontWeight: FontWeight.w600),
                              items: [
                                ...availableExistingSubjects.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                                const DropdownMenuItem(value: '__NEW__', child: Text('➕ Enter New Subject...', style: TextStyle(color: googleBlue))),
                              ],
                              onChanged: (val) {
                                if (val == '__NEW__') {
                                  setSheetState(() => isAddingNewSubject = true);
                                } else if (val != null) {
                                  setSheetState(() => selectedDropdownSubject = val);
                                }
                              },
                            ),
                          ),
                        ),
                      ] else ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('NEW SUBJECT NAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                            if (availableExistingSubjects.isNotEmpty)
                              InkWell(
                                onTap: () => setSheetState(() => isAddingNewSubject = false),
                                child: const Text('Pick from existing', style: TextStyle(fontSize: 10, color: googleBlue)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: scheduleSubjectController,
                          autofocus: true,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'e.g. Calculus and Optimization',
                            hintStyle: const TextStyle(fontSize: 13, color: googleBorder),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFD),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),

                      // Lecture Title / Topic
                      const Text('LECTURE TITLE / TOPIC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: scheduleLectureController,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. Lecture 2: Evaluating Limits & Continuity',
                          hintStyle: const TextStyle(fontSize: 13, color: googleBorder),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFD),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Session Block & Duration
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('SESSION BLOCK', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                                const SizedBox(height: 4),
                                Container(
                                  height: 44,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFD),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: googleBorder),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: sessionBlock,
                                      isExpanded: true,
                                      style: const TextStyle(fontSize: 12, color: googleTextPrimary, fontWeight: FontWeight.w600),
                                      items: const [
                                        DropdownMenuItem(value: 'Morning Block', child: Text('Morning Block')),
                                        DropdownMenuItem(value: 'Afternoon Block', child: Text('Afternoon Block')),
                                        DropdownMenuItem(value: 'Evening Block', child: Text('Evening Block')),
                                        DropdownMenuItem(value: 'Night Block', child: Text('Night Block')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setSheetState(() => sessionBlock = val);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('TOTAL HOURS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                              const SizedBox(height: 4),
                              Container(
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFD),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: googleBorder),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_rounded, size: 16),
                                      onPressed: () {
                                        if (scheduleDurationHours > 0.5) {
                                          setSheetState(() => scheduleDurationHours -= 0.5);
                                        }
                                      },
                                    ),
                                    Text(
                                      '${scheduleDurationHours.toStringAsFixed(1)}h',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleBlue),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_rounded, size: 16),
                                      onPressed: () {
                                        if (scheduleDurationHours < 8.0) {
                                          setSheetState(() => scheduleDurationHours += 0.5);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '✓ Spaced repetition recall checkpoints (Day 1, 4, 7, 14, 30) will be generated automatically.',
                        style: TextStyle(fontSize: 10.5, color: googleGreen, fontWeight: FontWeight.w500),
                      ),
                    ]

                    // --- 3. QUIZZES / TEST SERIES FORM ---
                    else if (selectedType == 'Quizzes') ...[
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Weekly Quiz', style: TextStyle(fontSize: 11)),
                            selected: quizType == 'WEEKLY_QUIZ',
                            onSelected: (v) => setSheetState(() => quizType = 'WEEKLY_QUIZ'),
                            selectedColor: const Color(0xFFE8F0FE),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Test Series Mocks', style: TextStyle(fontSize: 11)),
                            selected: quizType == 'TEST_SERIES',
                            onSelected: (v) => setSheetState(() => quizType = 'TEST_SERIES'),
                            selectedColor: const Color(0xFFE8F0FE),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      const Text('QUIZ TITLE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: quizTitleController,
                        autofocus: true,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. Weekly Quiz 2: Limits & Continuity',
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFD),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Quiz Subject selection (Dropdown if subjects exist, otherwise text field)
                      if (availableExistingSubjects.isNotEmpty && !isAddingNewQuizSubject) ...[
                        const Text('SUBJECT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                        const SizedBox(height: 4),
                        Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFD),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: googleBorder),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedQuizDropdownSubject ?? availableExistingSubjects.first,
                              isExpanded: true,
                              icon: const Icon(Icons.arrow_drop_down_rounded, color: googleBlue),
                              style: const TextStyle(fontSize: 13, color: googleTextPrimary, fontWeight: FontWeight.w600),
                              items: [
                                ...availableExistingSubjects.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                                const DropdownMenuItem(value: '__NEW__', child: Text('➕ Enter New Subject...', style: TextStyle(color: googleBlue))),
                              ],
                              onChanged: (val) {
                                if (val == '__NEW__') {
                                  setSheetState(() => isAddingNewQuizSubject = true);
                                } else if (val != null) {
                                  setSheetState(() => selectedQuizDropdownSubject = val);
                                }
                              },
                            ),
                          ),
                        ),
                      ] else ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('SUBJECT NAME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                            if (availableExistingSubjects.isNotEmpty)
                              InkWell(
                                onTap: () => setSheetState(() => isAddingNewQuizSubject = false),
                                child: const Text('Pick from existing', style: TextStyle(fontSize: 10, color: googleBlue)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: quizSubjectController,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'e.g. Calculus and Optimization',
                            hintStyle: const TextStyle(fontSize: 13, color: googleBorder),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFD),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('DURATION (MINS)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                                const SizedBox(height: 4),
                                TextField(
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => quizDurationMins = int.tryParse(v) ?? 45,
                                  decoration: InputDecoration(
                                    hintText: '45',
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFD),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('TOTAL MARKS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                                const SizedBox(height: 4),
                                TextField(
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => quizTotalMarks = int.tryParse(v) ?? 25,
                                  decoration: InputDecoration(
                                    hintText: '25',
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFD),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      const Text('SYLLABUS TOPICS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: quizSyllabusController,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'e.g. Limits, Continuity, L-Hopital, Squeeze theorem',
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFD),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ]

                    // --- 4. REVISIT FORM ---
                    else if (selectedType == 'Revisit') ...[
                      const Text('CONCEPT / TOPIC TO REVISIT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: revisitTopicController,
                        autofocus: true,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. Calculus • L-Hopital Indeterminate Forms',
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFD),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('STAGE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                                const SizedBox(height: 4),
                                Container(
                                  height: 44,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFD),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: googleBorder),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: revisitStage,
                                      isExpanded: true,
                                      style: const TextStyle(fontSize: 12, color: googleTextPrimary, fontWeight: FontWeight.w600),
                                      items: const [
                                        DropdownMenuItem(value: 'Day 1 (24h)', child: Text('Day 1 (24h)')),
                                        DropdownMenuItem(value: 'Day 4', child: Text('Day 4')),
                                        DropdownMenuItem(value: 'Day 7', child: Text('Day 7')),
                                        DropdownMenuItem(value: 'Day 14', child: Text('Day 14')),
                                        DropdownMenuItem(value: 'Day 30', child: Text('Day 30')),
                                        DropdownMenuItem(value: 'Custom Recall', child: Text('Custom Recall')),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setSheetState(() => revisitStage = val);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('DURATION (MINS)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                                const SizedBox(height: 4),
                                TextField(
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => revisitDurationMins = int.tryParse(v) ?? 20,
                                  decoration: InputDecoration(
                                    hintText: '20',
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFD),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: googleBorder)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Date, Time Chips & Multi-type Dropdown
                    Row(
                      children: [
                        // Date Chip
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
                        const SizedBox(width: 6),

                        // Time Chip (for Reminders)
                        if (selectedType == 'Reminder') ...[
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
                          const SizedBox(width: 6),
                        ],

                        // DROPDOWN MENU NEAR SET TIME CHIP (task/reminder, schedule, quizzes, revisit, mistake)
                        PopupMenuButton<String>(
                          tooltip: 'Entry Type',
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          color: Colors.white,
                          onSelected: (val) {
                            if (val == 'Mistake') {
                              Navigator.pop(context);
                              showAddMistakeModalSheet(
                                context,
                                onSaved: _loadGlobalData,
                                initialSubject: _selectedSubject,
                                availableSubjects: _availableSubjects,
                              );
                            } else {
                              setSheetState(() => selectedType = val);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'Reminder',
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_outline_rounded, size: 16, color: googleBlue),
                                  SizedBox(width: 8),
                                  Text('Task / Reminder', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'Schedule',
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_month_outlined, size: 16, color: googleGreen),
                                  SizedBox(width: 8),
                                  Text('Schedule (Lecture)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'Quizzes',
                              child: Row(
                                children: [
                                  Icon(Icons.quiz_outlined, size: 16, color: googleAmber),
                                  SizedBox(width: 8),
                                  Text('Quizzes / Tests', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'Revisit',
                              child: Row(
                                children: [
                                  Icon(Icons.replay_rounded, size: 16, color: googleBlue),
                                  SizedBox(width: 8),
                                  Text('Revisit Checkpoint', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'Mistake',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_note_rounded, size: 16, color: googleRed),
                                  SizedBox(width: 8),
                                  Text('Mistake Record', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F4F9),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.add_circle_outline_rounded, size: 14, color: googleBlue),
                                const SizedBox(width: 4),
                                Text(
                                  selectedType,
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: googleBlue),
                                ),
                                const Icon(Icons.arrow_drop_down_rounded, size: 16, color: googleBlue),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Action Buttons (Cancel / Save)
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
                            // 1. SAVE REMINDER
                            if (selectedType == 'Reminder') {
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
                                  if (scheduled.isBefore(now)) {
                                    scheduled = now.add(const Duration(seconds: 10));
                                  }
                                } else {
                                  if (isSelectedToday) {
                                    scheduled = now.add(const Duration(minutes: 15));
                                  } else {
                                    scheduled = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 9, 0);
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
                                  TopBanner.show(
                                    context,
                                    title: 'Reminder Scheduled',
                                    message: 'Set for $formattedAlertTime',
                                    icon: Icons.check_circle_outline_rounded,
                                    color: googleBlue,
                                  );
                                }
                              }
                            }

                            // 2. SAVE SCHEDULE
                            else if (selectedType == 'Schedule') {
                              String subj = (availableExistingSubjects.isNotEmpty && !isAddingNewSubject)
                                  ? (selectedDropdownSubject ?? availableExistingSubjects.first)
                                  : scheduleSubjectController.text.trim();
                              final lecName = scheduleLectureController.text.trim();

                              if (subj.isEmpty) subj = 'Engineering Mathematics';
                              if (lecName.isNotEmpty) {
                                await DatabaseService.instance.insertScheduledLecture(
                                  subject: subj,
                                  lectureName: lecName,
                                  date: selectedDate,
                                  durationHours: scheduleDurationHours,
                                  sessionBlock: sessionBlock,
                                );
                                _loadGlobalData();

                                if (mounted) {
                                  TopBanner.show(
                                    context,
                                    title: 'Schedule Created',
                                    message: 'Lecture & 5 spaced revisits scheduled.',
                                    icon: Icons.calendar_month_outlined,
                                    color: googleGreen,
                                  );
                                }
                              }
                            }

                            // 3. SAVE QUIZ
                            else if (selectedType == 'Quizzes') {
                              final title = quizTitleController.text.trim();
                              String subj = (availableExistingSubjects.isNotEmpty && !isAddingNewQuizSubject)
                                  ? (selectedQuizDropdownSubject ?? availableExistingSubjects.first)
                                  : quizSubjectController.text.trim();
                              if (subj.isEmpty) subj = 'Engineering Mathematics';

                              if (title.isNotEmpty) {
                                await DatabaseService.instance.saveCustomSubject(subj);
                                await DatabaseService.instance.insertQuiz(
                                  quizType: quizType,
                                  title: title,
                                  subject: subj,
                                  date: selectedDate,
                                  durationMins: quizDurationMins,
                                  totalMarks: quizTotalMarks,
                                  syllabusTopics: quizSyllabusController.text.trim(),
                                );
                                _loadGlobalData();

                                if (mounted) {
                                  TopBanner.show(
                                    context,
                                    title: 'Quiz Scheduled',
                                    message: '$title scheduled for $formattedDate.',
                                    icon: Icons.quiz_outlined,
                                    color: googleAmber,
                                  );
                                }
                              }
                            }

                            // 4. SAVE REVISIT
                            else if (selectedType == 'Revisit') {
                              final top = revisitTopicController.text.trim();
                              if (top.isNotEmpty) {
                                await DatabaseService.instance.insertCustomRevisit(
                                  topic: top,
                                  stage: revisitStage,
                                  dueDate: selectedDate,
                                  durationMins: revisitDurationMins,
                                );
                                _loadGlobalData();

                                if (mounted) {
                                  TopBanner.show(
                                    context,
                                    title: 'Revisit Added',
                                    message: '$top scheduled for recall.',
                                    icon: Icons.replay_rounded,
                                    color: googleBlue,
                                  );
                                }
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

  // --- Notifications History Sheet ---

  void _showNotificationsHistorySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationsHistorySheet(),
    );
  }

  // --- Navigation Helpers ---

  void _openCloudSyncPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CloudSyncPage(onDataChanged: _loadGlobalData),
      ),
    );
  }

  void _openSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }

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

  // --- Full Side Navigation Drawer ---

  Widget _buildSideNavigationDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: googleHairline)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: googleBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.check_rounded, color: googleBlue, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NYRO Tasks',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: googleTextPrimary),
                        ),
                        Text(
                          'GATE Study Copilot • v1.0.0',
                          style: TextStyle(fontSize: 11, color: googleTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Navigation Items (Top Section)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_sync_outlined, color: googleBlue, size: 22),
                    title: const Text('Cloud Sync', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: googleTextPrimary)),
                    subtitle: const Text('Backup & restore DB to Hugging Face', style: TextStyle(fontSize: 11, color: googleTextSecondary)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () {
                      Navigator.pop(context);
                      _openCloudSyncPage();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_none_rounded, color: googleAmber, size: 22),
                    title: const Text('Alerts & Routines', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: googleTextPrimary)),
                    subtitle: const Text('Morning brief, recall shield, and timers', style: TextStyle(fontSize: 11, color: googleTextSecondary)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () {
                      Navigator.pop(context);
                      _showAlertsSheet();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.event_outlined, color: googleBlue, size: 22),
                    title: const Text('Jump to Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: googleTextPrimary)),
                    subtitle: const Text('Quick calendar date navigation', style: TextStyle(fontSize: 11, color: googleTextSecondary)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () {
                      Navigator.pop(context);
                      _pickDate();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.mark_chat_unread_outlined, color: Colors.deepPurple, size: 22),
                    title: const Text('Notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: googleTextPrimary)),
                    subtitle: const Text('Test blunder logs & study alerts history', style: TextStyle(fontSize: 11, color: googleTextSecondary)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () {
                      Navigator.pop(context);
                      _showNotificationsHistorySheet();
                    },
                  ),
                ],
              ),
            ),

            // Bottom Settings Section
            const Divider(height: 1, thickness: 1, color: googleHairline),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.settings_outlined, color: googleTextPrimary, size: 22),
                title: const Text('Settings', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: googleTextPrimary)),
                subtitle: const Text('Cloud tokens, log server, updates & schema', style: TextStyle(fontSize: 11, color: googleTextSecondary)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  Navigator.pop(context);
                  _openSettingsPage();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      endDrawer: _buildSideNavigationDrawer(),
      appBar: AppBar(
        titleSpacing: 4,
        leading: IconButton(
          icon: const Icon(Icons.calendar_month_outlined, color: googleBlue, size: 22),
          tooltip: 'Jump to Date',
          onPressed: _pickDate,
        ),
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

          // Three horizontal bars menu icon to open Side Navigation Drawer
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.menu_rounded, size: 24, color: googleTextPrimary),
                if ((_badgeCounts['total_due'] ?? 0) > 0)
                  Positioned(
                    top: -1,
                    right: -1,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: googleAmber,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'Navigation Menu',
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
          const SizedBox(width: 6),
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
            onJumpToDate: _pickDate,
            onOpenCloudSync: _openCloudSyncPage,
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
        onPressed: () => _showNewTaskBottomSheet(),
        tooltip: 'New Task / Schedule / Quiz',
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
