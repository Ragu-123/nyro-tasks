import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'nyro_local.db');

    // If database does not exist, extract from asset
    if (!await File(dbPath).exists()) {
      ByteData data = await rootBundle.load('assets/data/nyro.db');
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

    return await openDatabase(dbPath);
  }

  // --- Today's Pacing & Lectures ---

  Future<Map<String, dynamic>> getDailyPacing(DateTime date) async {
    final db = await database;
    final isoDate = DateFormat('yyyy-MM-dd').format(date);
    final formattedDate = DateFormat('d MMM yyyy').format(date);

    // 1. Try reading daily_sessions
    final daily = await db.query(
      'daily_sessions',
      where: 'date_str = ?',
      whereArgs: [isoDate],
      limit: 1,
    );

    // 2. Query today's lectures
    final lecs = await db.rawQuery(
      'SELECT * FROM lectures WHERE lower(date_str) LIKE lower(?)',
      ['%$formattedDate%'],
    );

    double targetHours = 8.0;
    double watchedHours = 0.0;

    if (lecs.isNotEmpty) {
      targetHours = lecs.fold<double>(0.0, (sum, l) => sum + ((l['duration_hours'] as num?)?.toDouble() ?? 1.0));
      watchedHours = lecs
          .where((l) => (l['status'] as String?)?.toUpperCase() == 'COMPLETED')
          .fold<double>(0.0, (sum, l) => sum + ((l['duration_hours'] as num?)?.toDouble() ?? 1.0));
    } else if (daily.isNotEmpty) {
      targetHours = (daily.first['target_hours'] as num?)?.toDouble() ?? 8.0;
      watchedHours = (daily.first['watched_hours'] as num?)?.toDouble() ?? 0.0;
    }

    final revisits = await getDueRevisitsForDate(date);
    final quizzes = await getScheduledQuizzesForDate(date);

    return {
      'target_hours': targetHours,
      'watched_hours': watchedHours,
      'lecture_count': lecs.length,
      'completed_count': lecs.where((l) => (l['status'] as String?)?.toUpperCase() == 'COMPLETED').length,
      'revisit_count': revisits.length,
      'quiz_count': quizzes.length,
    };
  }

  Future<List<Map<String, dynamic>>> getLecturesForDate(DateTime date) async {
    final db = await database;
    final formattedDate = DateFormat('d MMM yyyy').format(date);
    return await db.rawQuery(
      'SELECT * FROM lectures WHERE lower(date_str) LIKE lower(?) ORDER BY id ASC',
      ['%$formattedDate%'],
    );
  }

  Future<void> toggleLectureStatus(int id, bool isCompleted, double duration, DateTime date) async {
    final db = await database;
    final status = isCompleted ? 'COMPLETED' : 'PENDING';
    final completedAt = isCompleted ? DateTime.now().toIso8601String() : null;

    await db.update(
      'lectures',
      {'status': status, 'completed_at': completedAt},
      where: 'id = ?',
      whereArgs: [id],
    );

    // Update daily_sessions if exists
    final isoDate = DateFormat('yyyy-MM-dd').format(date);
    final daily = await db.query('daily_sessions', where: 'date_str = ?', whereArgs: [isoDate]);
    if (daily.isNotEmpty) {
      double curWatched = (daily.first['watched_hours'] as num?)?.toDouble() ?? 0.0;
      double newWatched = isCompleted ? (curWatched + duration) : (curWatched - duration);
      if (newWatched < 0) newWatched = 0.0;
      await db.update(
        'daily_sessions',
        {'watched_hours': newWatched},
        where: 'date_str = ?',
        whereArgs: [isoDate],
      );
    }
  }

  // --- Revisits ---

  Future<List<Map<String, dynamic>>> getDueRevisitsForDate(DateTime date) async {
    final db = await database;
    final isoDate = DateFormat('yyyy-MM-dd').format(date);
    final formattedDate = DateFormat('d MMM yyyy').format(date);

    return await db.rawQuery(
      'SELECT * FROM revisit_items WHERE (due_date = ? OR lower(due_date) LIKE lower(?)) ORDER BY id ASC',
      [isoDate, '%$formattedDate%'],
    );
  }

  Future<List<Map<String, dynamic>>> getAllDueBacklogRevisits({String? subject}) async {
    final db = await database;
    String sql = 'SELECT * FROM revisit_items WHERE status != "DONE"';
    List<dynamic> args = [];
    if (subject != null && subject != 'All Subjects') {
      sql += ' AND lower(topic) LIKE lower(?)';
      args.add('%$subject%');
    }
    sql += ' ORDER BY due_date ASC LIMIT 150';
    return await db.rawQuery(sql, args);
  }

  Future<void> toggleRevisitStatus(int id, bool isDone) async {
    final db = await database;
    final status = isDone ? 'DONE' : 'DUE';
    final completedAt = isDone ? DateTime.now().toIso8601String() : null;

    await db.update(
      'revisit_items',
      {'status': status, 'completed_at': completedAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Retention Matrix Heatmap Data ---

  Future<List<Map<String, dynamic>>> getRetentionMatrixData() async {
    final db = await database;
    final items = await db.rawQuery('''
      SELECT topic, stage, status
      FROM revisit_items
    ''');

    // Aggregate by subject and stage
    final matrixMap = <String, Map<String, List<int>>>{};

    for (var r in items) {
      final rawTopic = r['topic'] as String? ?? '';
      final stage = r['stage'] as String? ?? '';
      final isDone = (r['status'] as String?)?.toUpperCase() == 'DONE';

      // Clean subject from topic (e.g., "Calculus and Optimization • Lecture - 1...")
      String subject = rawTopic.contains('•') ? rawTopic.split('•')[0].trim() : rawTopic.trim();
      if (subject.isEmpty) subject = 'General';

      // Standardize stage: Day 1, Day 4, Day 7, Day 14, Day 30
      String normStage = 'Other';
      if (stage.contains('Day 1') || stage.contains('24h')) normStage = 'Day 1';
      else if (stage.contains('Day 4')) normStage = 'Day 4';
      else if (stage.contains('Day 7')) normStage = 'Day 7';
      else if (stage.contains('Day 14')) normStage = 'Day 14';
      else if (stage.contains('Day 30')) normStage = 'Day 30';

      matrixMap.putIfAbsent(subject, () => {
        'Day 1': [0, 0],
        'Day 4': [0, 0],
        'Day 7': [0, 0],
        'Day 14': [0, 0],
        'Day 30': [0, 0],
      });

      if (matrixMap[subject]!.containsKey(normStage)) {
        matrixMap[subject]![normStage]![0]++; // total
        if (isDone) matrixMap[subject]![normStage]![1]++; // done
      }
    }

    final result = <Map<String, dynamic>>[];
    matrixMap.forEach((subj, stages) {
      result.add({
        'subject': subj,
        'stages': stages,
      });
    });

    return result;
  }

  Future<List<Map<String, dynamic>>> getRevisitsForSubjectAndStage(String subject, String stage) async {
    final db = await database;
    String stageQuery = '%$stage%';
    return await db.rawQuery(
      'SELECT * FROM revisit_items WHERE lower(topic) LIKE lower(?) AND lower(stage) LIKE lower(?) ORDER BY id ASC',
      ['%$subject%', stageQuery],
    );
  }

  // --- Mistake Notebook ---

  Future<List<Map<String, dynamic>>> getMistakeRecordsFiltered({
    String? subject,
    String? status,
    String? severity,
    String? quizTitle,
  }) async {
    final db = await database;
    String sql = 'SELECT * FROM mistake_records WHERE 1=1';
    List<dynamic> args = [];

    if (subject != null && subject != 'All Subjects' && subject.isNotEmpty) {
      sql += ' AND lower(subject) LIKE lower(?)';
      args.add('%$subject%');
    }
    if (status != null && status != 'ALL' && status.isNotEmpty) {
      sql += ' AND upper(status) = upper(?)';
      args.add(status);
    }
    if (severity != null && severity != 'ALL' && severity.isNotEmpty) {
      sql += ' AND upper(severity) = upper(?)';
      args.add(severity);
    }
    if (quizTitle != null && quizTitle.isNotEmpty) {
      sql += ' AND lower(quiz_title) LIKE lower(?)';
      args.add('%$quizTitle%');
    }

    sql += ' ORDER BY id DESC';
    return await db.rawQuery(sql, args);
  }

  Future<int> insertMistakeRecord({
    required String subject,
    required String topic,
    required String questionText,
    String? wrongAnswer,
    String? correctAnswer,
    String? mistakeReason,
    required String keyTakeaway,
    String? quizTitle,
    required String severity,
  }) async {
    final db = await database;
    return await db.insert('mistake_records', {
      'subject': subject,
      'topic': topic,
      'question_text': questionText,
      'wrong_answer': wrongAnswer,
      'correct_answer': correctAnswer,
      'mistake_reason': mistakeReason,
      'key_takeaway': keyTakeaway,
      'quiz_title': quizTitle ?? '',
      'severity': severity.toUpperCase(),
      'status': 'UNRESOLVED',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> toggleMistakeResolved(int id, bool isResolved) async {
    final db = await database;
    final status = isResolved ? 'RESOLVED' : 'UNRESOLVED';
    final resolvedAt = isResolved ? DateTime.now().toIso8601String() : null;

    await db.update(
      'mistake_records',
      {'status': status, 'resolved_at': resolvedAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Timetable & Curriculum ---

  Future<List<Map<String, dynamic>>> getCurriculumGroupedBySubject({String? query, String? subjectFilter}) async {
    final db = await database;
    String sql = 'SELECT * FROM lectures WHERE 1=1';
    List<dynamic> args = [];

    if (query != null && query.trim().isNotEmpty) {
      sql += ' AND (lower(topic) LIKE lower(?) OR lower(details) LIKE lower(?) OR lower(date_str) LIKE lower(?))';
      final term = '%${query.trim()}%';
      args.addAll([term, term, term]);
    }

    if (subjectFilter != null && subjectFilter != 'All Subjects' && subjectFilter.isNotEmpty) {
      sql += ' AND lower(topic) LIKE lower(?)';
      args.add('%$subjectFilter%');
    }

    sql += ' ORDER BY id ASC';
    return await db.rawQuery(sql, args);
  }

  Future<List<String>> getAllDistinctSubjects() async {
    final db = await database;
    final qSubjs = await db.rawQuery('SELECT DISTINCT subject FROM quiz_items WHERE subject IS NOT NULL');
    final mSubjs = await db.rawQuery('SELECT DISTINCT subject FROM mistake_records WHERE subject IS NOT NULL');
    
    final set = <String>{};
    for (var r in qSubjs) {
      if (r['subject'] != null && r['subject'].toString().trim().isNotEmpty) {
        set.add(r['subject'].toString().trim());
      }
    }
    for (var r in mSubjs) {
      if (r['subject'] != null && r['subject'].toString().trim().isNotEmpty) {
        set.add(r['subject'].toString().trim());
      }
    }

    final list = set.toList()..sort();
    return ['All Subjects', ...list];
  }

  // --- Quizzes & Tests ---

  Future<List<Map<String, dynamic>>> getScheduledQuizzesForDate(DateTime date) async {
    final db = await database;
    final formattedDate = DateFormat('d MMM yyyy').format(date);
    return await db.rawQuery(
      'SELECT * FROM quiz_items WHERE lower(date_str) LIKE lower(?) ORDER BY id ASC',
      ['%$formattedDate%'],
    );
  }

  Future<List<Map<String, dynamic>>> getQuizzesByType(String type, {String? subjectFilter}) async {
    final db = await database;
    String sql = 'SELECT * FROM quiz_items WHERE quiz_type = ?';
    List<dynamic> args = [type];

    if (subjectFilter != null && subjectFilter != 'All Subjects' && subjectFilter.isNotEmpty) {
      sql += ' AND lower(subject) LIKE lower(?)';
      args.add('%$subjectFilter%');
    }

    sql += ' ORDER BY id ASC';
    return await db.rawQuery(sql, args);
  }

  Future<int> getMistakeCountForQuiz(String quizTitle) async {
    final db = await database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM mistake_records WHERE lower(quiz_title) LIKE lower(?)',
      ['%$quizTitle%'],
    );
    return (res.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<void> toggleQuizStatus(int id, bool completed) async {
    final db = await database;
    final status = completed ? 'COMPLETED' : 'PENDING';
    await db.update('quiz_items', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  // --- Badge Counts for Bottom Tabs ---

  Future<Map<String, int>> getBadgeCounts() async {
    final db = await database;
    final dueRev = await db.rawQuery('SELECT COUNT(*) as cnt FROM revisit_items WHERE status != "DONE"');
    final pendingQuiz = await db.rawQuery('SELECT COUNT(*) as cnt FROM quiz_items WHERE upper(status) != "COMPLETED"');
    return {
      'due_revisits': (dueRev.first['cnt'] as num?)?.toInt() ?? 0,
      'pending_quizzes': (pendingQuiz.first['cnt'] as num?)?.toInt() ?? 0,
    };
  }

  // --- Alert Settings & Custom Reminders ---

  Future<Map<String, dynamic>> getAlertSettings() async {
    final db = await database;
    final list = await db.query('alert_settings', limit: 1);
    if (list.isNotEmpty) return list.first;
    return {
      'morning_brief': 1,
      'morning_brief_time': '05:00',
      'revisit_alerts': 1,
      'backlog_shield': 1,
      'shield_time': '21:30',
    };
  }

  Future<void> updateAlertSettings({
    required bool morningBrief,
    required bool revisitAlerts,
    required bool backlogShield,
  }) async {
    final db = await database;
    await db.update('alert_settings', {
      'morning_brief': morningBrief ? 1 : 0,
      'revisit_alerts': revisitAlerts ? 1 : 0,
      'backlog_shield': backlogShield ? 1 : 0,
    }, where: 'id = ?', whereArgs: [1]);
  }

  Future<List<Map<String, dynamic>>> getCustomReminders() async {
    final db = await database;
    return await db.query('custom_reminders', orderBy: 'remind_at ASC');
  }

  Future<int> addCustomReminder(String text, DateTime remindAt) async {
    final db = await database;
    return await db.insert('custom_reminders', {
      'text': text,
      'remind_at': remindAt.toIso8601String(),
      'status': 'PENDING',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteCustomReminder(int id) async {
    final db = await database;
    await db.delete('custom_reminders', where: 'id = ?', whereArgs: [id]);
  }
}
