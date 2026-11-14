import 'dart:math';
import 'package:flutter/material.dart';
import '../../../data/keep_note_model.dart';
import '../../../utils/theme.dart';

class NoteChecklistEditor extends StatefulWidget {
  final List<ChecklistItem> items;
  final ValueChanged<List<ChecklistItem>> onChanged;

  const NoteChecklistEditor({
    Key? key,
    required this.items,
    required this.onChanged,
  }) : super(key: key);

  @override
  _NoteChecklistEditorState createState() => _NoteChecklistEditorState();
}

class _NoteChecklistEditorState extends State<NoteChecklistEditor> {
  late TextEditingController _newItemController;
  late List<ChecklistItem> _items;

  @override
  void initState() {
    super.initState();
    _newItemController = TextEditingController();
    _items = List<ChecklistItem>.from(widget.items);
  }

  @override
  void didUpdateWidget(covariant NoteChecklistEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items) {
      _items = List<ChecklistItem>.from(widget.items);
    }
  }

  @override
  void dispose() {
    _newItemController.dispose();
    super.dispose();
  }

  void _addItem() {
    final text = _newItemController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _items.add(ChecklistItem(
        id: 'item_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}',
        text: text,
        checked: false,
      ));
      _newItemController.clear();
    });
    widget.onChanged(_items);
  }

  void _toggleItem(int index, bool? checked) {
    setState(() {
      _items[index] = _items[index].copyWith(checked: checked ?? false);
    });
    widget.onChanged(_items);
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
    widget.onChanged(_items);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ..._items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Checkbox(
                  value: item.checked,
                  activeColor: googleBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: (val) => _toggleItem(idx, val),
                ),
                Expanded(
                  child: Text(
                    item.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: item.checked ? googleTextSecondary : googleTextPrimary,
                      decoration: item.checked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: googleTextSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _removeItem(idx),
                ),
              ],
            ),
          );
        }),
        // Add new checklist item input
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.add, size: 20, color: googleTextSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _newItemController,
                  style: const TextStyle(fontSize: 14, color: googleTextPrimary),
                  decoration: const InputDecoration(
                    hintText: 'List item',
                    hintStyle: TextStyle(fontSize: 14, color: Color(0xFF9AA0A6)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  onSubmitted: (_) => _addItem(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.check_rounded, color: googleBlue, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _addItem,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
