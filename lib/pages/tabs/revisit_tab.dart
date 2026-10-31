import 'package:flutter/material.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/widgets/google_checkbox.dart';

class RevisitTab extends StatefulWidget {
  final VoidCallback onDataChanged;

  const RevisitTab({Key? key, required this.onDataChanged}) : super(key: key);

  @override
  _RevisitTabState createState() => _RevisitTabState();
}

class _RevisitTabState extends State<RevisitTab> {
  int _activeSubIndex = 0; // 0: Due Today, 1: Spaced (1-30d), 2: Mistakes
  List<Map<String, dynamic>> _todayRevisits = [];
  List<Map<String, dynamic>> _allSpacedRevisits = [];
  List<Map<String, dynamic>> _mistakes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final todayRev = await DatabaseService.instance.getDueRevisitsForDate(DateTime.now());
    final allSpaced = await DatabaseService.instance.getAllSpacedRevisits();
    final mistakes = await DatabaseService.instance.getMistakeRecords();

    if (mounted) {
      setState(() {
        _todayRevisits = todayRev;
        _allSpacedRevisits = allSpaced;
        _mistakes = mistakes;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleRevisit(Map<String, dynamic> rev, bool done) async {
    final id = rev['id'] as int;
    await DatabaseService.instance.toggleRevisitStatus(id, done);
    await _loadData();
    widget.onDataChanged();
  }

  Future<void> _toggleMistake(Map<String, dynamic> m, bool resolved) async {
    final id = m['id'] as int;
    await DatabaseService.instance.toggleMistakeResolved(id, resolved);
    await _loadData();
    widget.onDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: googleBlue));
    }

    return Column(
      children: [
        // Top Sub-segment Navigation
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              _buildSubTabButton(0, 'Due Today (${_todayRevisits.length})'),
              const SizedBox(width: 8),
              _buildSubTabButton(1, 'Spaced (1-30d)'),
              const SizedBox(width: 8),
              _buildSubTabButton(2, 'Mistakes (${_mistakes.length})'),
            ],
          ),
        ),
        const Divider(height: 1, color: googleBorder),

        Expanded(
          child: IndexedStack(
            index: _activeSubIndex,
            children: [
              _buildTodayRevisitsView(),
              _buildSpacedRevisitsView(),
              _buildMistakesView(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubTabButton(int index, String title) {
    final isActive = _activeSubIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeSubIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? googleBlueContainer : const Color(0xFFF0F4F9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

  Widget _buildTodayRevisitsView() {
    if (_todayRevisits.isEmpty) {
      return const Center(
        child: Text(
          'No revisits due today! Memory retention on track.',
          style: TextStyle(fontSize: 13, color: googleTextSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _todayRevisits.length,
      itemBuilder: (context, index) {
        final rev = _todayRevisits[index];
        final isDone = (rev['status'] as String?)?.toUpperCase() == 'DONE';
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
              GoogleCheckbox(
                value: isDone,
                onChanged: (val) => _toggleRevisit(rev, val),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rev['topic'] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? Colors.grey : googleTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Stage: ${rev['stage'] ?? "Day 1"} • ${rev['duration_mins'] ?? 30} mins',
                      style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: googleBlueContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  rev['stage'] ?? 'Day 1',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: googleOnBlueContainer,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpacedRevisitsView() {
    if (_allSpacedRevisits.isEmpty) {
      return const Center(
        child: Text(
          'No upcoming spaced retention items.',
          style: TextStyle(fontSize: 13, color: googleTextSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allSpacedRevisits.length,
      itemBuilder: (context, index) {
        final rev = _allSpacedRevisits[index];
        final isDone = (rev['status'] as String?)?.toUpperCase() == 'DONE';
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
              GoogleCheckbox(
                value: isDone,
                onChanged: (val) => _toggleRevisit(rev, val),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rev['topic'] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? Colors.grey : googleTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Due: ${rev['due_date'] ?? ""} • ${rev['duration_mins'] ?? 30}m',
                      style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  rev['stage'] ?? 'Checkpoint',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF444746)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMistakesView() {
    if (_mistakes.isEmpty) {
      return const Center(
        child: Text(
          'No mistakes recorded. Keep up the high accuracy!',
          style: TextStyle(fontSize: 13, color: googleTextSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _mistakes.length,
      itemBuilder: (context, index) {
        final m = _mistakes[index];
        final isResolved = (m['status'] as String?)?.toUpperCase() == 'RESOLVED';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isResolved ? googleBorder : googleBlue.withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: googleBlueContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      m['subject'] ?? 'Subject',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: googleOnBlueContainer,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => _toggleMistake(m, !isResolved),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isResolved ? const Color(0xFFE6F4EA) : const Color(0xFFFEF7E0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isResolved ? '✓ Resolved' : 'Unresolved',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isResolved ? const Color(0xFF137333) : const Color(0xFFB06000),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                m['question_text'] ?? m['topic'] ?? '',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: googleTextPrimary,
                ),
              ),
              if ((m['key_takeaway'] as String?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFD),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE0E2EC)),
                  ),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Takeaway: ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: googleBlue,
                          ),
                        ),
                        TextSpan(
                          text: m['key_takeaway'] ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            color: googleTextPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
