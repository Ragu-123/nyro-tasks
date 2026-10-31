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
      targetHours = lecs.fold(0.0, (sum, l) => sum + ((l['duration_hours'] as num?)?.toDouble() ?? 1.0));
      watchedHours = lecs
          .where((l) => (l['status'] as String?)?.toUpperCase() == 'COMPLETED')
          .fold(0.0, (sum, l) => sum + ((l['duration_hours'] as num?)?.toDouble() ?? 1.0));
    } else if (daily.isNotEmpty) {
      targetHours = (daily.first['target_hours'] as num?)?.toDouble() ?? 8.0;
      watchedHours = (daily.first['watched_hours'] as num?)?.toDouble() ?? 0.0;
    }

    return {
      'target_hours': targetHours,
      'watched_hours': watchedHours,
      'lecture_count': lecs.length,
      'completed_count': lecs.where((l) => (l['status'] as String?)?.toUpperCase() == 'COMPLETED').length,
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

    // Update daily_sessions
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

  Future<List<Map<String, dynamic>>> getAllSpacedRevisits() async {
    final db = await database;
    return await db.rawQuery(
      'SELECT * FROM revisit_items WHERE due_date IS NOT NULL AND status != "DONE" ORDER BY due_date ASC LIMIT 100',
    );
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

  // --- Mistake Notebook ---

  Future<List<Map<String, dynamic>>> getMistakeRecords() async {
    final db = await database;
    return await db.rawQuery('SELECT * FROM mistake_records ORDER BY id DESC');
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

  // --- Timetable / Curriculum ---

  Future<List<Map<String, dynamic>>> getAllCurriculumSessions() async {
    final db = await database;
    return await db.rawQuery('SELECT * FROM lectures ORDER BY id ASC');
  }

  Future<List<Map<String, dynamic>>> searchCurriculum(String query) async {
    final db = await database;
    final term = '%$query%';
    return await db.rawQuery(
      'SELECT * FROM lectures WHERE topic LIKE ? OR details LIKE ? OR date_str LIKE ? ORDER BY id ASC',
      [term, term, term],
    );
  }

  // --- Quizzes & Tests ---

  Future<List<Map<String, dynamic>>> getQuizzesByType(String type) async {
    final db = await database;
    return await db.query(
      'quiz_items',
      where: 'quiz_type = ?',
      whereArgs: [type],
      orderBy: 'id ASC',
    );
  }

  // --- Custom Reminders ---

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
