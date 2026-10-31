import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/widgets/google_checkbox.dart';
import 'package:url_launcher/url_launcher.dart';

class TodayTab extends StatefulWidget {
  final DateTime currentDate;
  final VoidCallback onDataChanged;
  final ScrollController scrollController;

  const TodayTab({
    Key? key,
    required this.currentDate,
    required this.onDataChanged,
    required this.scrollController,
  }) : super(key: key);

  @override
  _TodayTabState createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  late PageController _pageController;
  int _selectedPageIndex = 0;

  Map<String, dynamic> _pacing = {
    'target_hours': 8.0,
    'watched_hours': 0.0,
    'lecture_count': 0,
    'completed_count': 0,
    'revisit_count': 0,
    'quiz_count': 0,
  };

  List<Map<String, dynamic>> _lectures = [];
  List<Map<String, dynamic>> _dueRevisits = [];
  List<Map<String, dynamic>> _todayQuizzes = [];
  bool _isLoading = true;
  bool _isCompletedExpanded = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadData();
  }

  @override
  void didUpdateWidget(covariant TodayTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentDate != widget.currentDate) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final pacing = await DatabaseService.instance.getDailyPacing(widget.currentDate);
    final lectures = await DatabaseService.instance.getLecturesForDate(widget.currentDate);
    final revisits = await DatabaseService.instance.getDueRevisitsForDate(widget.currentDate);
    final quizzes = await DatabaseService.instance.getScheduledQuizzesForDate(widget.currentDate);

    if (mounted) {
      setState(() {
        _pacing = pacing;
        _lectures = lectures;
        _dueRevisits = revisits;
        _todayQuizzes = quizzes;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleLecture(Map<String, dynamic> lec, bool completed) async {
    final id = lec['id'] as int;
    final dur = (lec['duration_hours'] as num?)?.toDouble() ?? 1.0;
    await DatabaseService.instance.toggleLectureStatus(id, completed, dur, widget.currentDate);
    await _loadData();
    widget.onDataChanged();
  }

  Future<void> _toggleRevisit(Map<String, dynamic> rev, bool done) async {
    final id = rev['id'] as int;
    await DatabaseService.instance.toggleRevisitStatus(id, done);
    await _loadData();
    widget.onDataChanged();
  }

  Future<void> _toggleQuiz(Map<String, dynamic> q, bool done) async {
    final id = q['id'] as int;
    await DatabaseService.instance.toggleQuizStatus(id, done);
    await _loadData();
    widget.onDataChanged();
  }

  void _showLectureDetails(Map<String, dynamic> lec) {
    final title = lec['details'] ?? lec['topic'] ?? 'Lecture';
    final topic = lec['topic'] ?? '';
    final session = lec['session_block'] ?? 'General Session';
    final dur = (lec['duration_hours'] as num?)?.toDouble() ?? 1.0;
    final status = lec['status'] ?? 'PENDING';
    final completedAt = lec['completed_at'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: googleTextPrimary,
                        height: 1.3,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: status == 'COMPLETED' ? const Color(0xFFE6F4EA) : const Color(0xFFFFF0D4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: status == 'COMPLETED' ? googleGreen : googleAmber,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (topic.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.bookmark_border, size: 18, color: googleBlue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        topic,
                        style: const TextStyle(fontSize: 13, color: googleTextSecondary, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  const Icon(Icons.schedule, size: 18, color: googleBlue),
                  const SizedBox(width: 8),
                  Text(
                    '$session • ${dur.toStringAsFixed(1)} hours',
                    style: const TextStyle(fontSize: 13, color: googleTextSecondary),
                  ),
                ],
              ),
              if (completedAt != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 18, color: googleGreen),
                    const SizedBox(width: 8),
                    Text(
                      'Completed on $completedAt',
                      style: const TextStyle(fontSize: 12, color: googleGreen),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: googleBlue,
                    side: const BorderSide(color: googleBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: googleBlue));
    }

    final target = (_pacing['target_hours'] as num?)?.toDouble() ?? 8.0;
    final watched = (_pacing['watched_hours'] as num?)?.toDouble() ?? 0.0;
    final progress = target > 0 ? (watched / target).clamp(0.0, 1.0) : 0.0;
    final remaining = (target - watched).clamp(0.0, target);

    return ListView(
      controller: widget.scrollController,
      padding: EdgeInsets.zero,
      children: [
        // 1. Google Pacing Header (No Box Card — Flat on canvas)
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Text(
                    'DAILY LECTURE TARGET',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: googleTextSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${watched.toStringAsFixed(1)} ',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: googleTextPrimary,
                          ),
                        ),
                        TextSpan(
                          text: '/ ${target.toStringAsFixed(1)}h',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: googleTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFF1F3F4),
                  valueColor: const AlwaysStoppedAnimation<Color>(googleBlue),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Consolidated pace: ${remaining.toStringAsFixed(1)}h remaining today',
                    style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                  ),
                  const Text(
                    'Starts 08:00 AM',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: googleTextSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. Sliding Pill Segmented Indicator Tabs
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F4),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                _buildPillTab(0, 'Schedule', _lectures.length),
                _buildPillTab(1, 'Revisits', _dueRevisits.length),
                _buildPillTab(2, 'Quizzes', _todayQuizzes.length),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 1, color: googleHairline),

        // 3. Carousel View using AnimatedSize & IndexedStack (preserves scroll and layout smoothly)
        IndexedStack(
          index: _selectedPageIndex,
          children: [
            _buildScheduleView(),
            _buildRevisitsView(),
            _buildQuizzesView(),
          ],
        ),
      ],
    );
  }

  Widget _buildPillTab(int index, String label, int count) {
    final isSelected = _selectedPageIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _selectedPageIndex = index);
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
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? googleBlue : googleTextSecondary,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? googleBlue : const Color(0xFFDADCE0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 10,
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

  // --- Schedule Flat View ---

  Widget _buildScheduleView() {
    if (_lectures.isEmpty) {
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: const Center(
          child: Text(
            'No lectures scheduled for this date.',
            style: TextStyle(fontSize: 14, color: googleTextSecondary),
          ),
        ),
      );
    }

    final pending = _lectures.where((l) => (l['status'] as String?)?.toUpperCase() != 'COMPLETED').toList();
    final completed = _lectures.where((l) => (l['status'] as String?)?.toUpperCase() == 'COMPLETED').toList();

    // Group pending by session_block
    final groups = <String, List<Map<String, dynamic>>>{};
    for (var l in pending) {
      final block = (l['session_block'] as String?) ?? 'Scheduled Sessions';
      groups.putIfAbsent(block, () => []).add(l);
    }

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...groups.entries.map((entry) {
            final blockTitle = entry.key;
            final items = entry.value;
            final totalHours = items.fold<double>(0.0, (sum, l) => sum + ((l['duration_hours'] as num?)?.toDouble() ?? 1.0));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        blockTitle.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: googleTextSecondary,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        '${totalHours.toStringAsFixed(1)}h total',
                        style: const TextStyle(fontSize: 11, color: googleTextSecondary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                ...items.map((lec) => _buildTaskRow(lec, isCompleted: false)),
              ],
            );
          }),

          // Completed Section Accordion
          if (completed.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 1, color: googleHairline),
            InkWell(
              onTap: () {
                setState(() => _isCompletedExpanded = !_isCompletedExpanded);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      _isCompletedExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                      size: 20,
                      color: googleTextSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Completed (${completed.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: googleTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isCompletedExpanded)
              ...completed.map((lec) => _buildTaskRow(lec, isCompleted: true)),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildTaskRow(Map<String, dynamic> lec, {required bool isCompleted}) {
    final title = lec['details'] ?? lec['topic'] ?? 'Lecture';
    final topic = lec['topic'] ?? '';
    final dur = (lec['duration_hours'] as num?)?.toDouble() ?? 1.0;

    return InkWell(
      onTap: () => _showLectureDetails(lec),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GoogleCheckbox(
                  value: isCompleted,
                  onChanged: (val) => _toggleLecture(lec, val),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isCompleted ? googleTextSecondary : googleTextPrimary,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        topic,
                        style: TextStyle(
                          fontSize: 12,
                          color: isCompleted ? const Color(0xFF9AA0A6) : googleTextSecondary,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${dur.toStringAsFixed(1)}h',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: googleTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 56),
            child: Divider(height: 1, thickness: 1, color: googleHairline),
          ),
        ],
      ),
    );
  }

  // --- Revisits Flat View ---

  Widget _buildRevisitsView() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // GateOverflow DPP Protocol Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: const Color(0xFFF8FAFD),
            child: Row(
              children: [
                const Icon(Icons.bolt, size: 18, color: googleAmber),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Active Recall & DPP Protocol',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: googleTextPrimary),
                  ),
                ),
                InkWell(
                  onTap: () async {
                    final uri = Uri.parse('https://gateoverflow.in');
                    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  child: const Text(
                    'GO DPPs ↗',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: googleHairline),

          if (_dueRevisits.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
              child: const Center(
                child: Text(
                  'No revisits due for this date. Great job!',
                  style: TextStyle(fontSize: 14, color: googleTextSecondary),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'DUE TODAY FOR RECALL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: googleTextSecondary,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Text(
                    '${_dueRevisits.length} checkpoints',
                    style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                  ),
                ],
              ),
            ),
            ..._dueRevisits.map((rev) {
              final isDone = (rev['status'] as String?)?.toUpperCase() == 'DONE';
              final stage = rev['stage'] ?? 'Recall';
              final dur = rev['duration_mins'] ?? 25;
              final topic = rev['topic'] ?? '';

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GoogleCheckbox(
                          value: isDone,
                          onChanged: (val) => _toggleRevisit(rev, val),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                topic,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isDone ? googleTextSecondary : googleTextPrimary,
                                  decoration: isDone ? TextDecoration.lineThrough : null,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F3F4),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      stage,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: googleTextPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$dur mins active recall',
                                    style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 56),
                    child: Divider(height: 1, thickness: 1, color: googleHairline),
                  ),
                ],
              );
            }),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // --- Quizzes Flat View ---

  Widget _buildQuizzesView() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_todayQuizzes.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
              child: const Center(
                child: Text(
                  'No quizzes scheduled for this date.',
                  style: TextStyle(fontSize: 14, color: googleTextSecondary),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'ASSESSMENTS & QUIZZES (${_todayQuizzes.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: googleTextSecondary,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ..._todayQuizzes.map((q) {
              final isDone = (q['status'] as String?)?.toUpperCase() == 'COMPLETED';
              final title = q['title'] ?? 'Quiz';
              final marks = q['total_marks'] ?? 25;
              final dur = q['duration_mins'] ?? 45;
              final syllabus = q['syllabus_topics'] ?? '';
              final actionUrl = q['action_url'] as String?;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GoogleCheckbox(
                          value: isDone,
                          onChanged: (val) => _toggleQuiz(q, val),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDone ? googleTextSecondary : googleTextPrimary,
                                  decoration: isDone ? TextDecoration.lineThrough : null,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$dur mins • $marks Marks ${syllabus.isNotEmpty ? "• $syllabus" : ""}',
                                style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (actionUrl != null && actionUrl.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () async {
                                    final uri = Uri.parse(actionUrl);
                                    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                                  },
                                  child: const Text(
                                    'Start Quiz ↗',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 56),
                    child: Divider(height: 1, thickness: 1, color: googleHairline),
                  ),
                ],
              );
            }),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
