import 'package:flutter/material.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/widgets/google_checkbox.dart';

class TodayTab extends StatefulWidget {
  final DateTime currentDate;
  final VoidCallback onDataChanged;

  const TodayTab({
    Key? key,
    required this.currentDate,
    required this.onDataChanged,
  }) : super(key: key);

  @override
  _TodayTabState createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  Map<String, dynamic> _pacing = {'target_hours': 8.0, 'watched_hours': 0.0};
  List<Map<String, dynamic>> _lectures = [];
  List<Map<String, dynamic>> _dueRevisits = [];
  bool _isLoading = true;
  bool _isCompletedExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant TodayTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentDate != widget.currentDate) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final pacing = await DatabaseService.instance.getDailyPacing(widget.currentDate);
    final lectures = await DatabaseService.instance.getLecturesForDate(widget.currentDate);
    final revisits = await DatabaseService.instance.getDueRevisitsForDate(widget.currentDate);

    if (mounted) {
      setState(() {
        _pacing = pacing;
        _lectures = lectures;
        _dueRevisits = revisits;
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: googleBlue),
      );
    }

    final pendingLectures = _lectures
        .where((l) => (l['status'] as String?)?.toUpperCase() != 'COMPLETED')
        .toList();
    final completedLectures = _lectures
        .where((l) => (l['status'] as String?)?.toUpperCase() == 'COMPLETED')
        .toList();

    final target = (_pacing['target_hours'] as num?)?.toDouble() ?? 8.0;
    final watched = (_pacing['watched_hours'] as num?)?.toDouble() ?? 0.0;
    final progress = target > 0 ? (watched / target).clamp(0.0, 1.0) : 0.0;
    final remaining = (target - watched).clamp(0.0, target);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      children: [
        // Pacing Hero Card
        Container(
          padding: const EdgeInsets.all(16.0),
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
                  const Text(
                    'Daily Lecture Target',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: googleTextSecondary,
                    ),
                  ),
                  Text(
                    '${watched.toStringAsFixed(1)} / ${target.toStringAsFixed(1)}h',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: googleTextPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE9EEF6),
                  color: googleBlue,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    remaining <= 0.05
                        ? 'Target achieved for today!'
                        : 'Consolidated pace: ${remaining.toStringAsFixed(1)}h remaining',
                    style: const TextStyle(
                      fontSize: 12,
                      color: googleTextSecondary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Starts 08:00 AM',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 24h Active Lecture Recall Section (if any)
        if (_dueRevisits.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
            child: Text(
              '24H ACTIVE LECTURE RECALL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: googleTextSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          ..._dueRevisits.map((rev) {
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
                          rev['topic'] ?? 'Topic Recall',
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
          }),
          const SizedBox(height: 12),
        ],

        // Today's Lectures Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TODAY\'S LECTURES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: googleTextSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '${completedLectures.length} of ${_lectures.length} Done',
                style: const TextStyle(fontSize: 12, color: googleBlue, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),

        if (pendingLectures.isEmpty && completedLectures.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: const Text(
              'No lectures scheduled for this date.',
              style: TextStyle(fontSize: 13, color: googleTextSecondary),
            ),
          ),

        // Active Lectures
        ...pendingLectures.map((lec) => _buildLectureItem(lec, false)),

        // Collapsible Completed Section
        if (completedLectures.isNotEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () {
              setState(() {
                _isCompletedExpanded = !_isCompletedExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: Row(
                children: [
                  Icon(
                    _isCompletedExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 20,
                    color: googleTextSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Completed (${completedLectures.length})',
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
            ...completedLectures.map((lec) => _buildLectureItem(lec, true)),
        ],
      ],
    );
  }

  Widget _buildLectureItem(Map<String, dynamic> lec, bool isCompleted) {
    final dur = (lec['duration_hours'] as num?)?.toDouble() ?? 1.0;
    final block = (lec['session_block'] as String?) ?? 'Morning Block';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: googleBorder),
      ),
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
                  lec['topic'] ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                    color: isCompleted ? Colors.grey : googleTextPrimary,
                  ),
                ),
                if ((lec['details'] as String?)?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 2),
                  Text(
                    lec['details'] ?? '',
                    style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${dur.toStringAsFixed(1)}h',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF444746)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      block,
                      style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
