import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tasks/data/database_service.dart';

class DesktopLogServerService {
  static final DesktopLogServerService instance = DesktopLogServerService._internal();
  DesktopLogServerService._internal();

  HttpServer? _server;
  String? _localIp;
  int _port = 8080;

  // Stream controller to notify the Flutter UI when a mistake is received from laptop
  final StreamController<Map<String, dynamic>> _mistakeStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onMistakeReceived => _mistakeStreamController.stream;

  bool get isRunning => _server != null;
  String? get serverUrl => isRunning && _localIp != null ? 'http://$_localIp:$_port' : null;
  String? get localIp => _localIp;
  int get port => _port;

  Future<String?> getDeviceIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal) {
            _localIp = addr.address;
            return _localIp;
          }
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        _localIp = interfaces.first.addresses.first.address;
        return _localIp;
      }
    } catch (e) {
      debugPrint('Error detecting local IP: $e');
    }
    _localIp = '127.0.0.1';
    return _localIp;
  }

  Future<String?> startServer({int port = 8080}) async {
    if (_server != null) {
      return serverUrl;
    }

    _port = port;
    await getDeviceIp();

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    } catch (_) {
      _port = 8888;
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    }

    _server!.listen((HttpRequest request) {
      _handleRequest(request);
    });

    debugPrint('Desktop Log Server running at http://$_localIp:$_port');
    return serverUrl;
  }

  Future<void> stopServer() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    debugPrint('Desktop Log Server stopped');
  }

  void _handleRequest(HttpRequest request) async {
    // Add CORS headers for desktop browser flexibility
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, Accept, Authorization');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    if (request.method == 'GET' && (path == '/' || path == '/index.html')) {
      _serveWebPortal(request);
    } else if (request.method == 'GET' && path == '/api/status') {
      final data = {
        'status': 'online',
        'app': 'NYRO Tasks Copilot',
        'version': '1.0.0',
        'ip': _localIp,
        'port': _port,
      };
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(data));
      await request.response.close();
    } else if (request.method == 'GET' && path == '/api/subjects') {
      final subjs = await DatabaseService.instance.getAllDistinctSubjects();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'subjects': subjs.where((s) => s != 'All Subjects').toList()}));
      await request.response.close();
    } else if (request.method == 'GET' && path == '/api/mistakes') {
      final mistakes = await DatabaseService.instance.getMistakeRecordsFiltered();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'mistakes': mistakes}));
      await request.response.close();
    } else if (request.method == 'POST' && path == '/api/mistakes') {
      await _handlePostMistake(request);
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Not Found');
      await request.response.close();
    }
  }

  Future<void> _handlePostMistake(HttpRequest request) async {
    try {
      final bodyStr = await utf8.decodeStream(request);
      final Map<String, dynamic> data = jsonDecode(bodyStr);

      final subject = data['subject'] as String? ?? 'General';
      final topic = data['topic'] as String? ?? 'Test Question';
      final questionText = data['question_text'] as String? ?? '';
      final wrongAnswer = data['wrong_answer'] as String? ?? '';
      final correctAnswer = data['correct_answer'] as String? ?? '';
      final mistakeReason = data['mistake_reason'] as String? ?? '';
      final keyTakeaway = data['key_takeaway'] as String? ?? '';
      final quizTitle = data['quiz_title'] as String? ?? '';
      final severity = (data['severity'] as String? ?? 'MEDIUM').toUpperCase();
      final imageBase64 = data['image_base64'] as String?;

      String? savedImagePath;
      if (imageBase64 != null && imageBase64.isNotEmpty) {
        try {
          final cleanBase64 = imageBase64.contains(',') ? imageBase64.split(',').last : imageBase64;
          final bytes = base64Decode(cleanBase64);
          final docsDir = await getApplicationDocumentsDirectory();
          final fileName = 'blunder_desktop_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final file = File('${docsDir.path}/$fileName');
          await file.writeAsBytes(bytes);
          savedImagePath = file.path;
        } catch (e) {
          debugPrint('Error saving blunder screenshot: $e');
        }
      }

      String finalTakeaway = keyTakeaway;
      if (savedImagePath != null) {
        finalTakeaway += '\n\n![Screenshot]($savedImagePath)';
      }

      final id = await DatabaseService.instance.insertMistakeRecord(
        subject: subject,
        topic: topic,
        questionText: questionText.isNotEmpty ? questionText : topic,
        wrongAnswer: wrongAnswer,
        correctAnswer: correctAnswer,
        mistakeReason: mistakeReason,
        keyTakeaway: finalTakeaway,
        quizTitle: quizTitle,
        severity: severity,
      );

      // Save into in-app notifications
      await DatabaseService.instance.addInAppNotification(
        title: 'Laptop Mistake Logged',
        message: '$subject • $topic',
        type: 'MISTAKE_LOG',
      );

      // Notify UI via stream
      final eventData = {
        'id': id,
        'subject': subject,
        'topic': topic,
        'severity': severity,
        'image_path': savedImagePath,
      };
      _mistakeStreamController.add(eventData);

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'success': true,
        'message': 'Mistake record successfully logged into NYRO Tasks app!',
        'id': id,
      }));
      await request.response.close();
    } catch (e) {
      debugPrint('Error processing desktop blunder log: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'Internal server error: $e'}));
      await request.response.close();
    }
  }

  void _serveWebPortal(HttpRequest request) {
    final html = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>NYRO Tasks - Laptop Blunder & Mistake Logger</title>
  <style>
    :root {
      --bg: #F8FAFC;
      --card: #FFFFFF;
      --text: #0F172A;
      --subtext: #64748B;
      --blue: #1A73E8;
      --blue-hover: #1557B0;
      --border: #E2E8F0;
      --accent: #E8F0FE;
      --red: #DC2626;
      --red-bg: #FEF2F2;
      --green: #16A34A;
      --green-bg: #F0FDF4;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Inter", sans-serif;
      background-color: var(--bg);
      color: var(--text);
      padding: 24px 16px;
      display: flex;
      justify-content: center;
      line-height: 1.5;
    }
    .container {
      width: 100%;
      max-width: 840px;
      background: var(--card);
      border-radius: 16px;
      border: 1px solid var(--border);
      box-shadow: 0 4px 20px rgba(0,0,0,0.06);
      padding: 28px;
    }
    .header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid var(--border);
      padding-bottom: 16px;
      margin-bottom: 24px;
    }
    .title-box { display: flex; align-items: center; gap: 12px; }
    .logo-badge {
      width: 40px; height: 40px; background: var(--blue); color: #fff;
      border-radius: 10px; display: flex; align-items: center; justify-content: center;
      font-weight: 800; font-size: 20px;
    }
    h1 { font-size: 20px; font-weight: 700; }
    p.subtitle { font-size: 13px; color: var(--subtext); margin-top: 2px; }
    .status-badge {
      display: flex; align-items: center; gap: 6px; font-size: 12px;
      background: var(--green-bg); color: var(--green); font-weight: 600;
      padding: 6px 12px; border-radius: 20px; border: 1px solid rgba(22,163,74,0.25);
    }
    .dot { width: 8px; height: 8px; background: var(--green); border-radius: 50%; }

    .form-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 16px;
      margin-bottom: 16px;
    }
    .full-width { grid-column: 1 / -1; }
    label {
      display: block; font-size: 12.5px; font-weight: 600; color: var(--subtext);
      margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.4px;
    }
    input, select, textarea {
      width: 100%; padding: 10px 14px; border: 1.5px solid var(--border);
      border-radius: 8px; font-size: 14px; font-family: inherit; outline: none;
      transition: border-color 0.15s; background: #fff;
    }
    input:focus, select:focus, textarea:focus {
      border-color: var(--blue);
      box-shadow: 0 0 0 3px rgba(26,115,232,0.12);
    }
    textarea { resize: vertical; min-height: 80px; }

    /* Paste Dropzone */
    .paste-zone {
      border: 2px dashed #93C5FD;
      background: var(--accent);
      border-radius: 12px;
      padding: 20px;
      text-align: center;
      cursor: pointer;
      position: relative;
      margin-bottom: 18px;
      transition: all 0.2s;
    }
    .paste-zone:hover { background: #DBEAFE; }
    .paste-zone p.main-text { font-size: 14px; font-weight: 600; color: var(--blue); }
    .paste-zone p.sub-text { font-size: 12px; color: var(--subtext); margin-top: 4px; }
    .preview-box {
      margin-top: 12px; display: none; align-items: center; justify-content: center;
      position: relative;
    }
    .preview-box img {
      max-height: 180px; max-width: 100%; border-radius: 8px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.1); border: 1px solid var(--border);
    }
    .remove-btn {
      position: absolute; top: 4px; right: 4px; background: rgba(0,0,0,0.7);
      color: #fff; border: none; border-radius: 50%; width: 24px; height: 24px;
      cursor: pointer; font-size: 14px; line-height: 24px; text-align: center;
    }

    .btn-row { display: flex; justify-content: flex-end; gap: 12px; margin-top: 8px; }
    button.submit-btn {
      background: var(--blue); color: #fff; border: none; border-radius: 8px;
      padding: 12px 28px; font-size: 14px; font-weight: 700; cursor: pointer;
      display: flex; align-items: center; gap: 8px; transition: background 0.15s;
    }
    button.submit-btn:hover { background: var(--blue-hover); }
    button.submit-btn:disabled { background: #94A3B8; cursor: not-allowed; }

    .toast {
      position: fixed; top: 20px; right: 20px; background: #0F172A; color: #fff;
      padding: 12px 20px; border-radius: 8px; font-size: 13.5px; font-weight: 600;
      box-shadow: 0 4px 12px rgba(0,0,0,0.15); display: none; z-index: 999;
    }

    .recent-header {
      margin-top: 32px; padding-top: 20px; border-top: 1px solid var(--border);
      font-size: 15px; font-weight: 700; color: var(--text); display: flex;
      justify-content: space-between; align-items: center;
    }
    .recent-list { margin-top: 12px; display: flex; flex-direction: column; gap: 10px; }
    .blunder-card {
      padding: 12px 16px; border: 1px solid var(--border); border-radius: 10px;
      background: #F8FAFC; display: flex; justify-content: space-between; align-items: center;
    }
    .blunder-card h4 { font-size: 13.5px; font-weight: 600; }
    .blunder-card p { font-size: 12px; color: var(--subtext); margin-top: 2px; }
    .sev-pill {
      font-size: 10px; font-weight: 800; padding: 3px 8px; border-radius: 12px;
      text-transform: uppercase;
    }
    .sev-HIGH { background: #FEE2E2; color: #DC2626; }
    .sev-MEDIUM { background: #FEF3C7; color: #D97706; }
    .sev-LOW { background: #E0E7FF; color: #4338CA; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="title-box">
        <div class="logo-badge">✓</div>
        <div>
          <h1>NYRO Tasks • Desktop Test Logger</h1>
          <p class="subtitle">Quickly log test series mistakes directly from your laptop to phone</p>
        </div>
      </div>
      <div class="status-badge">
        <span class="dot"></span> Connected
      </div>
    </div>

    <!-- Paste Dropzone -->
    <div class="paste-zone" id="pasteZone">
      <p class="main-text">📋 Press Ctrl+V to paste screenshot from clipboard</p>
      <p class="sub-text">Or click to select an image from your computer</p>
      <input type="file" id="fileInput" accept="image/*" style="display: none;">
      <div class="preview-box" id="previewBox">
        <img id="previewImg" src="" alt="Screenshot">
        <button type="button" class="remove-btn" id="removeImgBtn">&times;</button>
      </div>
    </div>

    <form id="mistakeForm">
      <div class="form-grid">
        <div>
          <label>Subject</label>
          <input type="text" id="subjectInput" placeholder="e.g. Engineering Mathematics" list="subjectsList" required>
          <datalist id="subjectsList"></datalist>
        </div>
        <div>
          <label>Severity</label>
          <select id="severitySelect">
            <option value="HIGH">High (Concept Trap / Fatal Blunder)</option>
            <option value="MEDIUM" selected>Medium (Calculation Slip)</option>
            <option value="LOW">Low (Silly / Reading Oversight)</option>
          </select>
        </div>

        <div class="full-width">
          <label>Topic / Question Details</label>
          <input type="text" id="topicInput" placeholder="e.g. Q18: Eigenvalues of Skew-Symmetric Matrix" required>
        </div>

        <div>
          <label>Quiz / Test Title (Optional)</label>
          <input type="text" id="quizInput" placeholder="e.g. MadeEasy Mock 2">
        </div>
        <div>
          <label>Correct Answer</label>
          <input type="text" id="correctInput" placeholder="e.g. Purely imaginary or zero">
        </div>

        <div class="full-width">
          <label>Mistake Reason / Where did I get stuck?</label>
          <textarea id="reasonInput" placeholder="I assumed the eigenvalues were real because I confused symmetric with skew-symmetric..."></textarea>
        </div>

        <div class="full-width">
          <label>Key Takeaway / Concept to Remember</label>
          <textarea id="takeawayInput" placeholder="Skew-symmetric matrices have A^T = -A, so lambda = -conj(lambda). Hence eigenvalues are purely imaginary or 0!" required></textarea>
        </div>
      </div>

      <div class="btn-row">
        <button type="submit" class="submit-btn" id="submitBtn">
          <span>Log Mistake to Phone</span> ➔
        </button>
      </div>
    </form>

    <div class="recent-header">
      <span>Mistakes Logged This Session</span>
      <span id="sessionCount" style="font-size: 12px; color: var(--subtext);">0 items</span>
    </div>
    <div class="recent-list" id="recentList">
      <p style="font-size: 13px; color: var(--subtext); padding: 12px 0;">No mistakes logged in this session yet.</p>
    </div>
  </div>

  <div class="toast" id="toast"></div>

  <script>
    let pastedImageBase64 = null;
    let loggedItems = [];

    // Auto-fetch existing subjects from phone
    fetch('/api/subjects').then(r => r.json()).then(data => {
      const list = document.getElementById('subjectsList');
      if (data && data.subjects) {
        data.subjects.forEach(s => {
          const opt = document.createElement('option');
          opt.value = s;
          list.appendChild(opt);
        });
      }
    }).catch(() => {});

    // Ctrl+V paste listener anywhere on window
    window.addEventListener('paste', e => {
      const items = (e.clipboardData || e.originalEvent.clipboardData).items;
      for (const item of items) {
        if (item.type.indexOf('image') !== -1) {
          const blob = item.getAsFile();
          handleImageFile(blob);
          showToast('📸 Screenshot pasted from clipboard!');
          break;
        }
      }
    });

    const pasteZone = document.getElementById('pasteZone');
    const fileInput = document.getElementById('fileInput');
    pasteZone.addEventListener('click', e => {
      if (e.target.id !== 'removeImgBtn') fileInput.click();
    });

    fileInput.addEventListener('change', e => {
      if (e.target.files && e.target.files[0]) {
        handleImageFile(e.target.files[0]);
      }
    });

    function handleImageFile(file) {
      const reader = new FileReader();
      reader.onload = evt => {
        pastedImageBase64 = evt.target.result;
        document.getElementById('previewImg').src = pastedImageBase64;
        document.getElementById('previewBox').style.display = 'flex';
      };
      reader.readAsDataURL(file);
    }

    document.getElementById('removeImgBtn').addEventListener('click', e => {
      e.stopPropagation();
      pastedImageBase64 = null;
      document.getElementById('previewBox').style.display = 'none';
      document.getElementById('previewImg').src = '';
      fileInput.value = '';
    });

    function showToast(msg) {
      const t = document.getElementById('toast');
      t.innerText = msg;
      t.style.display = 'block';
      setTimeout(() => { t.style.display = 'none'; }, 3500);
    }

    // Submit handler
    document.getElementById('mistakeForm').addEventListener('submit', async e => {
      e.preventDefault();
      const btn = document.getElementById('submitBtn');
      btn.disabled = true;
      btn.innerText = 'Logging to phone...';

      const payload = {
        subject: document.getElementById('subjectInput').value.trim(),
        severity: document.getElementById('severitySelect').value,
        topic: document.getElementById('topicInput').value.trim(),
        quiz_title: document.getElementById('quizInput').value.trim(),
        correct_answer: document.getElementById('correctInput').value.trim(),
        mistake_reason: document.getElementById('reasonInput').value.trim(),
        key_takeaway: document.getElementById('takeawayInput').value.trim(),
        image_base64: pastedImageBase64
      };

      try {
        const res = await fetch('/api/mistakes', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (res.ok && data.success) {
          showToast('✅ Mistake recorded in Tasks app!');
          loggedItems.unshift(payload);
          updateRecentList();
          // Reset form
          document.getElementById('topicInput').value = '';
          document.getElementById('reasonInput').value = '';
          document.getElementById('takeawayInput').value = '';
          document.getElementById('correctInput').value = '';
          pastedImageBase64 = null;
          document.getElementById('previewBox').style.display = 'none';
          document.getElementById('previewImg').src = '';
          fileInput.value = '';
        } else {
          showToast('❌ Error: ' + (data.error || 'Failed to save'));
        }
      } catch (err) {
        showToast('❌ Connection error: ' + err);
      } finally {
        btn.disabled = false;
        btn.innerHTML = '<span>Log Mistake to Phone</span> ➔';
      }
    });

    function updateRecentList() {
      const list = document.getElementById('recentList');
      document.getElementById('sessionCount').innerText = loggedItems.length + ' items';
      if (loggedItems.length === 0) {
        list.innerHTML = '<p style="font-size: 13px; color: var(--subtext); padding: 12px 0;">No mistakes logged in this session yet.</p>';
        return;
      }
      list.innerHTML = loggedItems.map(item => `
        <div class="blunder-card">
          <div>
            <h4>\${item.subject} • \${item.topic}</h4>
            <p>\${item.key_takeaway.substring(0, 90)}\${item.key_takeaway.length > 90 ? '...' : ''}</p>
          </div>
          <span class="sev-pill sev-\${item.severity}">\${item.severity}</span>
        </div>
      `).join('');
    }
  </script>
</body>
</html>
''';

    request.response.headers.contentType = ContentType.html;
    request.response.write(html);
    request.response.close();
  }
}
