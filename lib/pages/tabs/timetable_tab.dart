import 'package:flutter/material.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/widgets/google_checkbox.dart';

class TimetableTab extends StatefulWidget {
  final VoidCallback onDataChanged;
  final String selectedSubject;
  final VoidCallback? onOpenFilter;

  const TimetableTab({
    Key? key,
    required this.onDataChanged,
    this.selectedSubject = 'All Subjects',
    this.onOpenFilter,
  }) : super(key: key);

  @override
  _TimetableTabState createState() => _TimetableTabState();
}

class _TimetableTabState extends State<TimetableTab> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _lectures = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurriculum();
  }

  @override
  void didUpdateWidget(covariant TimetableTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSubject != widget.selectedSubject) {
      _loadCurriculum();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurriculum() async {
    setState(() => _isLoading = true);
    final items = await DatabaseService.instance.getCurriculumGroupedBySubject(
      query: _searchController.text,
      subjectFilter: widget.selectedSubject,
    );
    if (mounted) {
      setState(() {
        _lectures = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleLecture(Map<String, dynamic> lec, bool completed) async {
    final id = lec['id'] as int;
    final dur = (lec['duration_hours'] as num?)?.toDouble() ?? 1.0;
    final dateStr = lec['date_str'] ?? '';
    DateTime date = DateTime.now();
    try {
      // Try parsing date or fallback to now
      date = DateTime.parse(dateStr);
    } catch (_) {}

    await DatabaseService.instance.toggleLectureStatus(id, completed, dur, date);
    await _loadCurriculum();
    widget.onDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Google Search Header (Flat on canvas)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F4),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Icon(Icons.search, color: googleTextSecondary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => _loadCurriculum(),
                      decoration: const InputDecoration(
                        hintText: 'Search lectures, topics, dates...',
                        hintStyle: TextStyle(fontSize: 14, color: googleTextSecondary),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: googleTextSecondary),
                      onPressed: () {
                        _searchController.clear();
                        _loadCurriculum();
                      },
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: googleHairline),

          // Curriculum Hierarchy
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: googleBlue))
                : _lectures.isEmpty
                    ? const Center(
                        child: Text(
                          'No lectures match your search or filter.',
                          style: TextStyle(fontSize: 14, color: googleTextSecondary),
                        ),
                      )
                    : _buildGroupedCurriculum(),
          ),
        ],
      ),
      floatingActionButton: widget.onOpenFilter != null
          ? FloatingActionButton.small(
              heroTag: 'timetable_filter_fab',
              elevation: 2,
              backgroundColor: widget.selectedSubject != 'All Subjects' ? googleBlue : Colors.white,
              foregroundColor: widget.selectedSubject != 'All Subjects' ? Colors.white : googleTextPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: widget.selectedSubject != 'All Subjects' ? googleBlue : googleBorder,
                ),
              ),
              tooltip: 'Filter by Subject',
              onPressed: widget.onOpenFilter,
              child: const Icon(Icons.tune_rounded, size: 20),
            )
          : null,
    );
  }

  Widget _buildGroupedCurriculum() {
    // Group lectures by Subject
    final subjectGroups = <String, List<Map<String, dynamic>>>{};
    for (var l in _lectures) {
      final topic = l['topic'] as String? ?? 'General';
      final subject = topic.contains('•') ? topic.split('•')[0].trim() : topic.trim();
      subjectGroups.putIfAbsent(subject, () => []).add(l);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: subjectGroups.length,
      itemBuilder: (context, index) {
        final subject = subjectGroups.keys.elementAt(index);
        final items = subjectGroups[subject]!;
        final completed = items.where((l) => (l['status'] as String?)?.toUpperCase() == 'COMPLETED').length;
        final total = items.length;
        final pct = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;

        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: index == 0,
            tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    subject.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: googleTextPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Text(
                  '$completed/$total (${(pct * 100).toInt()}%)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: googleBlue),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 4,
                  backgroundColor: const Color(0xFFF1F3F4),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    pct == 1.0 ? googleGreen : googleBlue,
                  ),
                ),
              ),
            ),
            children: items.map((lec) {
              final isCompleted = (lec['status'] as String?)?.toUpperCase() == 'COMPLETED';
              final title = lec['details'] ?? lec['topic'] ?? 'Lecture';
              final topic = lec['topic'] ?? '';
              final dateStr = lec['date_str'] ?? '';
              final dur = (lec['duration_hours'] as num?)?.toDouble() ?? 1.0;
              final status = lec['status'] as String? ?? 'PENDING';

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 20, 10),
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
                              Row(
                                children: [
                                  if (dateStr.isNotEmpty) ...[
                                    Text(
                                      dateStr,
                                      style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                                    ),
                                    const Text(' • ', style: TextStyle(fontSize: 11, color: googleTextSecondary)),
                                  ],
                                  Text(
                                    '${dur.toStringAsFixed(1)}h',
                                    style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                                  ),
                                  if (status == 'BACKLOG') ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF0D4),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'BACKLOG',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: googleAmber,
                                        ),
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
            }).toList(),
          ),
        );
      },
    );
  }
}
