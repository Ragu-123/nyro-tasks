import 'dart:convert';
import 'dart:io';
import '../../data/database_service.dart';
import 'desktop_auth_handler.dart';

class DesktopMistakesHandler {
  final DesktopAuthHandler authHandler;

  const DesktopMistakesHandler({required this.authHandler});

  Future<void> handleGetSubjects(HttpRequest request) async {
    try {
      final subjs = await DatabaseService.instance.getAllDistinctSubjects();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'subjects': subjs.where((s) => s != 'All Subjects').toList()}));
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleGetMistakes(HttpRequest request) async {
    try {
      final subjectFilter = request.uri.queryParameters['subject'];
      final severityFilter = request.uri.queryParameters['severity'];
      final statusFilter = request.uri.queryParameters['status'];
      final quizFilter = request.uri.queryParameters['quiz'];
      final search = request.uri.queryParameters['search'];

      final mistakes = await DatabaseService.instance.getMistakeRecordsFiltered(
        subject: subjectFilter,
        severity: severityFilter,
        status: statusFilter,
        quizTitle: quizFilter,
        searchQuery: search,
      );

      final totalUnresolved = await DatabaseService.instance.getUnresolvedMistakeCount();
      final totalRecords = await DatabaseService.instance.getTotalMistakeCount();

      final responseData = {
        'total': totalRecords,
        'unresolved': totalUnresolved,
        'count': mistakes.length,
        'records': mistakes,
      };

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(responseData));
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleCreateMistake(HttpRequest request) async {
    try {
      final bodyStr = await utf8.decodeStream(request);
      final json = jsonDecode(bodyStr);

      final subject = json['subject']?.toString().trim();
      final topic = json['topic']?.toString().trim();
      final reason = (json['mistake_reason'] ?? json['reason'])?.toString().trim();
      final keyTakeaway = (json['key_takeaway'] ?? json['takeaway'])?.toString().trim();
      final questionText = (json['question_text'] ?? json['question'])?.toString().trim();
      final wrongAnswer = (json['wrong_answer'] ?? json['wrong'])?.toString().trim();
      final correctAnswer = (json['correct_answer'] ?? json['correct'])?.toString().trim();
      final quizTitle = (json['quiz_title'] ?? json['quiz'])?.toString().trim();
      final severity = json['severity']?.toString().trim() ?? 'MEDIUM';

      if (subject == null || subject.isEmpty || topic == null || topic.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'subject and topic are required fields'}));
        await request.response.close();
        return;
      }

      final id = await DatabaseService.instance.addMistakeRecord(
        subject: subject,
        topic: topic,
        reason: reason,
        severity: severity,
        quizTitle: quizTitle,
        questionText: questionText,
        wrongAnswer: wrongAnswer,
        correctAnswer: correctAnswer,
        keyTakeaway: keyTakeaway,
      );

      request.response.statusCode = HttpStatus.created;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'id': id, 'message': 'Mistake record logged successfully'}));
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleToggleMistake(HttpRequest request, String idStr) async {
    try {
      final id = int.tryParse(idStr);
      if (id == null) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Invalid mistake ID'}));
        await request.response.close();
        return;
      }

      final bodyStr = await utf8.decodeStream(request);
      final json = jsonDecode(bodyStr);
      final isResolved = json['resolved'] == true || json['status'] == 'RESOLVED';

      await DatabaseService.instance.toggleMistakeResolved(id, isResolved);

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'id': id, 'status': isResolved ? 'RESOLVED' : 'UNRESOLVED'}));
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleDeleteMistake(HttpRequest request, String idStr) async {
    try {
      final id = int.tryParse(idStr);
      if (id == null) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Invalid mistake ID'}));
        await request.response.close();
        return;
      }

      await DatabaseService.instance.deleteMistakeRecord(id);

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'id': id}));
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }
}
