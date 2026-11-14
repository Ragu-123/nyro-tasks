import 'package:flutter/material.dart';
import '../../../utils/theme.dart';

class NoteTagsEditor extends StatefulWidget {
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  const NoteTagsEditor({
    Key? key,
    required this.tags,
    required this.onChanged,
  }) : super(key: key);

  @override
  _NoteTagsEditorState createState() => _NoteTagsEditorState();
}

class _NoteTagsEditorState extends State<NoteTagsEditor> {
  late TextEditingController _controller;
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _tags = List<String>.from(widget.tags);
  }

  @override
  void didUpdateWidget(covariant NoteTagsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tags != oldWidget.tags) {
      _tags = List<String>.from(widget.tags);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTag() {
    final text = _controller.text.trim();
    if (text.isEmpty || _tags.contains(text)) return;

    setState(() {
      _tags.add(text);
      _controller.clear();
    });
    widget.onChanged(_tags);
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
    widget.onChanged(_tags);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _tags.map((tag) {
              return Chip(
                label: Text('#$tag', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: googleBlue)),
                backgroundColor: Colors.black.withOpacity(0.05),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                deleteIcon: const Icon(Icons.close, size: 14, color: googleTextSecondary),
                onDeleted: () => _removeTag(tag),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            const Icon(Icons.tag_rounded, size: 16, color: googleTextSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                style: const TextStyle(fontSize: 12, color: googleTextPrimary),
                decoration: const InputDecoration(
                  hintText: 'Add tag (e.g. Formula, Revision)',
                  hintStyle: TextStyle(fontSize: 12, color: Color(0xFF9AA0A6)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
                onSubmitted: (_) => _addTag(),
              ),
            ),
            TextButton(
              onPressed: _addTag,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: googleBlue)),
            ),
          ],
        ),
      ],
    );
  }
}
