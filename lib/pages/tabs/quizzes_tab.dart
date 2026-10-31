import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/widgets/google_checkbox.dart';
import 'package:url_launcher/url_launcher.dart';

class QuizzesTab extends StatefulWidget {
  final VoidCallback onDataChanged;
  final String selectedSubject;

  const QuizzesTab({
    Key? key,
    required this.onDataChanged,
    this.selectedSubject = 'All Subjects',
  }) : super(key: key);

  @override
  _QuizzesTabState createState() => _QuizzesTabState();
}

class _QuizzesTabState extends State<QuizzesTab> {
  int _activeTypeIndex = 0; // 0: WEEKLY_QUIZ, 1: TEST_SERIES
  List<Map<String, dynamic>> _quizzes = [];
  Map<int, int> _trapsCounts = {};
  bool _isLoading = true;

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

  Future<void> _loadQuizzes() async {
    setState(() => _isLoading = true);
    final type = _activeTypeIndex == 0 ? 'WEEKLY_QUIZ' : 'TEST_SERIES';
    final items = await DatabaseService.instance.getQuizzesByType(type, subjectFilter: widget.selectedSubject);

    final counts = <int, int>{};
    for (var q in items) {
      final title = q['title'] ?? '';
      final id = q['id'] as int;
      final cnt = await DatabaseService.instance.getMistakeCountForQuiz(title);
      counts[id] = cnt;
    }

    if (mounted) {
      setState(() {
        _quizzes = items;
        _trapsCounts = counts;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleQuizStatus(Map<String, dynamic> q, bool done) async {
    final id = q['id'] as int;
    await DatabaseService.instance.toggleQuizStatus(id, done);
    await _loadQuizzes();
    widget.onDataChanged();
  }

  void _showQuizTrapsSheet(Map<String, dynamic> q) async {
    final title = q['title'] ?? 'Quiz';
    final mistakes = await DatabaseService.instance.getMistakeRecordsFiltered(quizTitle: title);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
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
              Text(
                'Logged Traps • $title',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: googleTextPrimary),
                maxLines: 2,
              ),
              const SizedBox(height: 4),
              Text(
                '${mistakes.length} recorded mistake notes for this quiz',
                style: const TextStyle(fontSize: 12, color: googleTextSecondary),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 1, color: googleHairline),
              Expanded(
                child: mistakes.isEmpty
                    ? const Center(
                        child: Text(
                          'No mistakes logged for this specific quiz title yet.',
                          style: TextStyle(fontSize: 13, color: googleTextSecondary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: mistakes.length,
                        itemBuilder: (context, idx) {
                          final m = mistakes[idx];
                          final topic = m['topic'] ?? '';
                          final takeaway = m['key_takeaway'] ?? '';
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
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: sevCol),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        topic,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: googleTextPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                MarkdownBody(
                                  data: takeaway,
                                  selectable: true,
                                  onTapLink: (text, href, title) async {
                                    if (href != null) {
                                      final uri = Uri.parse(href);
                                      if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  },
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

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? upcomingQuiz;
    if (_quizzes.isNotEmpty) {
      upcomingQuiz = _quizzes.firstWhere(
        (q) => (q['status'] as String?)?.toUpperCase() != 'COMPLETED',
        orElse: () => _quizzes.first,
      );
    }

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Sub-Tab Navigation
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
                      if (upcomingQuiz != null) ...[
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
                                    '${upcomingQuiz['duration_mins']}M • ${upcomingQuiz['total_marks']} MARKS',
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
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _activeTypeIndex == 0 ? 'WEEKLY QUIZZES' : 'TEST SERIES MOCKS',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: googleTextSecondary, letterSpacing: 0.6),
                              ),
                              Text('${_quizzes.length} tests', style: const TextStyle(fontSize: 11, color: googleTextSecondary)),
                            ],
                          ),
                        ),
                        ..._quizzes.map((q) {
                          final isDone = (q['status'] as String?)?.toUpperCase() == 'COMPLETED';
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
                                      value: isDone,
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
                                                    color: const Color(0xFFF1F3F4),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    subject.toUpperCase(),
                                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: googleTextPrimary),
                                                  ),
                                                ),
                                              if (date.isNotEmpty)
                                                Text(date, style: const TextStyle(fontSize: 11, color: googleTextSecondary)),
                                              const Spacer(),
                                              Text('${dur}m', style: const TextStyle(fontSize: 11, color: googleTextSecondary)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            title,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: isDone ? googleTextSecondary : googleTextPrimary,
                                              decoration: isDone ? TextDecoration.lineThrough : null,
                                            ),
                                          ),
                                          if (module.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(module, style: const TextStyle(fontSize: 11, color: googleTextSecondary)),
                                          ],
                                          if (trapCount > 0) ...[
                                            const SizedBox(height: 6),
                                            InkWell(
                                              onTap: () => _showQuizTrapsSheet(q),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFFF0D4),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  '• $trapCount Logged Traps • View Notes →',
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleAmber),
                                                ),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Text('$marks Marks', style: const TextStyle(fontSize: 11, color: googleTextSecondary)),
                                              if (syllabus.isNotEmpty) ...[
                                                const Text(' • ', style: TextStyle(fontSize: 11, color: googleTextSecondary)),
                                                Expanded(
                                                  child: Text(
                                                    syllabus,
                                                    style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                              if (url != null && url.isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                InkWell(
                                                  onTap: () async {
                                                    final uri = Uri.parse(url);
                                                    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                                                  },
                                                  child: const Text(
                                                    'Start Quiz ↗',
                                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleBlue),
                                                  ),
                                                ),
                                              ],
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
          ),
        ],
      ),
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
