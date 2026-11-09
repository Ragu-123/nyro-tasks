import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/utils/url_helper.dart';

void showAddMistakeModalSheet(
  BuildContext context, {
  required VoidCallback onSaved,
  String? initialSubject,
  List<String>? availableSubjects,
}) {
  final topicController = TextEditingController();
  final quizController = TextEditingController();
  final questionController = TextEditingController();
  final reasonController = TextEditingController();
  final takeawayController = TextEditingController();
  String severity = 'MEDIUM';
  int modeTab = 0; // 0: Write Note, 1: Markdown Preview

  final subjs = availableSubjects ?? ['Engineering Mathematics'];
  String selectedSubject = (initialSubject != null && initialSubject != 'All Subjects' && subjs.contains(initialSubject))
      ? initialSubject
      : (subjs.isNotEmpty && subjs.first != 'All Subjects' ? subjs.first : 'Engineering Mathematics');

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
          return Container(
            height: MediaQuery.of(context).size.height * 0.88,
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'New Mistake Record',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: googleTextPrimary),
                    ),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F3F4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => setSheetState(() => modeTab = 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: modeTab == 0 ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'Write',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: modeTab == 0 ? FontWeight.bold : FontWeight.normal,
                                  color: modeTab == 0 ? googleBlue : googleTextSecondary,
                                ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setSheetState(() => modeTab = 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: modeTab == 1 ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'Preview',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: modeTab == 1 ? FontWeight.bold : FontWeight.normal,
                                  color: modeTab == 1 ? googleBlue : googleTextSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, thickness: 1, color: googleHairline),
                const SizedBox(height: 12),

                Expanded(
                  child: modeTab == 1
                      ? ListView(
                          children: [
                            Text(
                              topicController.text.isEmpty ? 'Untitled Topic' : topicController.text,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$selectedSubject • Severity: $severity',
                              style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                            ),
                            const SizedBox(height: 12),
                            if (reasonController.text.isNotEmpty) ...[
                              const Text('WHY IT WENT WRONG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: severityMed)),
                              const SizedBox(height: 4),
                              Text(reasonController.text, style: const TextStyle(fontSize: 13)),
                              const SizedBox(height: 12),
                            ],
                            const Text('TAKEAWAYS & FORMULAS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleBlue)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFD),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: googleHairline),
                              ),
                              child: MarkdownBody(
                                data: takeawayController.text.isEmpty ? '_No markdown entered yet._' : takeawayController.text,
                                selectable: true,
                                onTapLink: (text, href, title) => openExternalUrl(href),
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          children: [
                            // 1. Topic Field
                            _buildInputBox(
                              controller: topicController,
                              label: 'Topic / Core Concept',
                              hint: 'e.g., Matrix Limits, Skew-Symmetric eigenvalues',
                            ),
                            const SizedBox(height: 12),

                            // 2. Subject Dropdown & Severity Selector
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'SUBJECT',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: googleTextSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFD),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: googleBorder),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: subjs.contains(selectedSubject) ? selectedSubject : (subjs.isNotEmpty ? subjs.first : null),
                                            isExpanded: true,
                                            icon: const Icon(Icons.arrow_drop_down_rounded, color: googleBlue),
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: googleTextPrimary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            items: subjs.where((s) => s != 'All Subjects').map((s) {
                                              return DropdownMenuItem<String>(
                                                value: s,
                                                child: Text(s, overflow: TextOverflow.ellipsis),
                                              );
                                            }).toList(),
                                            onChanged: (val) {
                                              if (val != null) {
                                                setSheetState(() => selectedSubject = val);
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('SEVERITY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: googleTextSecondary)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        _buildSeverityPill('HIGH', severity == 'HIGH', severityHigh, () => setSheetState(() => severity = 'HIGH')),
                                        const SizedBox(width: 4),
                                        _buildSeverityPill('MED', severity == 'MEDIUM', severityMed, () => setSheetState(() => severity = 'MEDIUM')),
                                        const SizedBox(width: 4),
                                        _buildSeverityPill('LOW', severity == 'LOW', severityLow, () => setSheetState(() => severity = 'LOW')),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 3. Quiz Source
                            _buildInputBox(
                              controller: quizController,
                              label: 'Quiz / Test Source (Optional)',
                              hint: 'e.g., Weekly Quiz 1, MadeEasy Mock 2',
                            ),
                            const SizedBox(height: 12),

                            // 4. Question Text
                            _buildInputBox(
                              controller: questionController,
                              label: 'Question / Problem Statement',
                              hint: 'Paste question text or notes',
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),

                            // 5. What Went Wrong
                            _buildInputBox(
                              controller: reasonController,
                              label: 'What Went Wrong (Reason)',
                              hint: 'Why was this answer wrong? Calculation slip or conceptual gap?',
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),

                            // 6. Key Takeaways & Formulas (Markdown)
                            _buildInputBox(
                              controller: takeawayController,
                              label: 'Key Takeaways & Formulas (Markdown)',
                              hint: 'Concept summary, formulas, bullet points, links...',
                              maxLines: 4,
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
                      final top = topicController.text.trim();
                      final reason = reasonController.text.trim();
                      final takeaway = takeawayController.text.trim();
                      if (top.isEmpty) {
                        return;
                      }
                      await DatabaseService.instance.insertMistakeRecord(
                        subject: selectedSubject,
                        topic: top,
                        questionText: questionController.text.trim(),
                        mistakeReason: reason,
                        keyTakeaway: takeaway.isNotEmpty ? takeaway : (reason.isNotEmpty ? reason : top),
                        quizTitle: quizController.text.trim(),
                        severity: severity,
                      );
                      onSaved();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: googleBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Save Mistake Record', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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

Widget _buildInputBox({
  required TextEditingController controller,
  required String label,
  required String hint,
  int maxLines = 1,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFD),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: googleHairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: googleTextSecondary)),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 14, color: googleTextPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9AA0A6)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.only(top: 4),
          ),
        ),
      ],
    ),
  );
}

Widget _buildSeverityPill(String label, bool isSelected, Color color, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? color : color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.white : color,
        ),
      ),
    ),
  );
}
