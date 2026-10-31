import 'package:flutter/material.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:url_launcher/url_launcher.dart';

class QuizzesTab extends StatefulWidget {
  const QuizzesTab({Key? key}) : super(key: key);

  @override
  _QuizzesTabState createState() => _QuizzesTabState();
}

class _QuizzesTabState extends State<QuizzesTab> {
  int _activeTypeIndex = 0; // 0: WEEKLY_QUIZ, 1: TEST_SERIES
  List<Map<String, dynamic>> _quizzes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuizzes();
  }

  Future<void> _loadQuizzes() async {
    setState(() => _isLoading = true);
    final type = _activeTypeIndex == 0 ? 'WEEKLY_QUIZ' : 'TEST_SERIES';
    final items = await DatabaseService.instance.getQuizzesByType(type);
    if (mounted) {
      setState(() {
        _quizzes = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _openExamLink(String? url) async {
    final link = url ?? 'https://gateoverflow.in';
    final uri = Uri.parse(link);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Sub-segmented Tab
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              _buildTypeButton(0, 'Weekly Quizzes'),
              const SizedBox(width: 8),
              _buildTypeButton(1, 'Test Series Mocks'),
            ],
          ),
        ),
        const Divider(height: 1, color: googleBorder),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: googleBlue))
              : _quizzes.isEmpty
                  ? const Center(
                      child: Text(
                        'No quizzes found.',
                        style: TextStyle(fontSize: 13, color: googleTextSecondary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _quizzes.length,
                      itemBuilder: (context, index) {
                        final q = _quizzes[index];
                        final status = q['status'] ?? 'UPCOMING';
                        final isReady = status.toString().toUpperCase() == 'READY';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: googleBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    q['week_number'] != null
                                        ? 'WEEK ${q['week_number']} QUIZ'
                                        : 'TEST SERIES',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: googleBlue,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isReady
                                          ? const Color(0xFFE6F4EA)
                                          : const Color(0xFFF1F3F4),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      status.toString().toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isReady
                                            ? const Color(0xFF137333)
                                            : const Color(0xFF5F6368),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                q['title'] ?? 'Quiz',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: googleTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    '${q['duration_mins'] ?? 90} mins',
                                    style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                                  ),
                                  const Text(' • ', style: TextStyle(color: googleTextSecondary)),
                                  Text(
                                    '${q['total_questions'] ?? 30} Qs',
                                    style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                                  ),
                                  const Text(' • ', style: TextStyle(color: googleTextSecondary)),
                                  Text(
                                    '${q['total_marks'] ?? 50} Marks',
                                    style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () => _openExamLink(q['action_url']),
                                  style: TextButton.styleFrom(
                                    backgroundColor: googleBlueContainer,
                                    foregroundColor: googleOnBlueContainer,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  ),
                                  icon: const Icon(Icons.open_in_new, size: 14),
                                  label: const Text(
                                    'Open on GateOverflow',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildTypeButton(int index, String title) {
    final isActive = _activeTypeIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _activeTypeIndex = index);
          _loadQuizzes();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? googleBlueContainer : const Color(0xFFF0F4F9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: isActive ? googleOnBlueContainer : googleTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
