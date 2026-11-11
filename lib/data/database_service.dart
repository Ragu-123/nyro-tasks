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

    final db = await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        // High-performance SQLite engine optimization:
        // WAL mode enables concurrent readers and non-blocking background writes
        await db.execute('PRAGMA journal_mode = WAL;');
        await db.execute('PRAGMA synchronous = NORMAL;');
        await db.execute('PRAGMA temp_store = MEMORY;');
        await db.execute('PRAGMA mmap_size = 268435456;');
        await db.execute('PRAGMA cache_size = -8000;');
      },
      onCreate: (db, version) async {
        await _createAllTables(db);
      },
    );

    // Defensively apply WAL pragmas for existing database connections
    try {
      await db.execute('PRAGMA journal_mode = WAL;');
      await db.execute('PRAGMA synchronous = NORMAL;');
    } catch (_) {}

    // Ensure all tables and config keys exist on upgrade or existing db
    await _createAllTables(db);
    return db;
  }

  Future<void> _createAllTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS timetables (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        title VARCHAR, 
        subject VARCHAR, 
        created_at DATETIME
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        date_str VARCHAR, 
        target_hours FLOAT, 
        watched_hours FLOAT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS timetable_proposals (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        proposal_type VARCHAR, 
        title VARCHAR, 
        summary VARCHAR, 
        changes_payload VARCHAR, 
        status VARCHAR, 
        created_at DATETIME
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS alert_settings (
        id INTEGER PRIMARY KEY, 
        morning_brief BOOLEAN, 
        morning_brief_time VARCHAR, 
        revisit_alerts BOOLEAN, 
        backlog_shield BOOLEAN, 
        shield_time VARCHAR, 
        last_morning_brief_date VARCHAR
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        text VARCHAR NOT NULL, 
        remind_at DATETIME NOT NULL, 
        status VARCHAR, 
        created_at DATETIME, 
        anchor_id INTEGER, 
        relative_id INTEGER, 
        anchor_type TEXT DEFAULT 'none', 
        offset_days INTEGER DEFAULT 0, 
        offset_time_str TEXT DEFAULT '08:00'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS lectures (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        timetable_id INTEGER, 
        date_str VARCHAR, 
        topic VARCHAR, 
        details VARCHAR, 
        duration_hours FLOAT, 
        session_block VARCHAR, 
        status VARCHAR, 
        completed_at DATETIME, 
        anchor_id INTEGER, 
        relative_id INTEGER, 
        offset_days INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS revisit_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        lecture_id INTEGER, 
        topic VARCHAR, 
        stage VARCHAR, 
        duration_mins INTEGER, 
        due_date VARCHAR, 
        status VARCHAR, 
        completed_at DATETIME, 
        anchor_id INTEGER, 
        relative_id INTEGER, 
        offset_days INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS quiz_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        quiz_type VARCHAR, 
        title VARCHAR, 
        week_number INTEGER, 
        date_str VARCHAR, 
        duration_mins INTEGER, 
        total_questions INTEGER, 
        total_marks INTEGER, 
        syllabus_topics VARCHAR, 
        status VARCHAR, 
        score FLOAT, 
        created_at DATETIME, 
        subject VARCHAR, 
        module_name VARCHAR, 
        action_url VARCHAR, 
        exam_id INTEGER, 
        is_premium BOOLEAN, 
        notes VARCHAR, 
        anchor_id INTEGER, 
        relative_id INTEGER, 
        offset_days INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS mistake_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        subject VARCHAR, 
        topic VARCHAR, 
        question_text VARCHAR, 
        wrong_answer VARCHAR, 
        correct_answer VARCHAR, 
        mistake_reason VARCHAR, 
        key_takeaway VARCHAR, 
        quiz_title VARCHAR, 
        severity VARCHAR, 
        status VARCHAR, 
        created_at DATETIME, 
        resolved_at DATETIME
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_subjects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS inapp_notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        message TEXT,
        type TEXT,
        created_at DATETIME
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_config (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bitchat_messages (
        id TEXT PRIMARY KEY,
        sender TEXT NOT NULL,
        sender_peer_id TEXT,
        sender_nostr_pubkey TEXT,
        recipient_nickname TEXT,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        channel TEXT,
        is_private INTEGER DEFAULT 0,
        is_relay INTEGER DEFAULT 0,
        delivery_status TEXT DEFAULT 'sent',
        transport_type TEXT DEFAULT 'both',
        hop_count INTEGER DEFAULT 0,
        sender_fingerprint TEXT,
        image_base64 TEXT,
        attachment_url TEXT,
        geohash_precision INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bitchat_peers (
        peer_id TEXT PRIMARY KEY,
        nickname TEXT NOT NULL,
        noise_public_key TEXT,
        signing_public_key TEXT,
        nostr_pubkey TEXT,
        rssi INTEGER,
        is_direct INTEGER DEFAULT 1,
        is_connected INTEGER DEFAULT 0,
        last_seen INTEGER NOT NULL,
        transport_type TEXT DEFAULT 'ble'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bitchat_channels (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        geohash TEXT,
        unread_count INTEGER DEFAULT 0,
        participant_count INTEGER DEFAULT 0
      )
    ''');

    // Performance composite indices for BitChat queries
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_bitchat_messages_channel_timestamp 
      ON bitchat_messages(channel, timestamp ASC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_bitchat_messages_timestamp 
      ON bitchat_messages(timestamp ASC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_bitchat_peers_last_seen 
      ON bitchat_peers(last_seen DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_bitchat_channels_type 
      ON bitchat_channels(type)
    ''');

    // Performance indices for high-frequency Tasks core queries
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_lectures_date_str 
      ON lectures(date_str)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_daily_sessions_date_str 
      ON daily_sessions(date_str)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_revisit_items_lecture_id 
      ON revisit_items(lecture_id)
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO alert_settings (id, morning_brief, morning_brief_time, revisit_alerts, backlog_shield, shield_time)
      VALUES (1, 1, '05:00', 1, 1, '21:30')
    ''');

    // Defensive schema migrations for existing databases
    try {
      final mCols = await db.rawQuery('PRAGMA table_info(mistake_records)');
      final colNames = mCols.map((c) => c['name']?.toString().toLowerCase()).toSet();
      if (!colNames.contains('question_text')) {
        await db.execute('ALTER TABLE mistake_records ADD COLUMN question_text VARCHAR');
      }
      if (!colNames.contains('wrong_answer')) {
        await db.execute('ALTER TABLE mistake_records ADD COLUMN wrong_answer VARCHAR');
      }
      if (!colNames.contains('correct_answer')) {
        await db.execute('ALTER TABLE mistake_records ADD COLUMN correct_answer VARCHAR');
      }
      if (!colNames.contains('resolved_at')) {
        await db.execute('ALTER TABLE mistake_records ADD COLUMN resolved_at DATETIME');
      }
    } catch (_) {}

    try {
      final bCols = await db.rawQuery('PRAGMA table_info(bitchat_messages)');
      final bColNames = bCols.map((c) => c['name']?.toString().toLowerCase()).toSet();
      if (!bColNames.contains('hop_count')) {
        await db.execute('ALTER TABLE bitchat_messages ADD COLUMN hop_count INTEGER DEFAULT 0');
      }
      if (!bColNames.contains('sender_fingerprint')) {
        await db.execute('ALTER TABLE bitchat_messages ADD COLUMN sender_fingerprint TEXT');
      }
      if (!bColNames.contains('image_base64')) {
        await db.execute('ALTER TABLE bitchat_messages ADD COLUMN image_base64 TEXT');
      }
      if (!bColNames.contains('attachment_url')) {
        await db.execute('ALTER TABLE bitchat_messages ADD COLUMN attachment_url TEXT');
      }
      if (!bColNames.contains('geohash_precision')) {
        await db.execute('ALTER TABLE bitchat_messages ADD COLUMN geohash_precision INTEGER');
      }
    } catch (_) {}
  }

  // --- App Config & Hugging Face Tokens / Settings ---

  Future<String?> getConfig(String key) async {
    final db = await database;
    final res = await db.query('app_config', where: 'key = ?', whereArgs: [key], limit: 1);
    if (res.isNotEmpty) return res.first['value'] as String?;
    return null;
  }

  Future<void> setConfig(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_config',
      {'key': key, 'value': value.trim()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getHfToken() => getConfig('hf_token');
  Future<void> setHfToken(String token) => setConfig('hf_token', token);

  Future<String?> getHfUsername() => getConfig('hf_username');
  Future<void> setHfUsername(String username) => setConfig('hf_username', username);

  Future<String?> getHfRepo() => getConfig('hf_repo');
  Future<void> setHfRepo(String repo) => setConfig('hf_repo', repo);

  Future<String?> getHfBucket() => getConfig('hf_bucket');
  Future<void> setHfBucket(String bucket) => setConfig('hf_bucket', bucket);

  Future<bool> getAutoCheckUpdates() async {
    final val = await getConfig('auto_check_updates');
    return val != '0'; // default true
  }

  Future<void> setAutoCheckUpdates(bool enabled) => setConfig('auto_check_updates', enabled ? '1' : '0');

  Future<bool> getAutoStartServer() async {
    final val = await getConfig('auto_start_server');
    return val == '1'; // default false
  }

  Future<void> setAutoStartServer(bool enabled) => setConfig('auto_start_server', enabled ? '1' : '0');

  Future<bool> hasAnyScheduledLectures() async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) as cnt FROM lectures');
    final cnt = (res.first['cnt'] as num?)?.toInt() ?? 0;
    return cnt > 0;
  }

  // --- Load Sample Curriculum (from asset nyro.db) ---
  Future<void> loadSampleCurriculum() async {
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, 'asset_sample_nyro.db');
    final ByteData data = await rootBundle.load('assets/data/nyro.db');
    final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await File(tempPath).writeAsBytes(bytes, flush: true);

    await smartMergeDatabase(tempPath);
    try {
      await File(tempPath).delete();
    } catch (_) {}
  }

  // --- Clear Timetable / Reset to Clean State ---
  Future<void> clearAllTimetableData() async {
    final db = await database;
    await db.delete('lectures');
    await db.delete('revisit_items');
    await db.delete('quiz_items');
    await db.delete('timetables');
    await db.delete('daily_sessions');
  }

  // --- In-App Notifications History ---

  Future<int> addInAppNotification({
    required String title,
    required String message,
    String type = 'INFO',
  }) async {
    final db = await database;
    return await db.insert('inapp_notifications', {
      'title': title,
      'message': message,
      'type': type,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getInAppNotifications({int limit = 40}) async {
    final db = await database;
    return await db.query('inapp_notifications', orderBy: 'id DESC', limit: limit);
  }

  Future<void> clearInAppNotifications() async {
    final db = await database;
    await db.delete('inapp_notifications');
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

    // 2. Query today's lectures
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

  // --- Spaced Repetition Formula & Schedule Creation ---

  Future<void> saveCustomSubject(String subject) async {
    final clean = subject.trim();
    if (clean.isEmpty || clean == 'All Subjects') return;
    final db = await database;
    await db.insert(
      'custom_subjects',
      {'name': clean},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Inserts a newly scheduled lecture and automatically generates 5 spaced repetition checkpoints
  /// as per the Ebbinghaus forgetting curve formula (Day 1, Day 4, Day 7, Day 14, Day 30).
  Future<int> insertScheduledLecture({
    required String subject,
    required String lectureName,
    required DateTime date,
    required double durationHours,
    String? sessionBlock,
  }) async {
    final db = await database;
    final cleanSubj = subject.trim();
    final cleanName = lectureName.trim();
    final dateStr = DateFormat('dd MMM yyyy').format(date);

    // Save subject to custom subjects
    await saveCustomSubject(cleanSubj);

    final lectureTopic = cleanSubj.isNotEmpty ? '$cleanSubj • $cleanName' : cleanName;

    // 1. Insert into lectures
    final lectureId = await db.insert('lectures', {
      'date_str': dateStr,
      'topic': lectureTopic,
      'details': cleanName,
      'duration_hours': durationHours,
      'session_block': sessionBlock ?? 'General Session',
      'status': 'PENDING',
      'offset_days': 0,
    });

    // 2. Automatically generate 5 spaced repetition revisits
    final intervals = [
      {'stage': 'Day 1 (24h)', 'offset': 1, 'mins': 20},
      {'stage': 'Day 4', 'offset': 4, 'mins': 25},
      {'stage': 'Day 7', 'offset': 7, 'mins': 30},
      {'stage': 'Day 14', 'offset': 14, 'mins': 30},
      {'stage': 'Day 30', 'offset': 30, 'mins': 30},
    ];

    for (final inv in intervals) {
      final offsetDays = inv['offset'] as int;
      final dueDate = date.add(Duration(days: offsetDays));
      final dueDateStr = DateFormat('dd MMM yyyy').format(dueDate);

      await db.insert('revisit_items', {
        'lecture_id': lectureId,
        'topic': lectureTopic,
        'stage': inv['stage'],
        'duration_mins': inv['mins'],
        'due_date': dueDateStr,
        'status': 'DUE',
        'offset_days': offsetDays,
      });
    }

    return lectureId;
  }

  // --- Quizzes & Tests Creation ---

  Future<int> insertQuiz({
    required String subject,
    required String title,
    required DateTime date,
    String quizType = 'WEEKLY_QUIZ',
    int durationMins = 45,
    int totalMarks = 25,
    String? syllabusTopics,
    String? actionUrl,
  }) async {
    final db = await database;
    final cleanSubj = subject.trim();
    await saveCustomSubject(cleanSubj);

    final dateStr = DateFormat('dd MMM yyyy').format(date);

    return await db.insert('quiz_items', {
      'quiz_type': quizType,
      'title': title.trim(),
      'subject': cleanSubj,
      'date_str': dateStr,
      'duration_mins': durationMins,
      'total_marks': totalMarks,
      'syllabus_topics': syllabusTopics ?? '',
      'action_url': actionUrl ?? '',
      'status': 'PENDING',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // --- Custom Revisit Item Creation ---

  Future<int> insertCustomRevisit({
    required String topic,
    required String stage,
    required DateTime dueDate,
    int durationMins = 25,
  }) async {
    final db = await database;
    final dueDateStr = DateFormat('dd MMM yyyy').format(dueDate);

    return await db.insert('revisit_items', {
      'topic': topic.trim(),
      'stage': stage.trim(),
      'duration_mins': durationMins,
      'due_date': dueDateStr,
      'status': 'DUE',
    });
  }

  // --- Revisits Queries ---

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
        matrixMap[subject]![normStage]![0]++;
        if (isDone) matrixMap[subject]![normStage]![1]++;
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
    String? searchQuery,
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
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim();
      sql += ' AND (lower(topic) LIKE lower(?) OR lower(question_text) LIKE lower(?) OR lower(key_takeaway) LIKE lower(?) OR lower(mistake_reason) LIKE lower(?) OR lower(wrong_answer) LIKE lower(?) OR lower(correct_answer) LIKE lower(?))';
      args.addAll(['%$q%', '%$q%', '%$q%', '%$q%', '%$q%', '%$q%']);
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
    final cleanSubj = subject.trim();
    await saveCustomSubject(cleanSubj);

    final db = await database;
    return await db.insert('mistake_records', {
      'subject': cleanSubj,
      'topic': topic.trim(),
      'question_text': questionText.trim(),
      'wrong_answer': wrongAnswer ?? '',
      'correct_answer': correctAnswer ?? '',
      'mistake_reason': mistakeReason ?? '',
      'key_takeaway': keyTakeaway.trim(),
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
    final cSubjs = await db.rawQuery('SELECT DISTINCT name FROM custom_subjects WHERE name IS NOT NULL');
    final lSubjs = await db.rawQuery('SELECT DISTINCT topic FROM lectures WHERE topic IS NOT NULL');
    
    final set = <String>{};
    for (var r in qSubjs) {
      final s = r['subject']?.toString().trim();
      if (s != null && s.isNotEmpty) set.add(s);
    }
    for (var r in mSubjs) {
      final s = r['subject']?.toString().trim();
      if (s != null && s.isNotEmpty) set.add(s);
    }
    for (var r in cSubjs) {
      final s = r['name']?.toString().trim();
      if (s != null && s.isNotEmpty) set.add(s);
    }
    for (var r in lSubjs) {
      final top = r['topic']?.toString().trim();
      if (top != null && top.isNotEmpty) {
        final s = top.contains('•') ? top.split('•')[0].trim() : top;
        if (s.isNotEmpty) set.add(s);
      }
    }

    final list = set.toList()..sort();
    return ['All Subjects', ...list];
  }

  Future<List<String>> getOnlySubjectsForDropdown() async {
    final list = await getAllDistinctSubjects();
    return list.where((s) => s != 'All Subjects').toList();
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
    String? morningBriefTime,
    String? shieldTime,
  }) async {
    final db = await database;
    final updateData = <String, dynamic>{
      'morning_brief': morningBrief ? 1 : 0,
      'revisit_alerts': revisitAlerts ? 1 : 0,
      'backlog_shield': backlogShield ? 1 : 0,
    };
    if (morningBriefTime != null) updateData['morning_brief_time'] = morningBriefTime;
    if (shieldTime != null) updateData['shield_time'] = shieldTime;

    await db.update('alert_settings', updateData, where: 'id = ?', whereArgs: [1]);
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

  Future<void> updateCustomReminder({
    required int id,
    required String text,
    required DateTime remindAt,
  }) async {
    final db = await database;
    await db.update(
      'custom_reminders',
      {
        'text': text,
        'remind_at': remindAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleReminderStatus(int id, bool completed) async {
    final db = await database;
    await db.update(
      'custom_reminders',
      {
        'status': completed ? 'COMPLETED' : 'PENDING',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCustomReminder(int id) async {
    final db = await database;
    await db.delete('custom_reminders', where: 'id = ?', whereArgs: [id]);
  }

  // --- Database Synchronization (Cloud nyro.db & android_nyro.db) ---

  Future<void> overwriteDatabase(String newDbPath) async {
    final savedToken = await getHfToken();
    final savedUsername = await getHfUsername();
    final savedRepo = await getHfRepo();
    final savedBucket = await getHfBucket();

    // Safeguard local BitChat cryptographic identity & private keys
    final savedNoisePriv = await getConfig('bitchat_noise_priv');
    final savedNostrPriv = await getConfig('bitchat_nostr_priv');
    final savedNick = await getConfig('bitchat_nickname');
    final savedPeerId = await getConfig('bitchat_peer_id');
    final savedNostrPub = await getConfig('bitchat_nostr_pubkey');
    final savedNpub = await getConfig('bitchat_nostr_npub');
    final savedGeohash = await getConfig('bitchat_geohash');

    final localPath = await getDbPath();

    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }

    final newBytes = await File(newDbPath).readAsBytes();
    await File(localPath).writeAsBytes(newBytes, flush: true);

    _db = await openDatabase(localPath);
    await _createAllTables(_db!);

    if (savedToken != null && savedToken.isNotEmpty) await setHfToken(savedToken);
    if (savedUsername != null && savedUsername.isNotEmpty) await setHfUsername(savedUsername);
    if (savedRepo != null && savedRepo.isNotEmpty) await setHfRepo(savedRepo);
    if (savedBucket != null && savedBucket.isNotEmpty) await setHfBucket(savedBucket);

    if (savedNoisePriv != null && savedNoisePriv.isNotEmpty) await setConfig('bitchat_noise_priv', savedNoisePriv);
    if (savedNostrPriv != null && savedNostrPriv.isNotEmpty) await setConfig('bitchat_nostr_priv', savedNostrPriv);
    if (savedNick != null && savedNick.isNotEmpty) await setConfig('bitchat_nickname', savedNick);
    if (savedPeerId != null && savedPeerId.isNotEmpty) await setConfig('bitchat_peer_id', savedPeerId);
    if (savedNostrPub != null && savedNostrPub.isNotEmpty) await setConfig('bitchat_nostr_pubkey', savedNostrPub);
    if (savedNpub != null && savedNpub.isNotEmpty) await setConfig('bitchat_nostr_npub', savedNpub);
    if (savedGeohash != null && savedGeohash.isNotEmpty) await setConfig('bitchat_geohash', savedGeohash);
  }

  /// Exports a sanitized temporary copy of the database where private keys and auth tokens
  /// are securely stripped before uploading to cloud backups.
  Future<String> exportSanitizedDatabaseForCloudUpload() async {
    final localPath = await getDbPath();
    final tempDir = await getTemporaryDirectory();
    final sanitizedPath = p.join(tempDir.path, 'sanitized_upload_nyro_${DateTime.now().millisecondsSinceEpoch}.db');

    final localBytes = await File(localPath).readAsBytes();
    await File(sanitizedPath).writeAsBytes(localBytes, flush: true);

    // Open temporary copy and strip private keys and sensitive credentials
    final tempDb = await openDatabase(sanitizedPath);
    try {
      await tempDb.delete('app_config', where: "key IN ('hf_token', 'bitchat_noise_priv', 'bitchat_nostr_priv')");
      // Vacuum to ensure deleted data is not retained in SQLite free pages
      await tempDb.execute('VACUUM');
    } finally {
      await tempDb.close();
    }

    return sanitizedPath;
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

  // --- BitChat Persistence ---

  Future<void> insertBitchatMessage(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert('bitchat_messages', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getBitchatMessages({String? channel, int limit = 100}) async {
    final db = await database;
    if (channel != null) {
      return await db.query(
        'bitchat_messages',
        where: 'channel = ?',
        whereArgs: [channel],
        orderBy: 'timestamp ASC',
        limit: limit,
      );
    }
    return await db.query(
      'bitchat_messages',
      orderBy: 'timestamp ASC',
      limit: limit,
    );
  }

  Future<void> upsertBitchatPeer(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert('bitchat_peers', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getBitchatPeers() async {
    final db = await database;
    return await db.query('bitchat_peers', orderBy: 'last_seen DESC');
  }

  Future<void> upsertBitchatChannel(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert('bitchat_channels', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getBitchatChannels() async {
    final db = await database;
    return await db.query('bitchat_channels');
  }

  Future<void> updateBitchatMessageDeliveryStatus(String messageId, String status) async {
    final db = await database;
    await db.update(
      'bitchat_messages',
      {'delivery_status': status},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }
}
