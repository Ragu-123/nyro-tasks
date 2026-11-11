import 'package:flutter/material.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/widgets/google_checkbox.dart';

class TimetableTab extends StatefulWidget {
  final VoidCallback onDataChanged;
  final String selectedSubject;
  final List<String>? availableSubjects;
  final VoidCallback? onOpenFilter;

  const TimetableTab({
    Key? key,
    required this.onDataChanged,
    this.selectedSubject = 'All Subjects',
    this.availableSubjects,
    this.onOpenFilter,
  }) : super(key: key);

  @override
  _TimetableTabState createState() => _TimetableTabState();
}

class _TimetableTabState extends State<TimetableTab> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _lectures = [];
  List<String> _availableSubjects = ['All Subjects'];
  late String _activeSubject;
  bool _isLoading = true;
  bool _isSearchVisible = false;
  bool _isCompletedExpanded = false;

  @override
  void initState() {
    super.initState();
    _activeSubject = widget.selectedSubject;
    if (widget.availableSubjects != null && widget.availableSubjects!.isNotEmpty) {
      _availableSubjects = widget.availableSubjects!;
    }
    _loadSubjectsAndCurriculum();
  }

  @override
  void didUpdateWidget(covariant TimetableTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.availableSubjects != null && widget.availableSubjects != oldWidget.availableSubjects) {
      setState(() {
        _availableSubjects = widget.availableSubjects!;
        if (!_availableSubjects.contains(_activeSubject)) {
          _activeSubject = 'All Subjects';
        }
      });
      _loadCurriculum();
    } else if (oldWidget.selectedSubject != widget.selectedSubject && widget.selectedSubject != _activeSubject) {
      _activeSubject = widget.selectedSubject;
      _loadCurriculum();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjectsAndCurriculum() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        DatabaseService.instance.getAllDistinctSubjects(),
        DatabaseService.instance.getCurriculumGroupedBySubject(
          query: _searchController.text,
          subjectFilter: _activeSubject,
        ),
      ]);

      if (mounted) {
        final subjs = results[0] as List<String>;
        final items = results[1] as List<Map<String, dynamic>>;
        setState(() {
          _availableSubjects = subjs.isNotEmpty ? subjs : ['All Subjects'];
          if (!_availableSubjects.contains(_activeSubject)) {
            _activeSubject = 'All Subjects';
          }
          _lectures = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading timetable tab: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadCurriculum() async {
    setState(() => _isLoading = true);
    final items = await DatabaseService.instance.getCurriculumGroupedBySubject(
      query: _searchController.text,
      subjectFilter: _activeSubject,
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
      date = DateTime.parse(dateStr);
    } catch (_) {}

    await DatabaseService.instance.toggleLectureStatus(id, completed, dur, date);
    await _loadCurriculum();
    widget.onDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    // Separate pending vs completed lectures
    final pending = _lectures.where((l) => (l['status'] as String?)?.toUpperCase() != 'COMPLETED').toList();
    final completed = _lectures.where((l) => (l['status'] as String?)?.toUpperCase() == 'COMPLETED').toList();
    final total = _lectures.length;
    final pct = total > 0 ? (completed.length / total).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 1. Fixed Top Subject Dropdown Bar with Search Action
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: googleHairline, width: 1)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Subject Dropdown Selector
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F3F4),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: googleBorder.withOpacity(0.4)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _availableSubjects.contains(_activeSubject) ? _activeSubject : 'All Subjects',
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: googleTextPrimary, size: 20),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: googleTextPrimary,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            items: _availableSubjects.map((s) {
                              return DropdownMenuItem<String>(
                                value: s,
                                child: Text(
                                  s,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _activeSubject = val;
                                });
                                _loadCurriculum();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Search Lectures Icon Button
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _isSearchVisible || _searchController.text.isNotEmpty
                            ? googleBlue.withOpacity(0.12)
                            : const Color(0xFFF1F3F4),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: IconButton(
                        icon: Icon(
                          _isSearchVisible ? Icons.search_off_rounded : Icons.search_rounded,
                          color: _isSearchVisible || _searchController.text.isNotEmpty ? googleBlue : googleTextSecondary,
                          size: 20,
                        ),
                        tooltip: 'Search lectures in this subject',
                        onPressed: () {
                          setState(() {
                            _isSearchVisible = !_isSearchVisible;
                            if (!_isSearchVisible && _searchController.text.isNotEmpty) {
                              _searchController.clear();
                              _loadCurriculum();
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),

                // Expandable Search Bar (when search icon is tapped)
                if (_isSearchVisible) ...[
                  const SizedBox(height: 10),
                  Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFD),
                      borderRadius: BorderRadius.circular(21),
                      border: Border.all(color: googleBlue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 18, color: googleBlue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            onChanged: (_) => _loadCurriculum(),
                            style: const TextStyle(fontSize: 13, color: googleTextPrimary),
                            decoration: InputDecoration(
                              hintText: 'Search in ${_activeSubject == "All Subjects" ? "curriculum" : _activeSubject}...',
                              hintStyle: const TextStyle(fontSize: 12.5, color: googleTextSecondary),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              _loadCurriculum();
                            },
                            child: const Icon(Icons.clear, size: 16, color: googleTextSecondary),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 2. Subject Progress Summary
          if (!_isLoading && _lectures.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              color: const Color(0xFFFAFBFC),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _activeSubject.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: googleTextSecondary,
                            letterSpacing: 0.6,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${completed.length}/$total (${(pct * 100).toInt()}%)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: pct == 1.0 ? googleGreen : googleBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 5,
                      backgroundColor: const Color(0xFFE8EAED),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        pct == 1.0 ? googleGreen : googleBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 3. Lectures List: Pending first, followed by Completed Accordion Toggle
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: googleBlue))
                : _lectures.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.menu_book_outlined, size: 48, color: googleTextSecondary.withOpacity(0.5)),
                            const SizedBox(height: 12),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No lectures match "${_searchController.text}"'
                                  : 'No lectures found in $_activeSubject.',
                              style: const TextStyle(fontSize: 13, color: googleTextSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 80),
                        children: [
                          // Pending Lectures
                          if (pending.isNotEmpty) ...[
                            ...pending.map((lec) => _buildLectureRow(lec, isCompleted: false)),
                          ] else if (completed.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                              child: Center(
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: googleGreen.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.task_alt_rounded, color: googleGreen, size: 28),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'All Lectures Completed!',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: googleTextPrimary),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Great work! You have finished all syllabus lectures for this subject.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12, color: googleTextSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],

                          // Completed Section Accordion (like Today page)
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
                              ...completed.map((lec) => _buildLectureRow(lec, isCompleted: true)),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildLectureRow(Map<String, dynamic> lec, {required bool isCompleted}) {
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
                        if (_activeSubject == 'All Subjects' && topic.isNotEmpty) ...[
                          Text(
                            topic.contains('•') ? topic.split('•')[0].trim() : topic,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isCompleted ? googleTextSecondary : googleBlue,
                            ),
                          ),
                          const Text(' • ', style: TextStyle(fontSize: 11, color: googleTextSecondary)),
                        ],
                        if (dateStr.isNotEmpty) ...[
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: isCompleted ? googleBorder : googleTextSecondary,
                              decoration: isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          const Text(' • ', style: TextStyle(fontSize: 11, color: googleTextSecondary)),
                        ],
                        Text(
                          '${dur.toStringAsFixed(1)}h',
                          style: TextStyle(
                            fontSize: 11,
                            color: isCompleted ? googleBorder : googleTextSecondary,
                          ),
                        ),
                        if (status == 'BACKLOG' && !isCompleted) ...[
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
  }
}
