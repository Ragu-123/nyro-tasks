import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/utils/url_helper.dart';
import 'package:tasks/widgets/add_mistake_modal_sheet.dart';
import 'package:tasks/widgets/google_checkbox.dart';

enum QuizSortOption {
  dateAsc, // Earliest Date first (Default)
  dateDesc, // Latest Date first
  subjectAsc, // Subject (A-Z)
  marksDesc, // Marks (High to Low)
  durationAsc, // Duration (Shortest first)
}

class QuizzesTab extends StatefulWidget {
  final VoidCallback onDataChanged;
  final String selectedSubject;
  final VoidCallback? onOpenFilter;

  const QuizzesTab({
    Key? key,
    required this.onDataChanged,
    this.selectedSubject = 'All Subjects',
    this.onOpenFilter,
  }) : super(key: key);

  @override
  _QuizzesTabState createState() => _QuizzesTabState();
}

class _QuizzesTabState extends State<QuizzesTab> {
  int _activeTypeIndex = 0; // 0: WEEKLY_QUIZ, 1: TEST_SERIES
  List<Map<String, dynamic>> _quizzes = [];
  Map<int, int> _trapsCounts = {};
  bool _isLoading = true;
  bool _isCompletedExpanded = false;
  QuizSortOption _sortOption = QuizSortOption.dateAsc; // Default sorted by Date

  @override
  void initState() {
    super.initState();
    _loadQuizzes();
  }

