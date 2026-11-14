import 'package:flutter/material.dart';
import '../../../utils/theme.dart';

class KeepEmptyState extends StatelessWidget {
  final bool isFiltered;
  final VoidCallback onClearFilter;

  const KeepEmptyState({
    Key? key,
    this.isFiltered = false,
    required this.onClearFilter,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: googleBlue.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isFiltered ? Icons.search_off_rounded : Icons.lightbulb_outline_rounded,
                size: 48,
                color: googleBlue,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isFiltered ? 'No matching notes found' : 'Notes you add appear here',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: googleTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isFiltered
                  ? 'Try searching with different keywords or clearing tag filters.'
                  : 'Capture quick thoughts, GATE formulas, checklists, and revision summaries in Keep.',
              style: const TextStyle(
                fontSize: 13,
                color: googleTextSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            if (isFiltered) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onClearFilter,
                icon: const Icon(Icons.clear_all_rounded, size: 16, color: googleBlue),
                label: const Text('Clear Filters', style: TextStyle(color: googleBlue, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: googleBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
