import 'dart:convert';
import 'package:flutter/material.dart';

class ChecklistItem {
  final String id;
  final String text;
  final bool checked;

  ChecklistItem({
    required this.id,
    required this.text,
    this.checked = false,
  });

  ChecklistItem copyWith({
    String? id,
    String? text,
    bool? checked,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      text: text ?? this.text,
      checked: checked ?? this.checked,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'checked': checked,
    };
  }

  factory ChecklistItem.fromMap(Map<String, dynamic> map) {
    return ChecklistItem(
      id: map['id']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      checked: map['checked'] == true || map['checked'] == 1,
    );
  }
}

class KeepNoteColor {
  final String name;
  final String hex;
  final Color lightColor;
  final Color darkColor;

  const KeepNoteColor({
    required this.name,
    required this.hex,
    required this.lightColor,
    required this.darkColor,
  });
}

class KeepNoteColors {
  static const List<KeepNoteColor> palette = [
    KeepNoteColor(
      name: 'Default',
      hex: '#FFFFFF',
      lightColor: Color(0xFFFFFFFF),
      darkColor: Color(0xFF202124),
    ),
    KeepNoteColor(
      name: 'Coral',
      hex: '#F28B82',
      lightColor: Color(0xFFF28B82),
      darkColor: Color(0xFF5C2B29),
    ),
    KeepNoteColor(
      name: 'Peach',
      hex: '#FBBC04',
      lightColor: Color(0xFFFBBC04),
      darkColor: Color(0xFF614A19),
    ),
    KeepNoteColor(
      name: 'Sand',
      hex: '#FFF475',
      lightColor: Color(0xFFFFF475),
      darkColor: Color(0xFF635D19),
    ),
    KeepNoteColor(
      name: 'Mint',
      hex: '#CCFF90',
      lightColor: Color(0xFFCCFF90),
      darkColor: Color(0xFF345920),
    ),
    KeepNoteColor(
      name: 'Sage',
      hex: '#A7FFEB',
      lightColor: Color(0xFFA7FFEB),
      darkColor: Color(0xFF16504B),
    ),
    KeepNoteColor(
      name: 'Fog',
      hex: '#CBF0F8',
      lightColor: Color(0xFFCBF0F8),
      darkColor: Color(0xFF2D555E),
    ),
    KeepNoteColor(
      name: 'Storm',
      hex: '#AECBFA',
      lightColor: Color(0xFFAECBFA),
      darkColor: Color(0xFF1E3A5F),
    ),
    KeepNoteColor(
      name: 'Dusk',
      hex: '#D7AEFB',
      lightColor: Color(0xFFD7AEFB),
      darkColor: Color(0xFF42275E),
    ),
    KeepNoteColor(
      name: 'Blossom',
      hex: '#FDCFE8',
      lightColor: Color(0xFFFDCFE8),
      darkColor: Color(0xFF5B2245),
    ),
    KeepNoteColor(
      name: 'Clay',
      hex: '#E6C9A8',
      lightColor: Color(0xFFE6C9A8),
      darkColor: Color(0xFF442F19),
    ),
    KeepNoteColor(
      name: 'Chalk',
      hex: '#E8EAED',
      lightColor: Color(0xFFE8EAED),
      darkColor: Color(0xFF3C3F43),
    ),
  ];

  static Color getColor(String hex, {bool isDark = false}) {
    final clean = hex.toUpperCase().trim();
    for (final item in palette) {
      if (item.hex.toUpperCase() == clean) {
        return isDark ? item.darkColor : item.lightColor;
      }
    }
    return isDark ? const Color(0xFF202124) : Colors.white;
  }
}

class KeepNote {
  final String id;
  final String title;
  final String content;
  final String color;
  final bool isPinned;
  final bool isArchived;
  final bool isTodoList;
  final List<ChecklistItem> todoItems;
  final List<String> tags;
  final bool isCode;
  final int createdAt;
  final int updatedAt;

  KeepNote({
    required this.id,
    this.title = '',
    this.content = '',
    this.color = '#FFFFFF',
    this.isPinned = false,
    this.isArchived = false,
    this.isTodoList = false,
    List<ChecklistItem>? todoItems,
    List<String>? tags,
    this.isCode = false,
    int? createdAt,
    int? updatedAt,
  })  : todoItems = todoItems ?? const [],
        tags = tags ?? const [],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  KeepNote copyWith({
    String? id,
    String? title,
    String? content,
    String? color,
    bool? isPinned,
    bool? isArchived,
    bool? isTodoList,
    List<ChecklistItem>? todoItems,
    List<String>? tags,
    bool? isCode,
    int? createdAt,
    int? updatedAt,
  }) {
    return KeepNote(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      color: color ?? this.color,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isTodoList: isTodoList ?? this.isTodoList,
      todoItems: todoItems ?? this.todoItems,
      tags: tags ?? this.tags,
      isCode: isCode ?? this.isCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'color': color,
      'is_pinned': isPinned ? 1 : 0,
      'is_archived': isArchived ? 1 : 0,
      'is_todo_list': isTodoList ? 1 : 0,
      'todo_items_json': jsonEncode(todoItems.map((e) => e.toMap()).toList()),
      'tags_json': jsonEncode(tags),
      'is_code': isCode ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory KeepNote.fromMap(Map<String, dynamic> map) {
    List<ChecklistItem> items = [];
    if (map['todo_items_json'] != null) {
      try {
        final decoded = jsonDecode(map['todo_items_json'] as String);
        if (decoded is List) {
          items = decoded.map((e) => ChecklistItem.fromMap(e as Map<String, dynamic>)).toList();
        }
      } catch (_) {}
    }

    List<String> tagsList = [];
    if (map['tags_json'] != null) {
      try {
        final decoded = jsonDecode(map['tags_json'] as String);
        if (decoded is List) {
          tagsList = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    return KeepNote(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      color: map['color']?.toString() ?? '#FFFFFF',
      isPinned: map['is_pinned'] == 1 || map['is_pinned'] == true,
      isArchived: map['is_archived'] == 1 || map['is_archived'] == true,
      isTodoList: map['is_todo_list'] == 1 || map['is_todo_list'] == true,
      todoItems: items,
      tags: tagsList,
      isCode: map['is_code'] == 1 || map['is_code'] == true,
      createdAt: (map['created_at'] is int)
          ? map['created_at'] as int
          : int.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: (map['updated_at'] is int)
          ? map['updated_at'] as int
          : int.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
