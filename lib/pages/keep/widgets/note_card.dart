import 'package:flutter/material.dart';
import '../../../data/keep_note_model.dart';
import '../../../utils/theme.dart';

class NoteCard extends StatelessWidget {
  final KeepNote note;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleArchive;
  final VoidCallback onDelete;
  final Function(String colorHex) onColorChanged;

  const NoteCard({
    Key? key,
    required this.note,
    required this.onTap,
    required this.onTogglePin,
    required this.onToggleArchive,
    required this.onDelete,
    required this.onColorChanged,
  }) : super(key: key);

  Color get _cardBgColor => KeepNoteColors.getColor(note.color, isDark: false);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: note.color.toUpperCase() == '#FFFFFF'
              ? const Color(0xFFE0E0E0)
              : Colors.black.withOpacity(0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          onLongPress: () => _showCardContextMenu(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header: Title & Pin Action
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: note.title.isNotEmpty
                          ? Text(
                              note.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: googleTextPrimary,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            )
                          : const SizedBox.shrink(),
                    ),
                    GestureDetector(
                      onTap: onTogglePin,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          note.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                          size: 18,
                          color: note.isPinned ? googleBlue : googleTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),

                if (note.title.isNotEmpty && (note.content.isNotEmpty || note.todoItems.isNotEmpty))
                  const SizedBox(height: 6),

                // Body: Checklist or Text Preview
                if (note.isTodoList && note.todoItems.isNotEmpty) ...[
                  ...note.todoItems.take(5).map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            item.checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            size: 15,
                            color: item.checked ? googleBlue : googleTextSecondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.text,
                              style: TextStyle(
                                fontSize: 13,
                                color: item.checked ? googleTextSecondary : googleTextPrimary,
                                decoration: item.checked ? TextDecoration.lineThrough : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (note.todoItems.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+ ${note.todoItems.length - 5} more items',
                        style: const TextStyle(fontSize: 11, color: googleTextSecondary, fontWeight: FontWeight.w500),
                      ),
                    ),
                ] else if (note.content.isNotEmpty) ...[
                  Text(
                    note.content,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: googleTextPrimary,
                      fontFamily: note.isCode ? 'monospace' : null,
                      height: 1.35,
                    ),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Tags Preview
                if (note.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: note.tags.take(3).map((t) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '#$t',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: googleTextSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCardContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(note.isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded, color: googleBlue),
              title: Text(note.isPinned ? 'Unpin Note' : 'Pin Note to Top'),
              onTap: () {
                Navigator.pop(ctx);
                onTogglePin();
              },
            ),
            ListTile(
              leading: Icon(note.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined, color: googleTextSecondary),
              title: Text(note.isArchived ? 'Unarchive Note' : 'Archive Note'),
              onTap: () {
                Navigator.pop(ctx);
                onToggleArchive();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: googleRed),
              title: const Text('Delete Note', style: TextStyle(color: googleRed)),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
            const Divider(height: 1),
            // Color Selector Bar in Context Menu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: KeepNoteColors.palette.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final item = KeepNoteColors.palette[idx];
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        onColorChanged(item.hex);
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: item.lightColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFCCCCCC), width: 1),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
