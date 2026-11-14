import 'package:flutter/material.dart';
import '../../../utils/theme.dart';

class KeepSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final bool isGridView;
  final VoidCallback onToggleView;
  final List<String> tags;
  final String? selectedTag;
  final ValueChanged<String?> onSelectTag;

  const KeepSearchBar({
    Key? key,
    required this.controller,
    required this.onQueryChanged,
    required this.onClear,
    required this.isGridView,
    required this.onToggleView,
    required this.tags,
    this.selectedTag,
    required this.onSelectTag,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Google Keep Floating Pill Search Bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F4),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              const Icon(Icons.search_rounded, color: googleTextSecondary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onQueryChanged,
                  style: const TextStyle(fontSize: 15, color: googleTextPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Search notes, checklists, tags...',
                    hintStyle: TextStyle(fontSize: 14, color: Color(0xFF70757A)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: googleTextSecondary),
                  onPressed: onClear,
                ),
              IconButton(
                icon: Icon(
                  isGridView ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
                  size: 20,
                  color: googleTextSecondary,
                ),
                tooltip: isGridView ? 'Switch to List View' : 'Switch to Grid View',
                onPressed: onToggleView,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),

        // 2. Horizontal Tag Filter Chips
        if (tags.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tags.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isAllSelected = selectedTag == null;
                  return ChoiceChip(
                    label: const Text('All Notes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    selected: isAllSelected,
                    selectedColor: googleBlue.withOpacity(0.15),
                    backgroundColor: const Color(0xFFF1F3F4),
                    labelStyle: TextStyle(
                      color: isAllSelected ? googleBlue : googleTextSecondary,
                      fontWeight: isAllSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    side: BorderSide.none,
                    onSelected: (_) => onSelectTag(null),
                  );
                }
                final tag = tags[index - 1];
                final isSelected = selectedTag == tag;
                return ChoiceChip(
                  label: Text('#$tag', style: const TextStyle(fontSize: 12)),
                  selected: isSelected,
                  selectedColor: googleBlue.withOpacity(0.15),
                  backgroundColor: const Color(0xFFF1F3F4),
                  labelStyle: TextStyle(
                    color: isSelected ? googleBlue : googleTextSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  side: BorderSide.none,
                  onSelected: (selected) => onSelectTag(selected ? tag : null),
                );
              },
            ),
          ),
      ],
    );
  }
}
