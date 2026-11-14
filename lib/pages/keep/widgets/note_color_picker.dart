import 'package:flutter/material.dart';
import '../../../data/keep_note_model.dart';
import '../../../utils/theme.dart';

class NoteColorPicker extends StatelessWidget {
  final String selectedColor;
  final ValueChanged<String> onColorSelected;

  const NoteColorPicker({
    Key? key,
    required this.selectedColor,
    required this.onColorSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Color',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: googleTextSecondary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: KeepNoteColors.palette.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = KeepNoteColors.palette[index];
              final isSelected = item.hex.toUpperCase() == selectedColor.toUpperCase();
              return GestureDetector(
                onTap: () => onColorSelected(item.hex),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: item.lightColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? googleBlue : const Color(0xFFCCCCCC),
                      width: isSelected ? 2.5 : 1.0,
                    ),
                    boxShadow: [
                      if (isSelected)
                        BoxShadow(
                          color: googleBlue.withOpacity(0.3),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded, size: 18, color: googleBlue)
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
