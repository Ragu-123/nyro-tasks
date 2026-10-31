import 'package:flutter/material.dart';
import 'package:tasks/utils/theme.dart';

class SubjectFilterModalSheet extends StatelessWidget {
  final List<String> subjects;
  final String selectedSubject;
  final ValueChanged<String> onSubjectSelected;

  const SubjectFilterModalSheet({
    Key? key,
    required this.subjects,
    required this.selectedSubject,
    required this.onSubjectSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          const SizedBox(height: 12),
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
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune_rounded, color: googleBlue, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Filter by Subject',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: googleTextPrimary,
                    ),
                  ),
                ),
                if (selectedSubject != 'All Subjects')
                  TextButton(
                    onPressed: () {
                      onSubjectSelected('All Subjects');
                      Navigator.pop(context);
                    },
                    child: const Text('Reset', style: TextStyle(color: googleBlue, fontWeight: FontWeight.w600)),
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: googleTextSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 1, color: googleHairline),

          // Subject Options List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: subjects.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 64, endIndent: 20, color: googleHairline),
              itemBuilder: (context, index) {
                final subject = subjects[index];
                final isSelected = subject == selectedSubject;
                final isAll = subject == 'All Subjects';

                return InkWell(
                  onTap: () {
                    onSubjectSelected(subject);
                    Navigator.pop(context);
                  },
                  child: Container(
                    color: isSelected ? const Color(0xFFE8F0FE).withOpacity(0.5) : Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected ? googleBlue : const Color(0xFFF1F3F4),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isAll ? Icons.apps_rounded : Icons.menu_book_rounded,
                            size: 18,
                            color: isSelected ? Colors.white : googleTextSecondary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            subject,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? googleBlue : googleTextPrimary,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded, color: googleBlue, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
