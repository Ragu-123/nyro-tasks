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

  Future<String> getDbPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return p.join(docsDir.path, 'nyro_local.db');
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDbPath();

    // If database does not exist, extract from asset
    if (!await File(dbPath).exists()) {
      ByteData data = await rootBundle.load('assets/data/nyro.db');
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

    final db = await openDatabase(dbPath);
    await db.execute('CREATE TABLE IF NOT EXISTS app_config (key TEXT PRIMARY KEY, value TEXT)');
    return db;
  }

  // --- App Config & Hugging Face Token ---

  Future<String?> getHfToken() async {
    final db = await database;
    final res = await db.query('app_config', where: 'key = ?', whereArgs: ['hf_token'], limit: 1);
    if (res.isNotEmpty) return res.first['value'] as String?;
    return null;
  }

  Future<void> setHfToken(String token) async {
    final db = await database;
    await db.insert(
      'app_config',
      {'key': 'hf_token', 'value': token.trim()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Today's Pacing & Lectures ---

  Future<Map<String, dynamic>> getDailyPacing(DateTime date) async {
    final db = await database;
    final isoDate = DateFormat('yyyy-MM-dd').format(date);
    final dayPadded = DateFormat('dd MMM yyyy').format(date);
    final dayUnpadded = DateFormat('d MMM yyyy').format(date);

    // 1. Try reading daily_sessions
    final daily = await db.query(
      'daily_sessions',
      where: 'date_str = ?',
      whereArgs: [isoDate],
      limit: 1,
    );

    // 2. Query today's lectures (exact date match to prevent multi-day substring overcounting)
    final lecs = await db.rawQuery(
      'SELECT * FROM lectures WHERE (lower(trim(date_str)) = lower(?) OR lower(trim(date_str)) = lower(?) OR date_str = ?)',
      [dayPadded, dayUnpadded, isoDate],
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
    final isoDate = DateFormat('yyyy-MM-dd').format(date);
    final dayPadded = DateFormat('dd MMM yyyy').format(date);
    final dayUnpadded = DateFormat('d MMM yyyy').format(date);
    return await db.rawQuery(
      'SELECT * FROM lectures WHERE (lower(trim(date_str)) = lower(?) OR lower(trim(date_str)) = lower(?) OR date_str = ?) ORDER BY id ASC',
      [dayPadded, dayUnpadded, isoDate],
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
    final dayPadded = DateFormat('dd MMM yyyy').format(date);
    final dayUnpadded = DateFormat('d MMM yyyy').format(date);

    return await db.rawQuery(
      'SELECT * FROM revisit_items WHERE (due_date = ? OR lower(trim(due_date)) = lower(?) OR lower(trim(due_date)) = lower(?)) ORDER BY id ASC',
      [isoDate, dayPadded, dayUnpadded],
    );
  }

  DateTime? _parseDateSafe(String? str) {
    if (str == null || str.trim().isEmpty) return null;
    final s = str.trim();
    try {
      return DateFormat('dd MMM yyyy').parse(s);
    } catch (_) {}
    try {
      return DateFormat('d MMM yyyy').parse(s);
    } catch (_) {}
    try {
      return DateTime.parse(s);
    } catch (_) {}
    try {
      return DateFormat('yyyy-MM-dd').parse(s);
    } catch (_) {}
    return null;
  }

  Future<Map<String, List<Map<String, dynamic>>>> getDueBacklogCategorized({
    required DateTime date,
    String? subject,
  }) async {
    final db = await database;
    final targetDate = DateTime(date.year, date.month, date.day, 23, 59, 59);

    // 1. Recalls (Revisit checkpoints)
    final revs = await db.query('revisit_items', where: 'status != ?', whereArgs: ['DONE']);
    final dueRevs = revs.where((r) {
      if (subject != null && subject != 'All Subjects' && subject.isNotEmpty) {
        final top = (r['topic'] as String? ?? '').toLowerCase();
        if (!top.contains(subject.toLowerCase())) return false;
      }
      final d = _parseDateSafe(r['due_date'] as String?);
      return d != null && !d.isAfter(targetDate);
    }).toList();

    // 2. Quizzes
    final quizzes = await db.query('quiz_items', where: 'status != ?', whereArgs: ['COMPLETED']);
    final dueQuizzes = quizzes.where((q) {
      if (subject != null && subject != 'All Subjects' && subject.isNotEmpty) {
        final sub = (q['subject'] as String? ?? '').toLowerCase();
        final title = (q['title'] as String? ?? '').toLowerCase();
        final sLower = subject.toLowerCase();
        if (!sub.contains(sLower) && !title.contains(sLower)) return false;
      }
      final d = _parseDateSafe(q['date_str'] as String?);
      return d != null && !d.isAfter(targetDate);
    }).toList();

    // 3. Lectures
    final lecs = await db.query('lectures', where: 'status != ?', whereArgs: ['COMPLETED']);
    final dueLecs = lecs.where((l) {
      if (subject != null && subject != 'All Subjects' && subject.isNotEmpty) {
        final top = (l['topic'] as String? ?? '').toLowerCase();
        if (!top.contains(subject.toLowerCase())) return false;
      }
      final d = _parseDateSafe(l['date_str'] as String?);
      return d != null && !d.isAfter(targetDate);
    }).toList();

    return {
      'recalls': dueRevs,
      'quizzes': dueQuizzes,
      'lectures': dueLecs,
    };
  }

  Future<List<Map<String, dynamic>>> getAllDueBacklogRevisits({String? subject, DateTime? date}) async {
    final categorized = await getDueBacklogCategorized(date: date ?? DateTime.now(), subject: subject);
    return categorized['recalls'] ?? [];
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
    final items = await db.rawQuery('SELECT topic, stage, status FROM revisit_items');

    final matrixMap = <String, Map<String, List<int>>>{};

    for (var r in items) {
      final rawTopic = r['topic'] as String? ?? '';
      final stage = r['stage'] as String? ?? '';
      final isDone = (r['status'] as String?)?.toUpperCase() == 'DONE';

      String subject = rawTopic.contains('•') ? rawTopic.split('•')[0].trim() : rawTopic.trim();
      if (subject.isEmpty) subject = 'General';

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

  Future<void> deleteMistakeRecord(int id) async {
    final db = await database;
    await db.delete('mistake_records', where: 'id = ?', whereArgs: [id]);
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

  Future<Map<String, int>> getSubjectLectureCounts() async {
    final db = await database;
    final lecs = await db.rawQuery('SELECT topic FROM lectures');
    final map = <String, int>{'All Subjects': lecs.length};
    for (var l in lecs) {
      final topic = l['topic'] as String? ?? 'General';
      final subj = topic.contains('•') ? topic.split('•')[0].trim() : topic.trim();
      map[subj] = (map[subj] ?? 0) + 1;
    }
    return map;
  }

  // --- Quizzes & Tests ---

  Future<List<Map<String, dynamic>>> getScheduledQuizzesForDate(DateTime date) async {
    final db = await database;
    final isoDate = DateFormat('yyyy-MM-dd').format(date);
    final dayPadded = DateFormat('dd MMM yyyy').format(date);
    final dayUnpadded = DateFormat('d MMM yyyy').format(date);
    return await db.rawQuery(
      'SELECT * FROM quiz_items WHERE (lower(trim(date_str)) = lower(?) OR lower(trim(date_str)) = lower(?) OR date_str = ?) ORDER BY id ASC',
      [dayPadded, dayUnpadded, isoDate],
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

  Future<Map<String, int>> getBadgeCounts([DateTime? date]) async {
    final now = date ?? DateTime.now();
    final categorized = await getDueBacklogCategorized(date: now);
    return {
      'due_revisits': categorized['recalls']?.length ?? 0,
      'pending_quizzes': categorized['quizzes']?.length ?? 0,
      'backlog_lectures': categorized['lectures']?.length ?? 0,
      'total_due': (categorized['recalls']?.length ?? 0) +
          (categorized['quizzes']?.length ?? 0) +
          (categorized['lectures']?.length ?? 0),
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

  // --- Database Synchronization (Cloud nyro.db & android_nyro.db) ---

  Future<void> overwriteDatabase(String newDbPath) async {
    final savedToken = await getHfToken();
    final localPath = await getDbPath();
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
    final newBytes = await File(newDbPath).readAsBytes();
    await File(localPath).writeAsBytes(newBytes, flush: true);
    _db = await openDatabase(localPath);
    await _db!.execute('''
      CREATE TABLE IF NOT EXISTS app_config (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    if (savedToken != null && savedToken.isNotEmpty) {
      await setHfToken(savedToken);
    }
  }

  Future<void> smartMergeDatabase(String cloudDbPath) async {
    final cloudDb = await openDatabase(cloudDbPath, readOnly: true);
    final localDb = await database;

    try {
      // 1. Sync lectures (preserve local status and completed_at)
      final cloudLecs = await cloudDb.query('lectures');
      for (var cl in cloudLecs) {
        final id = cl['id'] as int;
        final existing = await localDb.query('lectures', where: 'id = ?', whereArgs: [id]);
        if (existing.isEmpty) {
          await localDb.insert('lectures', cl);
        } else {
          // Update details from cloud, keep local status
          await localDb.update(
            'lectures',
            {
              'topic': cl['topic'],
              'details': cl['details'],
              'duration_hours': cl['duration_hours'],
              'session_block': cl['session_block'],
              'date_str': cl['date_str'],
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      // 2. Sync quizzes (preserve local status)
      final cloudQuizzes = await cloudDb.query('quiz_items');
      for (var cq in cloudQuizzes) {
        final id = cq['id'] as int;
        final existing = await localDb.query('quiz_items', where: 'id = ?', whereArgs: [id]);
        if (existing.isEmpty) {
          await localDb.insert('quiz_items', cq);
        } else {
          await localDb.update(
            'quiz_items',
            {
              'title': cq['title'],
              'subject': cq['subject'],
              'module_name': cq['module_name'],
              'date_str': cq['date_str'],
              'duration_mins': cq['duration_mins'],
              'total_marks': cq['total_marks'],
              'syllabus_topics': cq['syllabus_topics'],
              'action_url': cq['action_url'],
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      // 3. Sync revisits (insert missing, keep local status)
      final cloudRevisits = await cloudDb.query('revisit_items');
      for (var cr in cloudRevisits) {
        final id = cr['id'] as int;
        final existing = await localDb.query('revisit_items', where: 'id = ?', whereArgs: [id]);
        if (existing.isEmpty) {
          await localDb.insert('revisit_items', cr);
        } else {
          await localDb.update(
            'revisit_items',
            {
              'topic': cr['topic'],
              'stage': cr['stage'],
              'due_date': cr['due_date'],
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      // 4. Sync timetables (if cloud has updated timetable structures)
      try {
        final cloudTimetables = await cloudDb.query('timetables');
        for (var ct in cloudTimetables) {
          final id = ct['id'] as int;
          final existing = await localDb.query('timetables', where: 'id = ?', whereArgs: [id]);
          if (existing.isEmpty) {
            await localDb.insert('timetables', ct);
          } else {
            await localDb.update('timetables', ct, where: 'id = ?', whereArgs: [id]);
          }
        }
      } catch (_) {}
    } finally {
      await cloudDb.close();
    }
  }
}
