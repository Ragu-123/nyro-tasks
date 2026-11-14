import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/database_service.dart';
import '../../data/keep_note_model.dart';
import '../../utils/theme.dart';
import '../../widgets/top_banner_notification.dart';
import 'widgets/note_checklist_editor.dart';
import 'widgets/note_color_picker.dart';
import 'widgets/note_tags_editor.dart';

class NoteEditorSheet extends StatefulWidget {
  final KeepNote? note;
  final Function(KeepNote savedNote)? onSave;
  final VoidCallback? onDelete;

  const NoteEditorSheet({
    Key? key,
    this.note,
    this.onSave,
    this.onDelete,
  }) : super(key: key);

  @override
  _NoteEditorSheetState createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<NoteEditorSheet> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;

  late String _noteId;
  late String _selectedColor;
  late bool _isPinned;
  late bool _isArchived;
  late bool _isTodoList;
  late bool _isCode;
  late List<ChecklistItem> _todoItems;
  late List<String> _tags;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final n = widget.note;
    _noteId = n?.id ?? 'note_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    _titleController = TextEditingController(text: n?.title ?? '');
    _contentController = TextEditingController(text: n?.content ?? '');

    _selectedColor = n?.color ?? '#FFFFFF';
    _isPinned = n?.isPinned ?? false;
    _isArchived = n?.isArchived ?? false;
    _isTodoList = n?.isTodoList ?? false;
    _isCode = n?.isCode ?? false;
    _todoItems = n?.todoItems != null ? List<ChecklistItem>.from(n!.todoItems) : [];
    _tags = n?.tags != null ? List<String>.from(n!.tags) : [];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Color get _backgroundColor {
    return KeepNoteColors.getColor(_selectedColor, isDark: false);
  }

  void _toggleTodoList() {
    setState(() {
      _isTodoList = !_isTodoList;
      if (_isTodoList && _todoItems.isEmpty && _contentController.text.trim().isNotEmpty) {
        final lines = _contentController.text.split('\n').where((l) => l.trim().isNotEmpty);
        _todoItems = lines
            .map((l) => ChecklistItem(
                  id: 'item_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}',
                  text: l.trim(),
                  checked: false,
                ))
            .toList();
      }
    });
  }

  Future<void> _handleSave() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty && _todoItems.isEmpty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final savedNote = KeepNote(
        id: _noteId,
        title: title,
        content: content,
        color: _selectedColor,
        isPinned: _isPinned,
        isArchived: _isArchived,
        isTodoList: _isTodoList,
        todoItems: _todoItems,
        tags: _tags,
        isCode: _isCode,
        createdAt: widget.note?.createdAt ?? now,
        updatedAt: now,
      );

      await DatabaseService.instance.saveKeepNote(savedNote);
      widget.onSave?.call(savedNote);

      if (mounted) {
        Navigator.pop(context);
        TopBanner.show(
          context,
          title: widget.note == null ? 'Note Created' : 'Note Saved',
          message: title.isNotEmpty ? title : 'Note updated in Keep',
          icon: Icons.check_circle_outline_rounded,
          color: googleGreen,
        );
      }
    } catch (e) {
      debugPrint('Error saving note: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        TopBanner.show(
          context,
          title: 'Error Saving Note',
          message: e.toString(),
          icon: Icons.error_outline_rounded,
          color: googleRed,
        );
      }
    }
  }

  Future<void> _handleDelete() async {
    if (widget.note == null) {
      Navigator.pop(context);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Note?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: const Text('This note will be permanently deleted from Keep.', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: googleTextSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: googleRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.deleteKeepNote(_noteId);
      widget.onDelete?.call();
      if (mounted) {
        Navigator.pop(context);
        TopBanner.show(
          context,
          title: 'Note Deleted',
          message: 'Note removed from Keep.',
          icon: Icons.delete_outline_rounded,
          color: googleRed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Drag Handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 2. Actions Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: googleTextSecondary, size: 22),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _isTodoList ? Icons.check_box_rounded : Icons.check_box_outlined,
                          color: _isTodoList ? googleBlue : googleTextSecondary,
                          size: 22,
                        ),
                        tooltip: 'Checklist Mode',
                        onPressed: _toggleTodoList,
                      ),
                      IconButton(
                        icon: Icon(
                          _isCode ? Icons.code_rounded : Icons.data_object_rounded,
                          color: _isCode ? googleBlue : googleTextSecondary,
                          size: 22,
                        ),
                        tooltip: 'Monospace Code Note',
                        onPressed: () => setState(() => _isCode = !_isCode),
                      ),
                      IconButton(
                        icon: Icon(
                          _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                          color: _isPinned ? googleBlue : googleTextSecondary,
                          size: 22,
                        ),
                        tooltip: _isPinned ? 'Unpin' : 'Pin to top',
                        onPressed: () => setState(() => _isPinned = !_isPinned),
                      ),
                      IconButton(
                        icon: Icon(
                          _isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                          color: _isArchived ? googleBlue : googleTextSecondary,
                          size: 22,
                        ),
                        tooltip: _isArchived ? 'Unarchive' : 'Archive',
                        onPressed: () => setState(() => _isArchived = !_isArchived),
                      ),
                      if (widget.note != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: googleRed, size: 22),
                          tooltip: 'Delete Note',
                          onPressed: _handleDelete,
                        ),
                      const SizedBox(width: 4),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _handleSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: googleBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 3. Title Field
              TextField(
                controller: _titleController,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: googleTextPrimary,
                  letterSpacing: -0.4,
                ),
                decoration: const InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9AA0A6),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
              ),

              const SizedBox(height: 8),

              // 4. Content or Modular Checklist
              if (!_isTodoList) ...[
                TextField(
                  controller: _contentController,
                  maxLines: 8,
                  minLines: 4,
                  style: TextStyle(
                    fontSize: 15,
                    color: googleTextPrimary,
                    fontFamily: _isCode ? 'monospace' : null,
                    height: 1.45,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Take a note...',
                    hintStyle: TextStyle(fontSize: 15, color: Color(0xFF9AA0A6)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ] else ...[
                NoteChecklistEditor(
                  items: _todoItems,
                  onChanged: (newItems) => setState(() => _todoItems = newItems),
                ),
              ],

              const SizedBox(height: 12),

              // 5. Modular Tags Editor
              NoteTagsEditor(
                tags: _tags,
                onChanged: (newTags) => setState(() => _tags = newTags),
              ),

              const Divider(height: 24, thickness: 0.8),

              // 6. Modular Color Picker
              NoteColorPicker(
                selectedColor: _selectedColor,
                onColorSelected: (hex) => setState(() => _selectedColor = hex),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
