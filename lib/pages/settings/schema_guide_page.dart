import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/widgets/top_banner_notification.dart';

class DatabaseSchemaGuidePage extends StatelessWidget {
  const DatabaseSchemaGuidePage({Key? key}) : super(key: key);

  void _copyToClipboard(BuildContext context, String title, String code) {
    Clipboard.setData(ClipboardData(text: code));
    TopBanner.show(
      context,
      title: 'Copied to Clipboard',
      message: '$title template copied.',
      icon: Icons.check_circle_outline_rounded,
      color: googleGreen,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Database Schema Guide',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: googleTextPrimary),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: googleTextPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: googleBlue.withOpacity(0.3)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schema_outlined, color: googleBlue, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mass DB Preparation & Import Guide',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: googleBlue),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Follow these exact table structures to mass-generate your lecture timetable, test series, and spaced recall checkpoints using Python, ChatGPT, or SQLite, and sync directly via Hugging Face.',
                        style: TextStyle(fontSize: 12, color: googleTextPrimary, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 1. Lectures (Schedule)
          _buildTableCard(
            context: context,
            tableName: 'lectures (Schedule)',
            description: 'Stores daily study lectures and time pacing. Date format: "dd MMM yyyy" (e.g. "18 Oct 2026").',
            schemaSql: '''CREATE TABLE lectures (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date_str VARCHAR,        -- e.g. "18 Oct 2026"
  topic VARCHAR,           -- e.g. "Calculus • Module 1"
  details VARCHAR,         -- e.g. "Lecture 1: Limits & Continuity"
  duration_hours FLOAT,    -- e.g. 1.5, 2.0
  session_block VARCHAR,   -- e.g. "Morning Block", "Evening Block"
  status VARCHAR,          -- "PENDING" or "COMPLETED"
  completed_at DATETIME    -- ISO string when completed
);''',
            jsonExample: '''[
  {
    "date_str": "18 Oct 2026",
    "topic": "Calculus and Optimization • Limits",
    "details": "Lecture 1: Finding Limit of a function",
    "duration_hours": 2.0,
    "session_block": "Morning Block",
    "status": "PENDING"
  }
]''',
          ),
          const SizedBox(height: 20),

          // 2. Revisit Items (Spaced Repetition)
          _buildTableCard(
            context: context,
            tableName: 'revisit_items (Spaced Recalls)',
            description: 'Ebbinghaus forgetting curve checkpoints linked to lectures. Offsets: Day 1 (+1d, 20m), Day 4 (+4d, 25m), Day 7 (+7d, 30m), Day 14 (+14d, 30m), Day 30 (+30d, 30m).',
            schemaSql: '''CREATE TABLE revisit_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  lecture_id INTEGER,      -- Reference to lectures.id
  topic VARCHAR,           -- e.g. "Calculus • Lecture 1"
  stage VARCHAR,           -- "Day 1 (24h)", "Day 4", "Day 7", "Day 14", "Day 30"
  duration_mins INTEGER,   -- e.g. 20, 25, 30
  due_date VARCHAR,        -- e.g. "19 Oct 2026"
  status VARCHAR,          -- "DUE" or "DONE"
  completed_at DATETIME,
  offset_days INTEGER      -- 1, 4, 7, 14, 30
);''',
            jsonExample: '''[
  {
    "lecture_id": 1,
    "topic": "Calculus • Lecture 1: Limits",
    "stage": "Day 1 (24h)",
    "duration_mins": 20,
    "due_date": "19 Oct 2026",
    "status": "DUE",
    "offset_days": 1
  }
]''',
          ),
          const SizedBox(height: 20),

          // 3. Quiz Items
          _buildTableCard(
            context: context,
            tableName: 'quiz_items (Quizzes & Tests)',
            description: 'Weekly quizzes and Test Series mocks for GATE prep.',
            schemaSql: '''CREATE TABLE quiz_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  quiz_type VARCHAR,       -- "WEEKLY_QUIZ" or "TEST_SERIES"
  title VARCHAR,           -- e.g. "Weekly Quiz 1: Calculus"
  subject VARCHAR,         -- e.g. "Engineering Mathematics"
  module_name VARCHAR,     -- e.g. "Module 1"
  date_str VARCHAR,        -- e.g. "24 Oct 2026"
  duration_mins INTEGER,   -- e.g. 45
  total_marks INTEGER,     -- e.g. 25
  syllabus_topics VARCHAR, -- Syllabus summary
  action_url VARCHAR,      -- Link to online test portal
  status VARCHAR           -- "PENDING" or "COMPLETED"
);''',
            jsonExample: '''[
  {
    "quiz_type": "WEEKLY_QUIZ",
    "title": "Weekly Quiz 1: Limits & Continuity",
    "subject": "Calculus and Optimization",
    "date_str": "24 Oct 2026",
    "duration_mins": 45,
    "total_marks": 25,
    "syllabus_topics": "Indeterminate forms, L-Hopital rule, Epsilon-Delta",
    "status": "PENDING"
  }
]''',
          ),
          const SizedBox(height: 20),

          // 4. Mistake Records
          _buildTableCard(
            context: context,
            tableName: 'mistake_records (Blunder Notebook)',
            description: 'Mistakes logged during test series and study sessions.',
            schemaSql: '''CREATE TABLE mistake_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  subject VARCHAR,         -- e.g. "Computer Networks"
  topic VARCHAR,           -- e.g. "TCP Congestion Control"
  question_text VARCHAR,   -- Question text or summary
  wrong_answer VARCHAR,    -- What you answered incorrectly
  correct_answer VARCHAR,  -- Correct answer
  mistake_reason VARCHAR,  -- Trap or conceptual confusion
  key_takeaway VARCHAR,    -- Markdown note / formula fix
  quiz_title VARCHAR,      -- e.g. "MadeEasy Mock 2"
  severity VARCHAR,        -- "HIGH", "MEDIUM", "LOW"
  status VARCHAR           -- "UNRESOLVED" or "RESOLVED"
);''',
            jsonExample: '''[
  {
    "subject": "Computer Networks",
    "topic": "TCP Fast Retransmit",
    "question_text": "Number of duplicate ACKs needed for fast retransmit",
    "wrong_answer": "2",
    "correct_answer": "3 duplicate ACKs",
    "mistake_reason": "Forgot that receiver sends duplicate ACK on each out-of-order segment",
    "key_takeaway": "Fast retransmit requires 3 duplicate ACKs (4 identical ACKs total).",
    "severity": "MEDIUM",
    "status": "UNRESOLVED"
  }
]''',
          ),
        ],
      ),
    );
  }

  Widget _buildTableCard({
    required BuildContext context,
    required String tableName,
    required String description,
    required String schemaSql,
    required String jsonExample,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: googleHairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tableName,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: googleTextPrimary),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18, color: googleBlue),
                tooltip: 'Copy JSON Template',
                onPressed: () => _copyToClipboard(context, tableName, jsonExample),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(fontSize: 12, color: googleTextSecondary)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: googleHairline),
            ),
            child: SelectableText(
              schemaSql,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }
}
