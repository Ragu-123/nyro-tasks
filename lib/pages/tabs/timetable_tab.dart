import 'package:flutter/material.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/widgets/google_checkbox.dart';

class TimetableTab extends StatefulWidget {
  final VoidCallback onDataChanged;

  const TimetableTab({Key? key, required this.onDataChanged}) : super(key: key);

  @override
  _TimetableTabState createState() => _TimetableTabState();
}

class _TimetableTabState extends State<TimetableTab> {
  List<Map<String, dynamic>> _allSessions = [];
  List<Map<String, dynamic>> _filteredSessions = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final sessions = await DatabaseService.instance.getAllCurriculumSessions();
    if (mounted) {
      setState(() {
        _allSessions = sessions;
        _applyFilters();
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> result = List.from(_allSessions);

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((s) {
        final topic = (s['topic'] as String?)?.toLowerCase() ?? '';
        final details = (s['details'] as String?)?.toLowerCase() ?? '';
        final date = (s['date_str'] as String?)?.toLowerCase() ?? '';
        return topic.contains(q) || details.contains(q) || date.contains(q);
      }).toList();
    }

    _filteredSessions = result;
  }

  Future<void> _toggleLecture(Map<String, dynamic> lec, bool completed) async {
    final id = lec['id'] as int;
    final dur = (lec['duration_hours'] as num?)?.toDouble() ?? 1.0;
    await DatabaseService.instance.toggleLectureStatus(id, completed, dur, DateTime.now());
    await _loadData();
    widget.onDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: googleBlue));
    }

    // Group filtered sessions by date_str
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var s in _filteredSessions) {
      final date = (s['date_str'] as String?) ?? 'No Date';
      grouped.putIfAbsent(date, () => []).add(s);
    }

    final double totalHours = _filteredSessions.fold<double>(
        0.0, (sum, s) => sum + ((s['duration_hours'] as num?)?.toDouble() ?? 1.0));

    return Column(
      children: [
        // Search & Summary Bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: Colors.white,
          child: Column(
            children: [
              TextField(
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _applyFilters();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search topic, lecture, or date...',
                  hintStyle: const TextStyle(fontSize: 13, color: googleTextSecondary),
                  prefixIcon: const Icon(Icons.search, size: 20, color: googleTextSecondary),
                  filled: true,
                  fillColor: const Color(0xFFF0F4F9),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_filteredSessions.length} Sessions Total',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: googleTextSecondary,
                    ),
                  ),
                  Text(
                    '${totalHours.toStringAsFixed(1)} hrs',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: googleBlue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: googleBorder),

        // Grouped List of Sessions
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: grouped.keys.length,
            itemBuilder: (context, index) {
              final date = grouped.keys.elementAt(index);
              final items = grouped[date]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6, left: 4),
                    child: Text(
                      date.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: googleTextSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...items.map((lec) {
                    final isCompleted =
                        (lec['status'] as String?)?.toUpperCase() == 'COMPLETED';
                    final dur = (lec['duration_hours'] as num?)?.toDouble() ?? 1.0;
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
                                    decoration:
                                        isCompleted ? TextDecoration.lineThrough : null,
                                    color:
                                        isCompleted ? Colors.grey : googleTextPrimary,
                                  ),
                                ),
                                if ((lec['details'] as String?)?.isNotEmpty ?? false) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    lec['details'] ?? '',
                                    style: const TextStyle(
                                        fontSize: 12, color: googleTextSecondary),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0F4F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${dur.toStringAsFixed(1)}h • ${lec['session_block'] ?? "Session"}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF444746)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
