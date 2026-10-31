import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/widgets/google_checkbox.dart';
import 'package:url_launcher/url_launcher.dart';

class RevisitTab extends StatefulWidget {
  final VoidCallback onDataChanged;
  final String selectedSubject;

  const RevisitTab({
    Key? key,
    required this.onDataChanged,
    this.selectedSubject = 'All Subjects',
  }) : super(key: key);

  @override
  _RevisitTabState createState() => _RevisitTabState();
}

class _RevisitTabState extends State<RevisitTab> {
  int _activeSubIndex = 0; // 0: Due / Backlog, 1: Retention Matrix, 2: Mistake Notebook

  List<Map<String, dynamic>> _dueBacklog = [];
  List<Map<String, dynamic>> _matrixData = [];
  List<Map<String, dynamic>> _mistakes = [];

  String _mistakeStatusFilter = 'ALL';
  String _mistakeSeverityFilter = 'ALL';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant RevisitTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSubject != widget.selectedSubject) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final due = await DatabaseService.instance.getAllDueBacklogRevisits(subject: widget.selectedSubject);
    final matrix = await DatabaseService.instance.getRetentionMatrixData();
    final mistakes = await DatabaseService.instance.getMistakeRecordsFiltered(
      subject: widget.selectedSubject,
      status: _mistakeStatusFilter,
      severity: _mistakeSeverityFilter,
    );

    if (mounted) {
      setState(() {
        _dueBacklog = due;
        _matrixData = matrix;
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

  Future<void> _toggleMistakeResolved(Map<String, dynamic> m, bool resolved) async {
    final id = m['id'] as int;
    await DatabaseService.instance.toggleMistakeResolved(id, resolved);
    await _loadData();
    widget.onDataChanged();
  }

  void _showAddMistakeSheet() {
    final titleController = TextEditingController();
    final subjectController = TextEditingController(text: widget.selectedSubject != 'All Subjects' ? widget.selectedSubject : 'Linear Algebra');
    final questionController = TextEditingController();
    final wrongAnswerController = TextEditingController();
    final correctAnswerController = TextEditingController();
    final takeawayController = TextEditingController();
    final quizTitleController = TextEditingController();
    String severity = 'MEDIUM';
    bool isPreview = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 16,
                left: 20,
                right: 20,
              ),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add Mistake Note',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: googleTextPrimary),
                      ),
                      TextButton.icon(
                        icon: Icon(isPreview ? Icons.edit : Icons.remove_red_eye, size: 16, color: googleBlue),
                        label: Text(isPreview ? 'Edit Note' : 'Preview MD', style: const TextStyle(fontSize: 12, color: googleBlue)),
                        onPressed: () => setSheetState(() => isPreview = !isPreview),
                      ),
                    ],
                  ),
                  const Divider(height: 1, thickness: 1, color: googleHairline),
                  const SizedBox(height: 12),
                  Expanded(
                    child: isPreview
                        ? ListView(
                            children: [
                              Text(titleController.text.isEmpty ? 'Untitled Topic' : titleController.text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              MarkdownBody(
                                data: takeawayController.text.isEmpty ? '_No markdown body entered yet._' : takeawayController.text,
                                selectable: true,
                                onTapLink: (text, href, title) async {
                                  if (href != null) {
                                    final uri = Uri.parse(href);
                                    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                },
                              ),
                            ],
                          )
                        : ListView(
                            children: [
                              TextField(
                                controller: titleController,
                                decoration: const InputDecoration(
                                  labelText: 'Topic / Formula Name',
                                  labelStyle: TextStyle(fontSize: 13, color: googleTextSecondary),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: subjectController,
                                      decoration: const InputDecoration(
                                        labelText: 'Subject',
                                        labelStyle: TextStyle(fontSize: 13, color: googleTextSecondary),
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  DropdownButton<String>(
                                    value: severity,
                                    underline: const SizedBox(),
                                    items: const [
                                      DropdownMenuItem(value: 'HIGH', child: Text('HIGH', style: TextStyle(color: severityHigh, fontWeight: FontWeight.bold, fontSize: 12))),
                                      DropdownMenuItem(value: 'MEDIUM', child: Text('MED', style: TextStyle(color: severityMed, fontWeight: FontWeight.bold, fontSize: 12))),
                                      DropdownMenuItem(value: 'LOW', child: Text('LOW', style: TextStyle(color: severityLow, fontWeight: FontWeight.bold, fontSize: 12))),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setSheetState(() => severity = val);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: quizTitleController,
                                decoration: const InputDecoration(
                                  labelText: 'Quiz / Test Source (Optional)',
                                  labelStyle: TextStyle(fontSize: 13, color: googleTextSecondary),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: questionController,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'Question or GateOverflow Link',
                                  labelStyle: TextStyle(fontSize: 13, color: googleTextSecondary),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: takeawayController,
                                maxLines: 6,
                                decoration: const InputDecoration(
                                  labelText: 'Key Takeaways & ChatGPT Notes (Markdown supported)',
                                  hintText: 'Paste explanation, formulas, c!=0 -> independent, links...',
                                  labelStyle: TextStyle(fontSize: 13, color: googleTextSecondary),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final topic = titleController.text.trim();
                        final takeaway = takeawayController.text.trim();
                        if (topic.isNotEmpty) {
                          await DatabaseService.instance.insertMistakeRecord(
                            subject: subjectController.text.trim(),
                            topic: topic,
                            questionText: questionController.text.trim(),
                            wrongAnswer: wrongAnswerController.text.trim(),
                            correctAnswer: correctAnswerController.text.trim(),
                            keyTakeaway: takeaway.isNotEmpty ? takeaway : topic,
                            quizTitle: quizTitleController.text.trim(),
                            severity: severity,
                          );
                          await _loadData();
                          widget.onDataChanged();
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: googleBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Save Mistake Note'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMistakeDetails(Map<String, dynamic> m) {
    final topic = m['topic'] ?? 'Mistake Record';
    final subject = m['subject'] ?? 'General';
    final severity = m['severity'] ?? 'MEDIUM';
    final status = m['status'] ?? 'UNRESOLVED';
    final isResolved = status == 'RESOLVED';
    final qText = m['question_text'] ?? '';
    final reason = m['mistake_reason'] ?? '';
    final takeaway = m['key_takeaway'] ?? '';
    final quiz = m['quiz_title'] ?? '';

    Color sevColor = severityMed;
    if (severity == 'HIGH') sevColor = severityHigh;
    if (severity == 'LOW') sevColor = severityLow;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: sevColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      severity,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: sevColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      topic,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: googleTextPrimary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18, color: googleTextSecondary),
                    tooltip: 'Copy Note',
                    onPressed: () {
                      final fullText = '$topic ($subject)\n\n$qText\n\nTakeaway:\n$takeaway';
                      Clipboard.setData(ClipboardData(text: fullText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Note copied to clipboard!')),
                      );
                    },
                  ),
                ],
              ),
              Text(
                '$subject ${quiz.isNotEmpty ? "• $quiz" : ""}',
                style: const TextStyle(fontSize: 12, color: googleTextSecondary),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 1, color: googleHairline),
              const SizedBox(height: 12),

              Expanded(
                child: ListView(
                  children: [
                    if (qText.isNotEmpty) ...[
                      const Text('QUESTION / SOURCE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: googleTextSecondary)),
                      const SizedBox(height: 6),
                      MarkdownBody(
                        data: qText,
                        selectable: true,
                        onTapLink: (text, href, title) async {
                          if (href != null) {
                            final uri = Uri.parse(href);
                            if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (reason.isNotEmpty) ...[
                      const Text('WHY IT WENT WRONG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: severityMed)),
                      const SizedBox(height: 6),
                      Text(reason, style: const TextStyle(fontSize: 13, color: googleTextPrimary)),
                      const SizedBox(height: 16),
                    ],
                    if (takeaway.isNotEmpty) ...[
                      const Text('KEY TAKEAWAYS & FORMULAS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: googleBlue)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFD),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: googleHairline),
                        ),
                        child: MarkdownBody(
                          data: takeaway,
                          selectable: true,
                          onTapLink: (text, href, title) async {
                            if (href != null) {
                              final uri = Uri.parse(href);
                              if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(isResolved ? Icons.undo : Icons.check_circle_outline, size: 16),
                      label: Text(isResolved ? 'Mark Unresolved' : 'Mark Resolved'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isResolved ? googleTextSecondary : googleGreen,
                        side: BorderSide(color: isResolved ? googleBorder : googleGreen),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        await _toggleMistakeResolved(m, !isResolved);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMatrixDrilldown(String subject, String stage) async {
    final items = await DatabaseService.instance.getRevisitsForSubjectAndStage(subject, stage);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                    '$subject • $stage',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: googleTextPrimary),
                  ),
                  Text(
                    '${items.length} recall checkpoints in this retention cycle',
                    style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, thickness: 1, color: googleHairline),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(child: Text('No checkpoints found.'))
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (context, idx) {
                              final it = items[idx];
                              final isDone = (it['status'] as String?)?.toUpperCase() == 'DONE';
                              final topic = it['topic'] ?? '';
                              final dueDate = it['due_date'] ?? '';

                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        GoogleCheckbox(
                                          value: isDone,
                                          onChanged: (val) async {
                                            await _toggleRevisit(it, val);
                                            final updated = await DatabaseService.instance.getRevisitsForSubjectAndStage(subject, stage);
                                            setModalState(() {
                                              items.clear();
                                              items.addAll(updated);
                                            });
                                          },
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                topic,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDone ? googleTextSecondary : googleTextPrimary,
                                                  decoration: isDone ? TextDecoration.lineThrough : null,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text('Due: $dueDate', style: const TextStyle(fontSize: 11, color: googleTextSecondary)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.only(left: 44),
                                    child: Divider(height: 1, thickness: 1, color: googleHairline),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Sub-Tab Switcher
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
                  _buildSubTab(0, 'Due / Backlog', _dueBacklog.length),
                  _buildSubTab(1, 'Retention Matrix', 0),
                  _buildSubTab(2, 'Mistakes', _mistakes.length),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: googleHairline),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: googleBlue))
                : IndexedStack(
                    index: _activeSubIndex,
                    children: [
                      _buildDueBacklogView(),
                      _buildRetentionMatrixView(),
                      _buildMistakesView(),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: _activeSubIndex == 2
          ? FloatingActionButton(
              elevation: 3,
              backgroundColor: googleBlue,
              foregroundColor: Colors.white,
              onPressed: _showAddMistakeSheet,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildSubTab(int index, String title, int count) {
    final isSelected = _activeSubIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _activeSubIndex = index),
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
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? googleBlue : googleTextSecondary,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? googleBlue : const Color(0xFFDADCE0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 9,
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

  // --- Sub-Tab 0: Due & Backlog ---

  Widget _buildDueBacklogView() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // DPP protocol banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: const Color(0xFFF8FAFD),
          child: Row(
            children: [
              const Icon(Icons.psychology, size: 18, color: googleBlue),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Solve assigned DPPs & practice questions on GateOverflow',
                  style: TextStyle(fontSize: 12, color: googleTextPrimary),
                ),
              ),
              InkWell(
                onTap: () async {
                  final uri = Uri.parse('https://gateoverflow.in');
                  if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: const Text('GO DPPs ↗', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue)),
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: googleHairline),

        if (_dueBacklog.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
            child: const Center(
              child: Text(
                'No pending revisits in backlog! You are completely caught up.',
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
                  'ACTIVE RECALL BACKLOG',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: googleTextSecondary, letterSpacing: 0.6),
                ),
                Text('${_dueBacklog.length} items', style: const TextStyle(fontSize: 11, color: googleTextSecondary)),
              ],
            ),
          ),
          ..._dueBacklog.map((rev) {
            final isDone = (rev['status'] as String?)?.toUpperCase() == 'DONE';
            final stage = rev['stage'] ?? 'Recall';
            final dur = rev['duration_mins'] ?? 25;
            final topic = rev['topic'] ?? '';
            final due = rev['due_date'] ?? '';

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
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: googleTextPrimary),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('$dur mins • Due: $due', style: const TextStyle(fontSize: 11, color: googleTextSecondary)),
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
    );
  }

  // --- Sub-Tab 1: Retention Matrix Heatmap ---

  Widget _buildRetentionMatrixView() {
    final stages = ['Day 1', 'Day 4', 'Day 7', 'Day 14', 'Day 30'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
      children: [
        const Text(
          'EBBINGHAUS RETENTION ENGINE',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: googleTextSecondary, letterSpacing: 0.6),
        ),
        const SizedBox(height: 6),
        const Text(
          'Completion rates across memory checkpoints (1, 4, 7, 14, 30 days). Tap any cell to view scheduled lectures.',
          style: TextStyle(fontSize: 12, color: googleTextSecondary, height: 1.3),
        ),
        const SizedBox(height: 20),

        // Heatmap Grid
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            horizontalMargin: 8,
            columnSpacing: 12,
            headingRowHeight: 40,
            dataRowMinHeight: 48,
            dataRowMaxHeight: 52,
            columns: [
              const DataColumn(label: Text('Subject', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              ...stages.map((s) => DataColumn(
                    label: Text(s, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  )),
            ],
            rows: _matrixData.map((row) {
              final subject = row['subject'] as String;
              final stMap = row['stages'] as Map<String, List<int>>;

              return DataRow(
                cells: [
                  DataCell(
                    SizedBox(
                      width: 140,
                      child: Text(
                        subject,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: googleTextPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  ...stages.map((st) {
                    final data = stMap[st] ?? [0, 0];
                    final total = data[0];
                    final done = data[1];
                    final pct = total > 0 ? (done / total) : 0.0;

                    Color bg = const Color(0xFFF8FAFD);
                    Color textCol = googleTextSecondary;
                    if (total > 0) {
                      if (pct == 1.0) {
                        bg = googleBlue;
                        textCol = Colors.white;
                      } else if (pct > 0.0) {
                        bg = const Color(0xFFD3E3FD);
                        textCol = googleOnBlueContainer;
                      }
                    }

                    return DataCell(
                      InkWell(
                        onTap: total > 0 ? () => _showMatrixDrilldown(subject, st) : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 44,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: googleHairline),
                          ),
                          child: Text(
                            total > 0 ? '${(pct * 100).toInt()}%' : '-',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: textCol,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // --- Sub-Tab 2: Mistake Notebook ---

  Widget _buildMistakesView() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Filter Chips Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              _buildFilterChip('ALL', 'All', _mistakeStatusFilter == 'ALL', (v) {
                setState(() => _mistakeStatusFilter = 'ALL');
                _loadData();
              }),
              const SizedBox(width: 8),
              _buildFilterChip('UNRESOLVED', 'Unresolved', _mistakeStatusFilter == 'UNRESOLVED', (v) {
                setState(() => _mistakeStatusFilter = 'UNRESOLVED');
                _loadData();
              }),
              const SizedBox(width: 8),
              _buildFilterChip('RESOLVED', 'Resolved', _mistakeStatusFilter == 'RESOLVED', (v) {
                setState(() => _mistakeStatusFilter = 'RESOLVED');
                _loadData();
              }),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: googleHairline),

        if (_mistakes.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
            child: const Center(
              child: Text(
                'No mistake records found matching filters.\nTap + to log tricky questions or ChatGPT notes!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: googleTextSecondary, height: 1.4),
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'LOGGED TRAPS & CONCEPTS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: googleTextSecondary, letterSpacing: 0.6),
                ),
                Text('${_mistakes.length} notes', style: const TextStyle(fontSize: 11, color: googleTextSecondary)),
              ],
            ),
          ),
          ..._mistakes.map((m) {
            final topic = m['topic'] ?? 'Untitled';
            final subject = m['subject'] ?? '';
            final severity = m['severity'] ?? 'MEDIUM';
            final isResolved = (m['status'] as String?)?.toUpperCase() == 'RESOLVED';
            final qText = m['question_text'] ?? '';
            final quiz = m['quiz_title'] ?? '';

            Color sevColor = severityMed;
            if (severity == 'HIGH') sevColor = severityHigh;
            if (severity == 'LOW') sevColor = severityLow;

            return InkWell(
              onTap: () => _showMistakeDetails(m),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 20, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 4, right: 12),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: sevColor),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      topic,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isResolved ? googleTextSecondary : googleTextPrimary,
                                        decoration: isResolved ? TextDecoration.lineThrough : null,
                                      ),
                                    ),
                                  ),
                                  if (isResolved)
                                    const Icon(Icons.check_circle, size: 16, color: googleGreen),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$subject ${quiz.isNotEmpty ? "• $quiz" : ""}',
                                style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                              ),
                              if (qText.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  qText.split('\n').first,
                                  style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 38),
                    child: Divider(height: 1, thickness: 1, color: googleHairline),
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildFilterChip(String key, String label, bool isSelected, Function(bool) onSelected) {
    return FilterChip(
      selected: isSelected,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? googleBlue : googleTextSecondary,
      ),
      backgroundColor: const Color(0xFFF1F3F4),
      selectedColor: const Color(0xFFD3E3FD),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: onSelected,
    );
  }
}
