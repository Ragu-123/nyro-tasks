import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../../data/database_service.dart';
import '../../data/keep_note_model.dart';
import 'desktop_auth_handler.dart';

class DesktopNotesHandler {
  final DesktopAuthHandler authHandler;

  const DesktopNotesHandler({required this.authHandler});

  Future<void> handleGetNotes(HttpRequest request) async {
    try {
      final queryParams = request.uri.queryParameters;
      final includeArchived = queryParams['archived'] == '1' || queryParams['archived'] == 'true';
      final search = queryParams['search'];
      final tag = queryParams['tag'];

      final notes = await DatabaseService.instance.getKeepNotes(
        includeArchived: includeArchived,
        searchQuery: search,
        tag: tag,
      );

      final jsonNotes = notes.map((n) => n.toMap()).toList();
      final tags = await DatabaseService.instance.getAllKeepTags();

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'success': true,
        'count': notes.length,
        'notes': jsonNotes,
        'all_tags': tags,
      }));
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleCreateNote(HttpRequest request) async {
    try {
      final bodyStr = await utf8.decodeStream(request);
      final json = jsonDecode(bodyStr);

      final title = json['title']?.toString().trim() ?? '';
      final content = json['content']?.toString().trim() ?? '';
      final color = json['color']?.toString().trim() ?? '#FFFFFF';
      final isPinned = json['is_pinned'] == true || json['is_pinned'] == 1;
      final isArchived = json['is_archived'] == true || json['is_archived'] == 1;
      final isTodoList = json['is_todo_list'] == true || json['is_todo_list'] == 1;
      final isCode = json['is_code'] == true || json['is_code'] == 1;

      List<ChecklistItem> items = [];
      if (json['todo_items'] is List) {
        for (var it in json['todo_items']) {
          if (it is Map<String, dynamic>) {
            items.add(ChecklistItem.fromMap(it));
          } else if (it is String && it.trim().isNotEmpty) {
            items.add(ChecklistItem(
              id: 'item_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}',
              text: it.trim(),
              checked: false,
            ));
          }
        }
      }

      List<String> tags = [];
      if (json['tags'] is List) {
        tags = (json['tags'] as List).map((t) => t.toString().trim()).where((t) => t.isNotEmpty).toList();
      }

      final noteId = json['id']?.toString() ?? 'note_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
      final now = DateTime.now().millisecondsSinceEpoch;

      final note = KeepNote(
        id: noteId,
        title: title,
        content: content,
        color: color,
        isPinned: isPinned,
        isArchived: isArchived,
        isTodoList: isTodoList,
        todoItems: items,
        tags: tags,
        isCode: isCode,
        createdAt: now,
        updatedAt: now,
      );

      await DatabaseService.instance.saveKeepNote(note);

      request.response.statusCode = HttpStatus.created;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'note': note.toMap()}));
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleUpdateNote(HttpRequest request, String noteId) async {
    try {
      final existing = await DatabaseService.instance.getKeepNoteById(noteId);
      if (existing == null) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Note not found'}));
        await request.response.close();
        return;
      }

      final bodyStr = await utf8.decodeStream(request);
      final json = jsonDecode(bodyStr);

      final title = json['title'] != null ? json['title'].toString().trim() : existing.title;
      final content = json['content'] != null ? json['content'].toString().trim() : existing.content;
      final color = json['color'] != null ? json['color'].toString().trim() : existing.color;
      final isPinned = json['is_pinned'] != null ? (json['is_pinned'] == true || json['is_pinned'] == 1) : existing.isPinned;
      final isArchived = json['is_archived'] != null ? (json['is_archived'] == true || json['is_archived'] == 1) : existing.isArchived;
      final isTodoList = json['is_todo_list'] != null ? (json['is_todo_list'] == true || json['is_todo_list'] == 1) : existing.isTodoList;
      final isCode = json['is_code'] != null ? (json['is_code'] == true || json['is_code'] == 1) : existing.isCode;

      List<ChecklistItem> items = existing.todoItems;
      if (json['todo_items'] is List) {
        items = [];
        for (var it in json['todo_items']) {
          if (it is Map<String, dynamic>) {
            items.add(ChecklistItem.fromMap(it));
          }
        }
      }

      List<String> tags = existing.tags;
      if (json['tags'] is List) {
        tags = (json['tags'] as List).map((t) => t.toString().trim()).where((t) => t.isNotEmpty).toList();
      }

      final updated = existing.copyWith(
        title: title,
        content: content,
        color: color,
        isPinned: isPinned,
        isArchived: isArchived,
        isTodoList: isTodoList,
        todoItems: items,
        tags: tags,
        isCode: isCode,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await DatabaseService.instance.saveKeepNote(updated);

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'note': updated.toMap()}));
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleDeleteNote(HttpRequest request, String noteId) async {
    try {
      await DatabaseService.instance.deleteKeepNote(noteId);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'id': noteId}));
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }
}
