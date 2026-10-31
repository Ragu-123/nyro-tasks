import 'package:flutter/material.dart';
import 'package:tasks/utils/theme.dart';

class GoogleCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const GoogleCheckbox({
    Key? key,
    required this.value,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(right: 12.0, top: 2.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? googleBlue : Colors.white,
            border: Border.all(
              color: value ? googleBlue : const Color(0xFF747775),
              width: 1.75,
            ),
          ),
          child: value
              ? const Icon(
                  Icons.check,
                  size: 14,
                  color: Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}