  @override
  void didUpdateWidget(covariant QuizzesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSubject != widget.selectedSubject) {
      _loadQuizzes();
    }
  }

  static final DateFormat _quizDateFormat1 = DateFormat('dd MMM yyyy');
  static final DateFormat _quizDateFormat2 = DateFormat('d MMM yyyy');

  DateTime _parseQuizDate(String? d) {
    if (d == null || d.trim().isEmpty) return DateTime(2099);
    final clean = d.trim();
    try {
      return _quizDateFormat1.parse(clean);
    } catch (_) {
      try {
        return _quizDateFormat2.parse(clean);
      } catch (_) {
        try {
          return DateTime.parse(clean);
        } catch (_) {
          return DateTime(2099);
        }
      }
    }
  }

  List<Map<String, dynamic>> _applySorting(List<Map<String, dynamic>> items) {
    final list = List<Map<String, dynamic>>.from(items);
    switch (_sortOption) {
      case QuizSortOption.dateAsc:
        list.sort((a, b) {
          final dA = _parseQuizDate(a['date_str']);
          final dB = _parseQuizDate(b['date_str']);
          final cmp = dA.compareTo(dB);
          return cmp != 0 ? cmp : (a['id'] as int).compareTo(b['id'] as int);
        });
        break;
      case QuizSortOption.dateDesc:
        list.sort((a, b) {
          final dA = _parseQuizDate(a['date_str']);
          final dB = _parseQuizDate(b['date_str']);
          final cmp = dB.compareTo(dA);
          return cmp != 0 ? cmp : (b['id'] as int).compareTo(a['id'] as int);
        });
        break;
      case QuizSortOption.subjectAsc:
        list.sort((a, b) {
          final sA = (a['subject'] ?? '').toString().toLowerCase();
          final sB = (b['subject'] ?? '').toString().toLowerCase();
          return sA.compareTo(sB);
        });
        break;
      case QuizSortOption.marksDesc:
        list.sort((a, b) {
          final mA = (a['total_marks'] as num?)?.toInt() ?? 0;
          final mB = (b['total_marks'] as num?)?.toInt() ?? 0;
          return mB.compareTo(mA);
        });
        break;
      case QuizSortOption.durationAsc:
        list.sort((a, b) {
          final dA = (a['duration_mins'] as num?)?.toInt() ?? 0;
          final dB = (b['duration_mins'] as num?)?.toInt() ?? 0;
          return dA.compareTo(dB);
        });
        break;
    }
    return list;
  }

  Future<void> _loadQuizzes() async {
    setState(() => _isLoading = true);
    try {
      final type = _activeTypeIndex == 0 ? 'WEEKLY_QUIZ' : 'TEST_SERIES';
      final items = await DatabaseService.instance.getQuizzesByType(type, subjectFilter: widget.selectedSubject);

      // Concurrently fetch mistake counts for all quizzes via Future.wait
      final countsList = await Future.wait(
        items.map((q) async {
          final title = (q['title'] ?? '').toString();
          final id = q['id'] as int;
          if (title.isEmpty) return MapEntry(id, 0);
          final subject = (q['subject'] ?? '').toString();
          final cnt = await DatabaseService.instance.getMistakeCountForQuiz(title, subject: subject);
          return MapEntry(id, cnt);
        }),
      );
      final counts = Map<int, int>.fromEntries(countsList);

      final sortedItems = _applySorting(items);

      if (mounted) {
        setState(() {
          _quizzes = sortedItems;
          _trapsCounts = counts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading quizzes tab: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleQuizStatus(Map<String, dynamic> q, bool done) async {
    final id = q['id'] as int;
    await DatabaseService.instance.toggleQuizStatus(id, done);
    await _loadQuizzes();
    widget.onDataChanged();
  }

  void _showSortAndFilterSheet() {
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
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Sort & Preferences',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: googleTextPrimary),
                        ),
                        if (widget.onOpenFilter != null)
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onOpenFilter!();
                            },
                            icon: const Icon(Icons.filter_list_rounded, size: 16, color: googleBlue),
                            label: const Text('Subject Filter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'SORT QUIZZES BY',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleTextSecondary, letterSpacing: 0.6),
                    ),
                    const SizedBox(height: 8),

                    _buildSortTile(
                      label: 'Date: Earliest First (Default)',
                      subtitle: 'Chronological test schedule order',
                      option: QuizSortOption.dateAsc,
                      icon: Icons.calendar_today_rounded,
                      setSheetState: setSheetState,
                    ),
                    _buildSortTile(
                      label: 'Date: Latest First',
                      subtitle: 'Most recently scheduled tests first',
                      option: QuizSortOption.dateDesc,
                      icon: Icons.history_rounded,
                      setSheetState: setSheetState,
                    ),
                    _buildSortTile(
                      label: 'Subject: A to Z',
                      subtitle: 'Alphabetical subject grouping',
                      option: QuizSortOption.subjectAsc,
                      icon: Icons.sort_by_alpha_rounded,
                      setSheetState: setSheetState,
                    ),
                    _buildSortTile(
                      label: 'Total Marks: High to Low',
                      subtitle: 'Full-length and high-weight mocks first',
                      option: QuizSortOption.marksDesc,
                      icon: Icons.score_outlined,
                      setSheetState: setSheetState,
                    ),
                    _buildSortTile(
                      label: 'Duration: Shortest First',
                      subtitle: 'Quick 30-45m practice tests first',
                      option: QuizSortOption.durationAsc,
                      icon: Icons.timer_outlined,
                      setSheetState: setSheetState,
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

  Widget _buildSortTile({
    required String label,
    required String subtitle,
    required QuizSortOption option,
    required IconData icon,
    required StateSetter setSheetState,
  }) {
    final isSelected = _sortOption == option;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setSheetState(() => _sortOption = option);
        setState(() {
          _sortOption = option;
          _quizzes = _applySorting(_quizzes);
        });
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isSelected ? googleBlue.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? googleBlue : googleTextSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? googleBlue : googleTextPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                  ),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_rounded, size: 20, color: googleBlue),
          ],
        ),
      ),
    );
  }

  void _showQuizTrapsSheet(Map<String, dynamic> q) {
    showQuizTrapsModalSheet(
      context,
      quizTitle: q['title'] ?? 'Quiz',
      subject: q['subject'] as String?,
      onDataChanged: () {
        _loadQuizzes();
        widget.onDataChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Upcoming Quiz banner
    final upcomingQuiz = _quizzes.firstWhere(
      (q) => (q['status'] as String?)?.toUpperCase() != 'COMPLETED',
      orElse: () => {},
    );

    // Pending vs Completed Quizzes
    final pending = _quizzes.where((q) => (q['status'] as String?)?.toUpperCase() != 'COMPLETED').toList();
    final completed = _quizzes.where((q) => (q['status'] as String?)?.toUpperCase() == 'COMPLETED').toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Sub-Tab Navigation (Weekly Quizzes | Test Series Mocks)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  _buildSubTab(0, 'Weekly Quizzes'),
                  _buildSubTab(1, 'Test Series Mocks'),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: googleHairline),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: googleBlue))
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      // Upcoming Quiz Prep Banner
                      if (upcomingQuiz.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          color: const Color(0xFFFFF9EE),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'UPCOMING QUIZ PREP',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleAmber, letterSpacing: 0.5),
                                  ),
                                  Text(
                                    '${upcomingQuiz['duration_mins']}m • ${upcomingQuiz['total_marks']} Marks',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                upcomingQuiz['title'] ?? '',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: googleTextPrimary),
                              ),
                              if (upcomingQuiz['syllabus_topics'] != null && upcomingQuiz['syllabus_topics'].toString().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Syllabus to Revisit: ${upcomingQuiz['syllabus_topics']}',
                                  style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Divider(height: 1, thickness: 1, color: googleHairline),
                      ],

                      // Flat Quizzes List
                      if (_quizzes.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
                          child: const Center(
                            child: Text(
                              'No quizzes found for the selected filter.',
                              style: TextStyle(fontSize: 14, color: googleTextSecondary),
                            ),
                          ),
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _activeTypeIndex == 0 ? 'WEEKLY QUIZZES' : 'TEST SERIES MOCKS',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: googleTextSecondary, letterSpacing: 0.6),
                              ),
                              Text(
                                '${pending.length} pending • ${completed.length} done',
                                style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                              ),
                            ],
                          ),
                        ),

                        // Active / Pending Quizzes
                        if (pending.isNotEmpty) ...[
                          ...pending.map((q) => _buildQuizRow(q, isCompleted: false)),
                        ] else if (completed.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
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
                                    'All Quizzes Completed!',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: googleTextPrimary),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'You have finished all active tests in this section.',
                                    style: TextStyle(fontSize: 12, color: googleTextSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],

                        // Completed Quizzes Section Accordion Toggle
                        if (completed.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () {
                              setState(() => _isCompletedExpanded = !_isCompletedExpanded);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              child: Row(
                                children: [
                                  Icon(
                                    _isCompletedExpanded
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.keyboard_arrow_right_rounded,
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
                            ...completed.map((q) => _buildQuizRow(q, isCompleted: true)),
                        ],
                      ],
                      const SizedBox(height: 80),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'quizzes_filter_fab',
        elevation: 2,
        backgroundColor: widget.selectedSubject != 'All Subjects' ? googleBlue : Colors.white,
        foregroundColor: widget.selectedSubject != 'All Subjects' ? Colors.white : googleTextPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: widget.selectedSubject != 'All Subjects' ? googleBlue : googleBorder,
          ),
        ),
        tooltip: 'Sort & Filter Options',
        onPressed: _showSortAndFilterSheet,
        child: const Icon(Icons.tune_rounded, size: 20),
      ),
    );
  }

  Widget _buildQuizRow(Map<String, dynamic> q, {required bool isCompleted}) {
    final title = q['title'] ?? 'Quiz';
    final subject = q['subject'] ?? '';
    final module = q['module_name'] ?? '';
    final date = q['date_str'] ?? '';
    final marks = q['total_marks'] ?? 25;
    final dur = q['duration_mins'] ?? 45;
    final syllabus = q['syllabus_topics'] ?? '';
    final url = q['action_url'] as String?;
    final trapCount = _trapsCounts[q['id']] ?? 0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GoogleCheckbox(
                value: isCompleted,
                onChanged: (val) => _toggleQuizStatus(q, val),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (subject.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: isCompleted ? const Color(0xFFF1F3F4) : googleBlue.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              subject.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isCompleted ? googleTextSecondary : googleBlue,
                              ),
                            ),
                          ),
                        if (date.isNotEmpty)
                          Text(
                            date,
                            style: TextStyle(
                              fontSize: 11,
                              color: isCompleted ? googleBorder : googleTextSecondary,
                              decoration: isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        const Spacer(),
                        Text(
                          '${dur}m • $marks M',
                          style: TextStyle(
                            fontSize: 11,
                            color: isCompleted ? googleBorder : googleTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isCompleted ? googleTextSecondary : googleTextPrimary,
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (module.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        module,
                        style: TextStyle(
                          fontSize: 11,
                          color: isCompleted ? googleBorder : googleTextSecondary,
                        ),
                      ),
                    ],
                    if (syllabus.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        syllabus,
                        style: TextStyle(fontSize: 11, color: googleTextSecondary.withOpacity(0.8)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),

                    // Actions Row
                    Row(
                      children: [
                        if (url != null && url.isNotEmpty)
                          InkWell(
                            onTap: () => UrlHelper.launchURL(url),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                border: Border.all(color: googleBlue),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.open_in_new, size: 12, color: googleBlue),
                                  SizedBox(width: 4),
                                  Text(
                                    'Take Test',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleBlue),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const Spacer(),

                        // Mistake Traps Pill
                        InkWell(
                          onTap: () => _showQuizTrapsSheet(q),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: trapCount > 0 ? severityHigh.withOpacity(0.12) : const Color(0xFFF1F3F4),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 13,
                                  color: trapCount > 0 ? severityHigh : googleTextSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  trapCount > 0 ? '$trapCount Blunders' : '0 Traps',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: trapCount > 0 ? severityHigh : googleTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
  }

  Widget _buildSubTab(int index, String title) {
    final isSelected = _activeTypeIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _activeTypeIndex = index);
          _loadQuizzes();
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
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? googleBlue : googleTextSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showQuizTrapsModalSheet(
  BuildContext context, {
  required String quizTitle,
  String? subject,
  VoidCallback? onDataChanged,
}) async {
  final mistakes = await DatabaseService.instance.getMistakeRecordsFiltered(
    quizTitle: quizTitle,
    subject: subject,
  );

  if (!context.mounted) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Logged Traps • $quizTitle',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${mistakes.length} recorded mistake notes for this quiz',
                        style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    showAddMistakeModalSheet(
                      context,
                      initialQuizTitle: quizTitle,
                      initialSubject: subject,
                      onSaved: () {
                        onDataChanged?.call();
                      },
                    );
                  },
                  icon: const Icon(Icons.add, size: 16, color: googleBlue),
                  label: const Text('Log Trap', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    backgroundColor: googleBlue.withOpacity(0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 1, color: googleHairline),
            Expanded(
              child: mistakes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, size: 40, color: googleGreen),
                          const SizedBox(height: 10),
                          const Text(
                            'No mistakes logged for this specific quiz yet.',
                            style: TextStyle(fontSize: 13, color: googleTextSecondary),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              showAddMistakeModalSheet(
                                context,
                                initialQuizTitle: quizTitle,
                                initialSubject: subject,
                                onSaved: () {
                                  onDataChanged?.call();
                                },
                              );
                            },
                            icon: const Icon(Icons.add, size: 16, color: googleBlue),
                            label: const Text('Add First Mistake Trap'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: mistakes.length,
                      itemBuilder: (context, idx) {
                        final m = mistakes[idx];
                        final topic = m['topic'] ?? '';
                        final qText = m['question_text'] ?? '';
                        final reason = m['mistake_reason'] ?? '';
                        final takeaway = m['key_takeaway'] ?? '';
                        final wrong = (m['wrong_answer'] as String?)?.trim() ?? '';
                        final correct = (m['correct_answer'] as String?)?.trim() ?? '';
                        final sev = m['severity'] ?? 'MEDIUM';

                        Color sevCol = severityMed;
                        if (sev == 'HIGH') sevCol = severityHigh;
                        if (sev == 'LOW') sevCol = severityLow;

                        return Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFD),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: googleHairline),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: sevCol.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      sev,
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: sevCol),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      topic,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleTextPrimary),
                                    ),
                                  ),
                                ],
                              ),
                              if (qText.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                const Text('Question / Source:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                                const SizedBox(height: 2),
                                MarkdownBody(
                                  data: qText,
                                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                    p: const TextStyle(fontSize: 12, color: googleTextPrimary, height: 1.3),
                                  ),
                                  onTapLink: (text, href, title) => openExternalUrl(href),
                                ),
                              ],
                              if (wrong.isNotEmpty || correct.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    if (wrong.isNotEmpty)
                                      Expanded(
                                        child: Text('Wrong: $wrong', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: severityHigh)),
                                      ),
                                    if (correct.isNotEmpty)
                                      Expanded(
                                        child: Text('Correct: $correct', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: googleGreen)),
                                      ),
                                  ],
                                ),
                              ],
                              if (reason.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('Trap: $reason', style: const TextStyle(fontSize: 11, color: severityMed)),
                              ],
                              const SizedBox(height: 6),
                              MarkdownBody(
                                data: takeaway,
                                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                  p: const TextStyle(fontSize: 12, color: googleTextPrimary, height: 1.3),
                                ),
                                onTapLink: (text, href, title) => openExternalUrl(href),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
