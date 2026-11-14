import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/services/app_update_service.dart';

class DesktopLogServerService {
  static final DesktopLogServerService instance = DesktopLogServerService._internal();
  DesktopLogServerService._internal() {
    _generateNewPinInternal();
  }

  HttpServer? _server;
  String? _localIp;
  int _port = 8080;

  // 6-digit Authenticator Wi-Fi Shield PIN
  String _pairingPin = '123456';
  final Map<String, DateTime> _activeSessions = <String, DateTime>{};
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  final Map<String, int> _failedAttemptsByIp = <String, int>{};
  final Map<String, DateTime> _lockoutByIp = <String, DateTime>{};

  // Stream controller to notify Flutter UI when a mistake is received from desktop
  final StreamController<Map<String, dynamic>> _mistakeStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onMistakeReceived => _mistakeStreamController.stream;

  bool get isRunning => _server != null;
  String? get serverUrl => isRunning && _localIp != null ? 'http://$_localIp:$_port' : null;
  String? get localIp => _localIp;
  int get port => _port;
  String get pairingPin => _pairingPin;

  String generateNewPin() {
    final pin = _generateNewPinInternal();
    // Revoke all existing sessions so laptop must re-verify
    _activeSessions.clear();
    _failedAttempts = 0;
    _lockoutUntil = null;
    _failedAttemptsByIp.clear();
    _lockoutByIp.clear();
    return pin;
  }

  String _generateNewPinInternal() {
    final rand = Random.secure();
    final pinNum = 100000 + rand.nextInt(900000);
    _pairingPin = pinNum.toString();
    return _pairingPin;
  }

  static bool _constantTimeEqual(String a, String b) {
    if (a.length != b.length) return false;
    int res = 0;
    for (int i = 0; i < a.length; i++) {
      res |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return res == 0;
  }

  String? verifyPin(String inputPin, {String? clientIp}) {
    final now = DateTime.now();

    // Check IP lockout first if clientIp provided
    if (clientIp != null && _lockoutByIp.containsKey(clientIp)) {
      final ipLockout = _lockoutByIp[clientIp]!;
      if (now.isBefore(ipLockout)) {
        final waitSecs = ipLockout.difference(now).inSeconds;
        throw Exception('Too many failed attempts from your IP. Locked for $waitSecs seconds.');
      }
    }

    // Check global lockout
    if (_lockoutUntil != null && now.isBefore(_lockoutUntil!)) {
      final waitSecs = _lockoutUntil!.difference(now).inSeconds;
      throw Exception('Too many failed attempts. Locked for $waitSecs seconds.');
    }

    final cleanInput = inputPin.trim().replaceAll(RegExp(r'\s+'), '');
    if (_constantTimeEqual(cleanInput, _pairingPin)) {
      _failedAttempts = 0;
      _lockoutUntil = null;
      if (clientIp != null) {
        _failedAttemptsByIp.remove(clientIp);
        _lockoutByIp.remove(clientIp);
      }
      // Generate secure 32-byte (64-character hex) session token
      final rand = Random.secure();
      final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
      final token = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final expiry = now.add(const Duration(hours: 12));
      _activeSessions[token] = expiry;
      _pruneExpiredSessions();
      return token;
    } else {
      _failedAttempts++;
      if (clientIp != null) {
        _failedAttemptsByIp[clientIp] = (_failedAttemptsByIp[clientIp] ?? 0) + 1;
      }

      // Exponential lockout policy: 5 -> 1m, 6 -> 5m, 7 -> 15m, 8+ -> 60m
      final attempts = max(_failedAttempts, clientIp != null ? (_failedAttemptsByIp[clientIp] ?? 0) : 0);
      Duration? lockDuration;
      if (attempts >= 8) {
        lockDuration = const Duration(minutes: 60);
      } else if (attempts == 7) {
        lockDuration = const Duration(minutes: 15);
      } else if (attempts == 6) {
        lockDuration = const Duration(minutes: 5);
      } else if (attempts >= 5) {
        lockDuration = const Duration(minutes: 1);
      }

      if (lockDuration != null) {
        final lockExpiry = now.add(lockDuration);
        _lockoutUntil = lockExpiry;
        if (clientIp != null) {
          _lockoutByIp[clientIp] = lockExpiry;
        }
      }
      return null;
    }
  }

  void _pruneExpiredSessions() {
    final now = DateTime.now();
    _activeSessions.removeWhere((_, expiry) => now.isAfter(expiry));
  }

  bool isSessionValid(String? token) {
    if (token == null || token.isEmpty) return false;
    final trimmed = token.trim();
    if (!RegExp(r'^[a-fA-F0-9]{32,64}$').hasMatch(trimmed)) return false;
    final expiry = _activeSessions[trimmed];
    if (expiry == null) return false;
    if (DateTime.now().isAfter(expiry)) {
      _activeSessions.remove(trimmed);
      return false;
    }
    return true;
  }

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

    debugPrint('Desktop Log Server running at http://$_localIp:$_port (PIN: $_pairingPin)');
    return serverUrl;
  }

  Future<void> stopServer() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _activeSessions.clear();
    debugPrint('Desktop Log Server stopped');
  }

  Future<String?> _readLimitedBody(HttpRequest request, {int maxBytes = 10 * 1024 * 1024}) async {
    final contentLength = request.headers.contentLength;
    if (contentLength > maxBytes) {
      request.response.statusCode = HttpStatus.requestEntityTooLarge;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'Payload Too Large', 'max_bytes': maxBytes}));
      await request.response.close();
      return null;
    }

    final builder = BytesBuilder(copy: false);
    int totalBytes = 0;
    await for (final chunk in request) {
      totalBytes += chunk.length;
      if (totalBytes > maxBytes) {
        request.response.statusCode = HttpStatus.requestEntityTooLarge;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Payload Too Large', 'max_bytes': maxBytes}));
        await request.response.close();
        return null;
      }
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes());
  }

  void _handleRequest(HttpRequest request) async {
    // Add CORS headers for desktop browser flexibility
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Origin, Content-Type, Accept, Authorization');
    request.response.headers.add('X-Content-Type-Options', 'nosniff');
    request.response.headers.add('X-Frame-Options', 'DENY');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    final authHeader = request.headers.value('Authorization');
    String? token;
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      token = authHeader.substring(7).trim();
    }
    final isAuthenticated = isSessionValid(token);

    // 1. Root Portal & Static Assets (Unauthenticated)
    if (request.method == 'GET' && (path == '/' || path == '/index.html')) {
      _serveWebPortal(request);
      return;
    }

    // 2. Auth Verification Endpoint (Public)
    if (request.method == 'POST' && path == '/api/auth/verify') {
      await _handleAuthVerify(request);
      return;
    }

    // 3. Auth Status Check (Public)
    if (request.method == 'GET' && path == '/api/auth/status') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'authenticated': isAuthenticated}));
      await request.response.close();
      return;
    }

    // 4. Auth Logout Endpoint (Invalidates Session)
    if ((request.method == 'POST' || request.method == 'GET') && path == '/api/auth/logout') {
      if (token != null) {
        _activeSessions.remove(token);
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'message': 'Logged out successfully'}));
      await request.response.close();
      return;
    }

    // 5. Server Status Endpoint (Public)
    if (request.method == 'GET' && path == '/api/status') {
      final data = {
        'status': 'online',
        'app': 'NYRO Tasks Copilot',
        'version': AppUpdateService.currentVersion,
        'ip': _localIp,
        'port': _port,
        'authenticated': isAuthenticated,
      };
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(data));
      await request.response.close();
      return;
    }

    // --- PROTECTED ROUTES: Require 6-digit Authenticator Session ---
    if (!isAuthenticated) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'error': 'Unauthorized',
        'message': 'Please enter the 6-digit PIN displayed on your phone app to access this service.',
      }));
      await request.response.close();
      return;
    }

    // 6. Distinct Subjects List
    if (request.method == 'GET' && path == '/api/subjects') {
      final subjs = await DatabaseService.instance.getAllDistinctSubjects();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'subjects': subjs.where((s) => s != 'All Subjects').toList()}));
      await request.response.close();
      return;
    }

    // 7. Mistakes API
    if (request.method == 'GET' && path == '/api/mistakes') {
      final subjectFilter = request.uri.queryParameters['subject'];
      final severityFilter = request.uri.queryParameters['severity'];
      final statusFilter = request.uri.queryParameters['status'];
      final quizFilter = request.uri.queryParameters['quiz'];
      final search = request.uri.queryParameters['search'];

      List<Map<String, dynamic>> mistakes;
      if (statusFilter != null && (statusFilter.toUpperCase() == 'UNRESOLVED' || statusFilter.toUpperCase() == 'PENDING')) {
        final all = await DatabaseService.instance.getMistakeRecordsFiltered(
          subject: subjectFilter,
          severity: severityFilter,
          quizTitle: quizFilter,
          searchQuery: search,
        );
        mistakes = all.where((m) {
          final st = (m['status']?.toString() ?? '').toUpperCase();
          return st != 'RESOLVED' && st != 'COMPLETED' && st != 'DONE';
        }).toList();
      } else {
        mistakes = await DatabaseService.instance.getMistakeRecordsFiltered(
          subject: subjectFilter,
          severity: severityFilter,
          status: statusFilter,
          quizTitle: quizFilter,
          searchQuery: search,
        );
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'mistakes': mistakes}));
      await request.response.close();
      return;
    }

    // 7. Post Mistake Log
    if (request.method == 'POST' && path == '/api/mistakes') {
      await _handlePostMistake(request);
      return;
    }

    // 8. Toggle Resolved Status
    if (request.method == 'PATCH' && path.startsWith('/api/mistakes/') && path.endsWith('/resolve')) {
      final parts = path.split('/');
      final id = int.tryParse(parts[3]);
      if (id != null) {
        final bodyStr = await _readLimitedBody(request, maxBytes: 65536);
        if (bodyStr == null) return;
        final Map<String, dynamic> data = jsonDecode(bodyStr);
        final isResolved = data['resolved'] as bool? ?? true;
        await DatabaseService.instance.toggleMistakeResolved(id, isResolved);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true, 'id': id, 'resolved': isResolved}));
        await request.response.close();
        return;
      }
    }

    // 9. Delete Mistake Record
    if (request.method == 'DELETE' && path.startsWith('/api/mistakes/')) {
      final parts = path.split('/');
      final id = int.tryParse(parts.last);
      if (id != null) {
        await DatabaseService.instance.deleteMistakeRecord(id);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true, 'id': id}));
        await request.response.close();
        return;
      }
    }

    // 10. Serve Saved Screenshots with Path Traversal & Injection Defense
    if (request.method == 'GET' && path.startsWith('/api/images/')) {
      final imageName = path.substring('/api/images/'.length);
      final safeImagePattern = RegExp(r'^[a-zA-Z0-9_\-]+\.(jpg|jpeg|png|webp)$', caseSensitive: false);
      if (!safeImagePattern.hasMatch(imageName) || imageName.contains('..') || imageName.contains('/') || imageName.contains('\\')) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Invalid image filename'}));
        await request.response.close();
        return;
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final imageFile = File('${docsDir.path}/$imageName');

      try {
        final canonicalDocs = docsDir.resolveSymbolicLinksSync();
        final canonicalFile = imageFile.resolveSymbolicLinksSync();
        if (!canonicalFile.startsWith(canonicalDocs)) {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'error': 'Access denied'}));
          await request.response.close();
          return;
        }
      } catch (_) {
        // Symbolic link check failed or file does not exist
      }

      if (await imageFile.exists()) {
        final ext = imageName.split('.').last.toLowerCase();
        final subType = (ext == 'png') ? 'png' : (ext == 'webp' ? 'webp' : 'jpeg');
        request.response.headers.contentType = ContentType('image', subType);
        request.response.headers.add('X-Content-Type-Options', 'nosniff');
        request.response.headers.add('Cache-Control', 'private, max-age=86400');
        await imageFile.openRead().pipe(request.response);
        return;
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Image not found'}));
        await request.response.close();
        return;
      }
    }

    request.response.statusCode = HttpStatus.notFound;
    request.response.write('Not Found');
    await request.response.close();
  }

  Future<void> _handleAuthVerify(HttpRequest request) async {
    try {
      final bodyStr = await _readLimitedBody(request, maxBytes: 65536);
      if (bodyStr == null) return;
      final Map<String, dynamic> data = jsonDecode(bodyStr);
      final inputPin = data['pin']?.toString() ?? '';
      final clientIp = request.connectionInfo?.remoteAddress.address;

      final token = verifyPin(inputPin, clientIp: clientIp);
      if (token != null) {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'success': true,
          'token': token,
          'message': 'Successfully authenticated with phone Wi-Fi shield!',
        }));
      } else {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'success': false,
          'error': 'Invalid 6-digit PIN. Check the code displayed in your phone app.',
        }));
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'success': false,
        'error': e.toString().replaceAll('Exception: ', ''),
      }));
    }
    await request.response.close();
  }

  Future<void> _handlePostMistake(HttpRequest request) async {
    try {
      final bodyStr = await _readLimitedBody(request, maxBytes: 10 * 1024 * 1024);
      if (bodyStr == null) return;
      final Map<String, dynamic> data = jsonDecode(bodyStr);

      String sanitizeField(dynamic val, int maxLen, {String fallback = ''}) {
        if (val == null) return fallback;
        final s = val
            .toString()
            .replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'), '')
            .replaceAll('<script', '&lt;script')
            .replaceAll('</script', '&lt;/script')
            .trim();
        return s.length > maxLen ? s.substring(0, maxLen) : (s.isEmpty ? fallback : s);
      }

      final subject = sanitizeField(data['subject'], 100, fallback: 'General');
      final topic = sanitizeField(data['topic'], 200, fallback: 'Test Question');
      final questionText = sanitizeField(data['question_text'], 10000);
      final wrongAnswer = sanitizeField(data['wrong_answer'], 2000);
      final correctAnswer = sanitizeField(data['correct_answer'], 2000);
      final mistakeReason = sanitizeField(data['mistake_reason'], 5000);
      final keyTakeaway = sanitizeField(data['key_takeaway'], 5000);
      final quizTitle = sanitizeField(data['quiz_title'], 200);

      final rawSeverity = (data['severity'] as String? ?? 'MEDIUM').toUpperCase().trim();
      final severity = const {'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'}.contains(rawSeverity) ? rawSeverity : 'MEDIUM';

      final imageBase64 = data['image_base64'] as String?;

      String? savedImagePath;
      String? savedFileName;
      if (imageBase64 != null && imageBase64.isNotEmpty && imageBase64.length <= 8 * 1024 * 1024) {
        try {
          final cleanBase64 = imageBase64.contains(',') ? imageBase64.split(',').last : imageBase64;
          final bytes = base64Decode(cleanBase64.replaceAll(RegExp(r'\s+'), ''));
          if (bytes.length <= 6 * 1024 * 1024) {
            final docsDir = await getApplicationDocumentsDirectory();
            savedFileName = 'blunder_desktop_${DateTime.now().millisecondsSinceEpoch}_${Random.secure().nextInt(9999)}.jpg';
            final file = File('${docsDir.path}/$savedFileName');
            await file.writeAsBytes(bytes, flush: true);
            savedImagePath = file.path;
          }
        } catch (e) {
          debugPrint('Error saving blunder screenshot: $e');
        }
      }

      String finalTakeaway = keyTakeaway;
      if (savedFileName != null) {
        finalTakeaway += '\n\n![Screenshot](/api/images/$savedFileName)';
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
        'saved_image': savedFileName != null ? '/api/images/$savedFileName' : null,
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
    final version = AppUpdateService.currentVersion;
    final html = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>NYRO Tasks • Desktop Mistake Studio</title>
  <style>
    :root {
      --bg: #F8FAFC;
      --card: #FFFFFF;
      --text: #0F172A;
      --subtext: #64748B;
      --blue: #1A73E8;
      --blue-hover: #1557B0;
      --blue-subtle: #E8F0FE;
      --border: #E2E8F0;
      --border-dark: #CBD5E1;
      --red: #DC2626;
      --red-bg: #FEF2F2;
      --green: #16A34A;
      --green-bg: #F0FDF4;
      --amber: #D97706;
      --amber-bg: #FEF3C7;
      --code-bg: #F1F5F9;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Inter", sans-serif;
      background-color: var(--bg);
      color: var(--text);
      line-height: 1.5;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }
    .app-nav {
      background: #FFFFFF;
      border-bottom: 1px solid var(--border);
      position: sticky;
      top: 0;
      z-index: 100;
      box-shadow: 0 1px 3px rgba(0,0,0,0.02);
    }
    .nav-inner {
      max-width: 1400px;
      margin: 0 auto;
      padding: 0 24px;
      height: 64px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .brand-group { display: flex; align-items: center; gap: 14px; }
    .brand-icon {
      width: 36px; height: 36px; background: var(--blue); color: #fff;
      border-radius: 9px; display: flex; align-items: center; justify-content: center;
      font-weight: 800; font-size: 18px;
    }
    .brand-title { font-size: 16px; font-weight: 700; color: var(--text); }
    .brand-version { font-size: 11px; background: var(--blue-subtle); color: var(--blue); padding: 2px 8px; border-radius: 12px; font-weight: 600; margin-left: 6px; }

    .nav-tabs { display: flex; gap: 4px; background: #F1F5F9; padding: 4px; border-radius: 10px; }
    .tab-btn {
      border: none; background: transparent; padding: 8px 18px; border-radius: 8px;
      font-size: 13.5px; font-weight: 600; color: var(--subtext); cursor: pointer;
      display: flex; align-items: center; gap: 8px; transition: all 0.15s ease;
    }
    .tab-btn:hover { color: var(--text); }
    .tab-btn.active { background: #FFFFFF; color: var(--blue); box-shadow: 0 1px 4px rgba(0,0,0,0.06); }
    .tab-badge { font-size: 11px; background: var(--blue); color: #fff; padding: 1px 7px; border-radius: 10px; font-weight: 700; }

    .nav-actions { display: flex; align-items: center; gap: 12px; }
    .status-pill {
      display: flex; align-items: center; gap: 6px; font-size: 12px;
      background: var(--green-bg); color: var(--green); font-weight: 600;
      padding: 5px 12px; border-radius: 20px; border: 1px solid rgba(22,163,74,0.2);
    }
    .status-dot { width: 7px; height: 7px; background: var(--green); border-radius: 50%; }
    .shield-btn {
      border: 1px solid var(--border); background: #fff; border-radius: 8px;
      padding: 6px 12px; font-size: 12px; font-weight: 600; color: var(--subtext);
      cursor: pointer; display: flex; align-items: center; gap: 6px;
    }
    .shield-btn:hover { background: #F8FAFC; color: var(--red); border-color: #FECACA; }

    /* Main Container */
    .main-wrap {
      max-width: 1400px;
      width: 100%;
      margin: 0 auto;
      padding: 24px;
      flex: 1;
    }

    /* Views */
    .tab-pane { display: none; }
    .tab-pane.active { display: block; }

    /* Logger View */
    .log-layout {
      display: grid;
      grid-template-columns: 380px 1fr;
      gap: 24px;
    }
    .side-card, .form-card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 14px;
      padding: 24px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.03);
    }
    .card-title { font-size: 16px; font-weight: 700; margin-bottom: 4px; }
    .card-subtitle { font-size: 12.5px; color: var(--subtext); margin-bottom: 20px; }

    .paste-zone {
      border: 2px dashed #93C5FD;
      background: var(--blue-subtle);
      border-radius: 12px;
      padding: 24px 16px;
      text-align: center;
      cursor: pointer;
      margin-bottom: 16px;
      transition: all 0.2s;
    }
    .paste-zone:hover { background: #DBEAFE; }
    .paste-zone.has-image { border-style: solid; border-color: var(--blue); padding: 12px; }
    .paste-zone p.main-text { font-size: 13.5px; font-weight: 600; color: var(--blue); }
    .paste-zone p.sub-text { font-size: 11.5px; color: var(--subtext); margin-top: 4px; }
    .preview-box { margin-top: 10px; display: none; position: relative; }
    .preview-box img { max-height: 160px; max-width: 100%; border-radius: 8px; border: 1px solid var(--border); }
    .remove-img {
      position: absolute; top: -6px; right: -6px; background: var(--red); color: #fff;
      border: none; border-radius: 50%; width: 22px; height: 22px; cursor: pointer;
      font-size: 12px; font-weight: bold; line-height: 22px;
    }

    .form-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 16px;
      margin-bottom: 16px;
    }
    .col-full { grid-column: 1 / -1; }
    label {
      display: block; font-size: 11.5px; font-weight: 700; color: var(--subtext);
      margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.5px;
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
    textarea { resize: vertical; min-height: 85px; }

    button.btn-primary {
      background: var(--blue); color: #fff; border: none; border-radius: 8px;
      padding: 12px 28px; font-size: 14px; font-weight: 700; cursor: pointer;
      display: inline-flex; align-items: center; gap: 8px; transition: background 0.15s;
    }
    button.btn-primary:hover { background: var(--blue-hover); }
    button.btn-primary:disabled { background: #94A3B8; cursor: not-allowed; }

    /* Mistake Reviewer / Explorer View */
    .filter-bar {
      background: #FFFFFF;
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 16px;
      margin-bottom: 20px;
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
    }
    .search-box {
      flex: 1;
      min-width: 280px;
      position: relative;
    }
    .search-box input {
      padding-left: 36px;
      height: 40px;
      font-size: 13.5px;
    }
    .search-icon {
      position: absolute; left: 12px; top: 12px; color: var(--subtext); font-size: 16px;
    }
    .filter-group { display: flex; gap: 8px; align-items: center; }
    .filter-select { height: 40px; padding: 0 12px; min-width: 180px; }

    .stat-cards {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 16px;
      margin-bottom: 20px;
    }
    .stat-card {
      background: #FFFFFF;
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 14px 18px;
    }
    .stat-label { font-size: 11.5px; color: var(--subtext); font-weight: 600; text-transform: uppercase; }
    .stat-val { font-size: 22px; font-weight: 800; color: var(--text); margin-top: 2px; }

    .mistake-feed {
      display: flex;
      flex-direction: column;
      gap: 16px;
    }
    .feed-card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 20px;
      transition: box-shadow 0.15s;
    }
    .feed-card:hover {
      box-shadow: 0 4px 14px rgba(0,0,0,0.05);
      border-color: var(--border-dark);
    }
    .feed-card.resolved { opacity: 0.7; background: #F8FAFC; }
    .card-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 12px;
      gap: 12px;
    }
    .badge-wrap { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
    .subj-pill {
      font-size: 11.5px; font-weight: 700; padding: 3px 10px; border-radius: 12px;
      background: var(--blue-subtle); color: var(--blue);
    }
    .sev-pill {
      font-size: 11px; font-weight: 800; padding: 3px 9px; border-radius: 12px;
      text-transform: uppercase;
    }
    .sev-HIGH { background: var(--red-bg); color: var(--red); }
    .sev-MEDIUM { background: var(--amber-bg); color: var(--amber); }
    .sev-LOW { background: var(--blue-subtle); color: var(--blue); }
    .quiz-pill { font-size: 11px; background: #F1F5F9; color: var(--subtext); padding: 3px 8px; border-radius: 6px; }
    .date-str { font-size: 12px; color: var(--subtext); }

    .q-title { font-size: 16px; font-weight: 700; color: var(--text); margin-bottom: 10px; }
    .feed-card.resolved .q-title { text-decoration: line-through; color: var(--subtext); }
    
    .ans-box {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-bottom: 14px;
      background: #F8FAFC;
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 12px;
    }
    .wrong-ans { color: var(--red); font-size: 13px; font-weight: 600; flex: 1; min-width: 220px; }
    .correct-ans { color: var(--green); font-size: 13px; font-weight: 600; flex: 1; min-width: 220px; }

    .markdown-block {
      background: #FFFFFF;
      border-left: 3px solid var(--blue);
      padding: 10px 14px;
      border-radius: 0 8px 8px 0;
      margin-bottom: 10px;
      font-size: 13.5px;
      line-height: 1.6;
    }
    .markdown-block.question {
      border-left-color: #64748B;
      background: #F8FAFC;
    }
    .markdown-block.reason {
      border-left-color: var(--blue);
      background: #FFFFFF;
    }
    .markdown-block.takeaway {
      border-left-color: var(--amber);
      background: #FFFBEB;
    }
    .block-tag { font-size: 11px; font-weight: 800; text-transform: uppercase; margin-bottom: 4px; display: block; }
    .block-tag.t-question { color: #475569; }
    .block-tag.t-reason { color: var(--blue); }
    .block-tag.t-takeaway { color: var(--amber); }

    .resolved-pill {
      font-size: 11px; font-weight: 700; padding: 3px 8px; border-radius: 6px;
      background: var(--green-bg); color: var(--green); display: inline-flex; align-items: center; gap: 4px;
    }
    .act-btn.copy-btn:hover { color: var(--blue); border-color: rgba(26,115,232,0.3); }

    .markdown-block a {
      color: var(--blue);
      text-decoration: underline;
      word-break: break-all;
    }
    .markdown-block code {
      background: var(--code-bg);
      color: #9333EA;
      padding: 2px 5px;
      border-radius: 4px;
      font-size: 12px;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    }

    .screenshot-thumb {
      margin-top: 10px;
      border-radius: 8px;
      max-height: 180px;
      max-width: 100%;
      cursor: pointer;
      border: 1px solid var(--border);
    }

    .card-footer {
      display: flex;
      justify-content: flex-end;
      gap: 10px;
      margin-top: 14px;
      padding-top: 12px;
      border-top: 1px solid var(--border);
    }
    .act-btn {
      background: transparent; border: 1px solid var(--border); border-radius: 6px;
      padding: 6px 12px; font-size: 12px; font-weight: 600; cursor: pointer;
      display: flex; align-items: center; gap: 5px; color: var(--subtext);
    }
    .act-btn:hover { background: #F8FAFC; color: var(--text); }
    .act-btn.resolve-btn:hover { color: var(--green); border-color: rgba(22,163,74,0.3); }
    .act-btn.delete-btn:hover { color: var(--red); border-color: rgba(220,38,38,0.3); }

    /* Security Shield PIN Modal */
    .shield-modal-bg {
      position: fixed; inset: 0; background: rgba(15,23,42,0.85); backdrop-filter: blur(8px);
      z-index: 1000; display: flex; align-items: center; justify-content: center; padding: 20px;
    }
    .shield-card {
      background: #FFFFFF; border-radius: 20px; max-width: 440px; width: 100%;
      padding: 32px 28px; text-align: center; box-shadow: 0 20px 40px rgba(0,0,0,0.25);
    }
    .shield-icon {
      width: 56px; height: 56px; background: #DCFCE7; color: var(--green);
      border-radius: 14px; display: inline-flex; align-items: center; justify-content: center;
      font-size: 28px; margin-bottom: 16px;
    }
    .shield-title { font-size: 20px; font-weight: 800; color: var(--text); margin-bottom: 6px; }
    .shield-desc { font-size: 13.5px; color: var(--subtext); margin-bottom: 24px; line-height: 1.45; }
    .pin-grid {
      display: flex; justify-content: center; gap: 10px; margin-bottom: 24px;
    }
    .pin-box {
      width: 48px; height: 56px; border: 2px solid var(--border); border-radius: 10px;
      font-size: 24px; font-weight: 800; text-align: center; font-family: monospace;
      outline: none; transition: border-color 0.15s; background: #F8FAFC;
    }
    .pin-box:focus { border-color: var(--blue); background: #FFFFFF; box-shadow: 0 0 0 3px rgba(26,115,232,0.15); }
    .shield-submit {
      width: 100%; height: 46px; font-size: 15px; font-weight: 700;
    }
    .pin-error { color: var(--red); font-size: 12.5px; font-weight: 600; margin-top: 12px; display: none; }

    /* Toast Notification */
    .toast {
      position: fixed; bottom: 24px; right: 24px; background: #0F172A; color: #fff;
      padding: 12px 22px; border-radius: 10px; font-size: 13.5px; font-weight: 600;
      box-shadow: 0 6px 20px rgba(0,0,0,0.2); display: none; z-index: 1100;
    }

    @media (max-width: 900px) {
      .log-layout { grid-template-columns: 1fr; }
      .stat-cards { grid-template-columns: 1fr 1fr; }
      .ans-box { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>

  <!-- Top Navigation Bar -->
  <header class="app-nav">
    <div class="nav-inner">
      <div class="brand-group">
        <div class="brand-icon"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg></div>
        <div>
          <span class="brand-title">NYRO Tasks Copilot</span>
          <span class="brand-version">v$version</span>
        </div>
      </div>

      <nav class="nav-tabs">
        <button class="tab-btn active" id="tabBtnLog" onclick="switchTab('log')">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 6px;"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg><span>Log Mistake</span>
        </button>
        <button class="tab-btn" id="tabBtnReview" onclick="switchTab('review')">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 6px;"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/></svg><span>Mistake Archive</span>
          <span class="tab-badge" id="navCount">0</span>
        </button>
      </nav>

      <div class="nav-actions">
        <div class="status-pill">
          <span class="status-dot"></span>
          <span>Wi-Fi Shield Active</span>
        </div>
        <button class="shield-btn" onclick="logoutSession()" title="Lock dashboard & disconnect">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 4px;"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg><span>Lock</span>
        </button>
      </div>
    </div>
  </header>

  <!-- Main Content Wrap -->
  <main class="main-wrap">

    <!-- TAB 1: LOG MISTAKE VIEW -->
    <section id="paneLog" class="tab-pane active">
      <div class="log-layout">
        
        <!-- Left: Paste / Screenshot Column -->
        <div class="side-card">
          <h2 class="card-title">Question Screenshot</h2>
          <p class="card-subtitle">Paste image from test series or lecture notes</p>

          <div class="paste-zone" id="pasteZone">
            <p class="main-text"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 6px;"><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><rect x="8" y="2" width="8" height="4" rx="1" ry="1"/></svg>Click or Press Ctrl+V</p>
            <p class="sub-text">Paste clipboard image directly</p>
            <input type="file" id="fileInput" accept="image/*" style="display: none;">
            <div class="preview-box" id="previewBox">
              <img id="previewImg" src="" alt="Screenshot">
              <button type="button" class="remove-img" id="removeImgBtn" title="Remove image">&times;</button>
            </div>
          </div>

          <div style="font-size: 12px; color: var(--subtext); line-height: 1.5; padding: 10px; background: #F8FAFC; border-radius: 8px;">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#f59e0b" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 4px;"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/></svg><strong>Fast Logging Tip:</strong> When taking quizzes on MadeEasy, GateAcademy, or GateOverflow on laptop, use <code>Win + Shift + S</code> to snip the question, then switch here and hit <code>Ctrl + V</code>!
          </div>
        </div>

        <!-- Right: Mistake Form -->
        <div class="form-card">
          <h2 class="card-title">Log Blunder Details</h2>
          <p class="card-subtitle">Recorded mistakes sync immediately to your phone and cloud notes</p>

          <form id="mistakeForm">
            <div class="form-grid">
              <div>
                <label>Subject</label>
                <input type="text" id="subjectInput" placeholder="e.g. Engineering Mathematics" list="subjectsList" required>
                <datalist id="subjectsList"></datalist>
              </div>
              <div>
                <label>Severity / Trap Level</label>
                <select id="severitySelect">
                  <option value="HIGH">High (Concept Trap / Fatal Blunder)</option>
                  <option value="MEDIUM" selected>Medium (Calculation Slip)</option>
                  <option value="LOW">Low (Silly / Reading Oversight)</option>
                </select>
              </div>

              <div class="col-full">
                <label>Topic / Core Concept</label>
                <input type="text" id="topicInput" placeholder="e.g. Linear Independence, Matrix Limits" required>
              </div>

              <div class="col-full">
                <label>Question / Problem Statement (or Source URL)</label>
                <textarea id="questionInput" placeholder="Paste question text, problem statement, or GateOverflow / quiz URL..."></textarea>
              </div>

              <div class="col-full">
                <label>Quiz / Test Series Title (Optional)</label>
                <input type="text" id="quizInput" placeholder="e.g. MadeEasy Topic Test 02, GO Weekly Quiz 1">
              </div>

              <div>
                <label>My Wrong Answer / Initial Attempt</label>
                <input type="text" id="wrongInput" placeholder="e.g. All eigenvalues are real">
              </div>
              <div>
                <label>Correct Answer</label>
                <input type="text" id="correctInput" placeholder="e.g. Purely imaginary or zero">
              </div>

              <div class="col-full">
                <label>Mistake Reason (Where did I slip?)</label>
                <textarea id="reasonInput" placeholder="Confused symmetric (A^T = A, real eigenvalues) with skew-symmetric (A^T = -A). Remember URLs or links like https://gateoverflow.in/1234 are clickable!"></textarea>
              </div>

              <div class="col-full">
                <label>Key Takeaway / Concept to Remember</label>
                <textarea id="takeawayInput" placeholder="For skew-symmetric: lambda = -lambda*. Hence Re(lambda) = 0! Eigenvalues are 0 or purely imaginary." required></textarea>
              </div>
            </div>

            <div style="display: flex; justify-content: flex-end; gap: 12px;">
              <button type="submit" class="btn-primary" id="submitBtn">
                <span>Save Mistake to Phone</span> <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-left: 6px;"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></svg>
              </button>
            </div>
          </form>
        </div>

      </div>
    </section>

    <!-- TAB 2: REVIEW & STUDY ARCHIVE VIEW -->
    <section id="paneReview" class="tab-pane">
      
      <!-- Stats Row -->
      <div class="stat-cards">
        <div class="stat-card">
          <div class="stat-label">Total Recorded</div>
          <div class="stat-val" id="statTotal">0</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">High Priority Traps</div>
          <div class="stat-val" style="color: var(--red);" id="statHigh">0</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Pending Review</div>
          <div class="stat-val" style="color: var(--amber);" id="statPending">0</div>
        </div>
        <div class="stat-card">
          <div class="stat-label">Resolved / Mastered</div>
          <div class="stat-val" style="color: var(--green);" id="statResolved">0</div>
        </div>
      </div>

      <!-- Filter & Search Toolbar -->
      <div class="filter-bar">
        <div class="search-box">
          <span class="search-icon"><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg></span>
          <input type="text" id="searchInput" placeholder="Search by question, formula, concept, or takeaway..." oninput="onSearchChanged()">
        </div>

        <div class="filter-group">
          <select id="filterSubject" class="filter-select" onchange="applyFilters()">
            <option value="">All Subjects</option>
          </select>

          <select id="filterSeverity" class="filter-select" onchange="applyFilters()">
            <option value="">All Severities</option>
            <option value="HIGH">High Traps</option>
            <option value="MEDIUM">Medium Slips</option>
            <option value="LOW">Low / Silly</option>
          </select>

          <select id="filterStatus" class="filter-select" onchange="applyFilters()">
            <option value="" selected>All Statuses</option>
            <option value="PENDING">Unresolved Only</option>
            <option value="RESOLVED">Resolved Only</option>
          </select>
        </div>
      </div>

      <!-- Live Mistakes Feed -->
      <div class="mistake-feed" id="mistakeFeed">
        <div style="text-align: center; padding: 48px; color: var(--subtext);">
          Loading mistakes from phone...
        </div>
      </div>
    </section>

  </main>

  <!-- Wi-Fi Shield 6-Digit Authenticator Modal -->
  <div class="shield-modal-bg" id="shieldModal" style="display: none;">
    <div class="shield-card">
      <div class="shield-icon"><svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="var(--blue)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg></div>
      <h2 class="shield-title">Public Wi-Fi Shield</h2>
      <p class="shield-desc">
        Enter the <strong>6-digit Pairing Code</strong> shown in NYRO Tasks app on your mobile phone to unlock this laptop dashboard.
      </p>

      <div class="pin-grid">
        <input type="password" maxlength="1" class="pin-box" id="pin1" inputmode="numeric" autofocus>
        <input type="password" maxlength="1" class="pin-box" id="pin2" inputmode="numeric">
        <input type="password" maxlength="1" class="pin-box" id="pin3" inputmode="numeric">
        <input type="password" maxlength="1" class="pin-box" id="pin4" inputmode="numeric">
        <input type="password" maxlength="1" class="pin-box" id="pin5" inputmode="numeric">
        <input type="password" maxlength="1" class="pin-box" id="pin6" inputmode="numeric">
      </div>

      <button class="btn-primary shield-submit" id="shieldSubmitBtn" onclick="submitPin()">
        Unlock Dashboard
      </button>

      <div class="pin-error" id="pinError">Invalid code. Please check your phone.</div>
    </div>
  </div>

  <!-- Toast Notification -->
  <div class="toast" id="toast"></div>

  <script>
    // State
    let authToken = localStorage.getItem('nyro_desktop_token');
    let allMistakes = [];
    let distinctSubjects = [];
    let pastedImageBase64 = null;

    // Helper: Toast
    function showToast(msg) {
      const t = document.getElementById('toast');
      t.innerText = msg;
      t.style.display = 'block';
      setTimeout(() => { t.style.display = 'none'; }, 3200);
    }

    // Helper: HTML escaper for safe attribute/tag injection
    function escapeHtml(text) {
      if (!text) return '';
      return String(text)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
    }

    // Helper: Markdown parser with clickable URLs, markdown links, images, code, and bold/italic
    function renderMarkdown(rawText) {
      if (!rawText) return '';
      let escaped = String(rawText)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');

      const tokens = [];

      // 1. Markdown Images: ![alt](url)
      escaped = escaped.replace(/!\\[(.*?)\\]\\((https?:\\/\\/[^\\s)]+|\\/api\\/images\\/[^\\s)]+)\\)/g, (match, alt, src) => {
        const idx = tokens.length;
        tokens.push(`<img src="\${src}" class="screenshot-thumb" alt="\${alt || 'Screenshot'}" onclick="window.open('\${src}', '_blank')">`);
        return `___TOKEN_\${idx}___`;
      });

      // 2. Markdown Links: [text](url)
      escaped = escaped.replace(/\\[(.*?)\\]\\((https?:\\/\\/[^\\s)]+)\\)/g, (match, text, url) => {
        const idx = tokens.length;
        tokens.push(`<a href="\${url}" target="_blank" rel="noopener noreferrer">\${text} ↗</a>`);
        return `___TOKEN_\${idx}___`;
      });

      // 3. Inline Code: `code`
      escaped = escaped.replace(/`([^`]+)`/g, (match, code) => {
        const idx = tokens.length;
        tokens.push(`<code>\${code}</code>`);
        return `___TOKEN_\${idx}___`;
      });

      // 4. Auto-link bare URLs (not inside markdown links)
      escaped = escaped.replace(/(https?:\\/\\/[^\\s<]+)/g, (match, url) => {
        let trailing = '';
        while (url.length > 0 && /[.,;)]\$/.test(url)) {
          trailing = url.slice(-1) + trailing;
          url = url.slice(0, -1);
        }
        return `<a href="\${url}" target="_blank" rel="noopener noreferrer">\${url} ↗</a>\${trailing}`;
      });

      // 5. Bold & Italic
      escaped = escaped.replace(/\\*\\*(.*?)\\*\\*/g, '<strong>\$1</strong>');
      escaped = escaped.replace(/(^|[\\s(])\\*([^\\*\\s][^\\*]*?[^\\*\\s]|\\S)\\*(?=[\\s).,!?]|\$)/g, '\$1<em>\$2</em>');

      // 6. Convert linebreaks
      escaped = escaped.replace(/\\r?\\n/g, '<br>');

      // 7. Restore tokens
      escaped = escaped.replace(/___TOKEN_(\\d+)___/g, (match, idx) => {
        return tokens[Number(idx)];
      });

      return escaped;
    }

    // Tab Switcher
    function switchTab(tabId) {
      document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
      document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));

      if (tabId === 'log') {
        document.getElementById('paneLog').classList.add('active');
        document.getElementById('tabBtnLog').classList.add('active');
      } else {
        document.getElementById('paneReview').classList.add('active');
        document.getElementById('tabBtnReview').classList.add('active');
        loadMistakes();
      }
    }

    // Auth & Wi-Fi Shield
    let heartbeatTimer = null;

    function startHeartbeat() {
      stopHeartbeat();
      heartbeatTimer = setInterval(() => {
        if (!authToken) {
          stopHeartbeat();
          showShieldModal();
          return;
        }
        fetch('/api/auth/status', {
          headers: { 'Authorization': 'Bearer ' + authToken }
        })
        .then(r => {
          if (r.status === 401) {
            logoutSession();
            return null;
          }
          return r.json();
        })
        .then(d => {
          if (d && !d.authenticated) {
            logoutSession();
          }
        })
        .catch(() => {});
      }, 3000);
    }

    function stopHeartbeat() {
      if (heartbeatTimer) {
        clearInterval(heartbeatTimer);
        heartbeatTimer = null;
      }
    }

    function checkAuth() {
      if (!authToken) {
        showShieldModal();
        return;
      }
      fetch('/api/auth/status', {
        headers: { 'Authorization': 'Bearer ' + authToken }
      })
      .then(r => {
        if (r.status === 401) {
          logoutSession();
          return null;
        }
        return r.json();
      })
      .then(d => {
        if (!d || !d.authenticated) {
          logoutSession();
        } else {
          hideShieldModal();
          startHeartbeat();
          initDashboard();
        }
      })
      .catch(() => showShieldModal());
    }

    function showShieldModal() {
      document.getElementById('shieldModal').style.display = 'flex';
      setupPinInputs();
    }

    function hideShieldModal() {
      document.getElementById('shieldModal').style.display = 'none';
    }

    function logoutSession() {
      const tokenToRevoke = authToken;
      authToken = null;
      stopHeartbeat();
      localStorage.removeItem('nyro_desktop_token');
      showShieldModal();
      showToast('Dashboard locked. Re-enter phone PIN to unlock.');
      if (tokenToRevoke) {
        fetch('/api/auth/logout', {
          method: 'POST',
          headers: { 'Authorization': 'Bearer ' + tokenToRevoke }
        }).catch(() => {});
      }
    }

    function setupPinInputs() {
      const inputs = [1,2,3,4,5,6].map(i => document.getElementById('pin' + i));
      inputs.forEach((inp, idx) => {
        inp.value = '';
        inp.oninput = (e) => {
          if (inp.value.length === 1 && idx < 5) {
            inputs[idx + 1].focus();
          }
          if (idx === 5 && inp.value.length === 1) {
            submitPin();
          }
        };
        inp.onkeydown = (e) => {
          if (e.key === 'Backspace' && !inp.value && idx > 0) {
            inputs[idx - 1].focus();
          }
        };
        inp.onpaste = (e) => {
          e.preventDefault();
          const paste = (e.clipboardData || window.clipboardData).getData('text').replace(/\\D/g, '');
          if (paste.length >= 6) {
            for (let i = 0; i < 6; i++) {
              inputs[i].value = paste[i];
            }
            submitPin();
          }
        };
      });
      setTimeout(() => inputs[0].focus(), 150);
    }

    function submitPin() {
      const pin = [1,2,3,4,5,6].map(i => document.getElementById('pin' + i).value).join('');
      if (pin.length < 6) return;

      const errEl = document.getElementById('pinError');
      errEl.style.display = 'none';

      fetch('/api/auth/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pin: pin })
      })
      .then(r => r.json())
      .then(res => {
        if (res.success && res.token) {
          authToken = res.token;
          localStorage.setItem('nyro_desktop_token', authToken);
          hideShieldModal();
          startHeartbeat();
          showToast('Shield Authenticated! Welcome to NYRO Desktop Studio.');
          initDashboard();
        } else {
          errEl.innerText = res.error || 'Invalid 6-digit code. Check your phone!';
          errEl.style.display = 'block';
        }
      })
      .catch(err => {
        errEl.innerText = 'Authentication error. Please retry.';
        errEl.style.display = 'block';
      });
    }

    // Dashboard Initialization
    function initDashboard() {
      loadSubjects();
      loadMistakes();
    }

    function loadSubjects() {
      fetch('/api/subjects', {
        headers: { 'Authorization': 'Bearer ' + authToken }
      })
      .then(r => {
        if (r.status === 401) {
          logoutSession();
          return null;
        }
        return r.json();
      })
      .then(data => {
        if (!data) return;
        distinctSubjects = data.subjects || [];
        const dl = document.getElementById('subjectsList');
        const sel = document.getElementById('filterSubject');
        dl.innerHTML = distinctSubjects.map(s => `<option value="\${s}">`).join('');
        sel.innerHTML = '<option value="">All Subjects</option>' + distinctSubjects.map(s => `<option value="\${s}">\${s}</option>`).join('');
      })
      .catch(() => {});
    }

    function loadMistakes() {
      fetch('/api/mistakes', {
        headers: { 'Authorization': 'Bearer ' + authToken }
      })
      .then(r => {
        if (r.status === 401) {
          logoutSession();
          return null;
        }
        return r.json();
      })
      .then(data => {
        if (!data) return;
        allMistakes = data.mistakes || [];
        updateStats();
        applyFilters();
      })
      .catch(e => {
        document.getElementById('mistakeFeed').innerHTML = '<div style="text-align:center; padding: 30px; color: var(--red);">Error loading mistake records from phone.</div>';
      });
    }

    function updateStats() {
      const total = allMistakes.length;
      const high = allMistakes.filter(m => (m.severity || '').trim().toUpperCase() === 'HIGH').length;
      const resolved = allMistakes.filter(m => {
        const st = (m.status || '').trim().toUpperCase();
        return st === 'RESOLVED' || st === 'COMPLETED' || st === 'DONE';
      }).length;
      const pending = total - resolved;

      document.getElementById('statTotal').innerText = total;
      document.getElementById('statHigh').innerText = high;
      document.getElementById('statPending').innerText = pending;
      document.getElementById('statResolved').innerText = resolved;
      document.getElementById('navCount').innerText = pending;
    }

    function onSearchChanged() {
      applyFilters();
    }

    function filterByQuiz(quizTitle) {
      document.getElementById('searchInput').value = quizTitle;
      applyFilters();
      showToast('Filtered traps for quiz: ' + quizTitle);
    }

    function applyFilters() {
      const q = (document.getElementById('searchInput').value || '').toLowerCase().trim();
      const s = (document.getElementById('filterSubject').value || '').trim().toLowerCase();
      const sev = (document.getElementById('filterSeverity').value || '').trim().toUpperCase();
      const status = (document.getElementById('filterStatus').value || '').trim().toUpperCase();

      const filtered = allMistakes.filter(m => {
        if (s && (m.subject || '').trim().toLowerCase() !== s) return false;
        if (sev && (m.severity || '').trim().toUpperCase() !== sev) return false;
        if (status) {
          const mStatus = (m.status || '').trim().toUpperCase();
          const isResolved = (mStatus === 'RESOLVED' || mStatus === 'COMPLETED' || mStatus === 'DONE');
          if (status === 'RESOLVED' && !isResolved) return false;
          if (status === 'PENDING' && isResolved) return false;
        }
        if (q) {
          const matchQ = (m.topic || '').toLowerCase().includes(q) ||
                         (m.question_text || '').toLowerCase().includes(q) ||
                         (m.wrong_answer || '').toLowerCase().includes(q) ||
                         (m.correct_answer || '').toLowerCase().includes(q) ||
                         (m.mistake_reason || '').toLowerCase().includes(q) ||
                         (m.key_takeaway || '').toLowerCase().includes(q) ||
                         (m.subject || '').toLowerCase().includes(q) ||
                         (m.quiz_title || '').toLowerCase().includes(q);
          if (!matchQ) return false;
        }
        return true;
      });

      renderMistakeFeed(filtered);
    }

    function renderMistakeFeed(items) {
      const feed = document.getElementById('mistakeFeed');
      if (items.length === 0) {
        feed.innerHTML = '<div style="text-align: center; padding: 48px; color: var(--subtext); background:#fff; border-radius:12px; border:1px solid var(--border);">No matching mistakes found.</div>';
        return;
      }

      feed.innerHTML = items.map(m => {
        const isResolved = (m.status || '').toUpperCase() === 'RESOLVED';
        const sev = (m.severity || 'MEDIUM').toUpperCase();
        const rawDate = (m.created_at || '').replace(' ', 'T');
        const d = rawDate ? new Date(rawDate) : null;
        const dateStr = (d && !isNaN(d.getTime())) ? d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }) : '';

        // Extract image url if stored in takeaway
        const safeImgRegex = /^\/api\/images\/[a-zA-Z0-9_\-]+\.(jpg|jpeg|png|webp)\$/i;
        let imgHtml = '';
        let cleanTakeaway = m.key_takeaway || '';
        const imgMatch = cleanTakeaway.match(/!\[Screenshot\]\((.*?)\)/);
        if (imgMatch) {
          const src = imgMatch[1];
          if (safeImgRegex.test(src)) {
            imgHtml = `<img src="\${src}" class="screenshot-thumb" alt="Screenshot" onclick="window.open('\${src}', '_blank')">`;
          }
          cleanTakeaway = cleanTakeaway.replace(/!\[Screenshot\]\(.*?\)/g, '').trim();
        }

        // Extract image url if stored in question_text
        let cleanQText = m.question_text || '';
        const qImgMatch = cleanQText.match(/!\[Screenshot\]\((.*?)\)/);
        let qImgHtml = '';
        if (qImgMatch) {
          const src = qImgMatch[1];
          if (safeImgRegex.test(src)) {
            qImgHtml = `<img src="\${src}" class="screenshot-thumb" alt="Question Screenshot" onclick="window.open('\${src}', '_blank')">`;
          }
          cleanQText = cleanQText.replace(/!\[Screenshot\]\(.*?\)/g, '').trim();
        }

        return `
          <div class="feed-card \${isResolved ? 'resolved' : ''}">
            <div class="card-head">
              <div class="badge-wrap">
                <span class="subj-pill">\${escapeHtml(m.subject || 'General')}</span>
                <span class="sev-pill sev-\${sev}">\${sev}</span>
                \${m.quiz_title ? `<span class="quiz-pill" onclick="filterByQuiz('\${escapeHtml(m.quiz_title)}')" style="cursor:pointer;" title="Click to view all traps for this quiz"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 4px;"><circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/></svg>\${escapeHtml(m.quiz_title)}</span>` : ''}
                \${isResolved ? `<span class="resolved-pill"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 3px;"><polyline points="20 6 9 17 4 12"/></svg>Resolved</span>` : ''}
              </div>
              \${dateStr ? `<span class="date-str">\${escapeHtml(dateStr)}</span>` : ''}
            </div>

            <div class="q-title">\${escapeHtml(m.topic || 'Mistake Record')}</div>

            \${(cleanQText || qImgHtml) ? `
              <div class="markdown-block question">
                <span class="block-tag t-question">Question / Source</span>
                \${cleanQText ? renderMarkdown(cleanQText) : ''}
                \${qImgHtml}
              </div>
            ` : ''}

            \${(m.wrong_answer || m.correct_answer) ? `
              <div class="ans-box">
                \${m.wrong_answer ? `<div class="wrong-ans"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 4px;"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>Wrong Attempt: \${escapeHtml(m.wrong_answer)}</div>` : ''}
                \${m.correct_answer ? `<div class="correct-ans"><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 4px;"><polyline points="20 6 9 17 4 12"/></svg>Correct Answer: \${escapeHtml(m.correct_answer)}</div>` : ''}
              </div>
            ` : ''}

            \${m.mistake_reason ? `
              <div class="markdown-block reason">
                <span class="block-tag t-reason">Trap / Why I Slipped</span>
                \${renderMarkdown(m.mistake_reason)}
              </div>
            ` : ''}

            \${cleanTakeaway ? `
              <div class="markdown-block takeaway">
                <span class="block-tag t-takeaway">Core Takeaway to Remember</span>
                \${renderMarkdown(cleanTakeaway)}
              </div>
            ` : ''}

            \${imgHtml}

            <div class="card-footer">
              <button class="act-btn copy-btn" onclick="copyMistake(\${m.id})" title="Copy complete note">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 4px;"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>Copy Note
              </button>
              <button class="act-btn resolve-btn" onclick="toggleResolve(\${m.id}, \${!isResolved})">
                \${isResolved ? '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 4px;"><polyline points="9 14 4 9 9 4"/><path d="M20 20v-7a4 4 0 0 0-4-4H4"/></svg>Re-open' : '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 4px;"><polyline points="20 6 9 17 4 12"/></svg>Mark Resolved'}
              </button>
              <button class="act-btn delete-btn" onclick="deleteMistake(\${m.id})">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 4px;"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>Delete
              </button>
            </div>
          </div>
        `;
      }).join('');
    }

    function copyMistake(id) {
      const m = allMistakes.find(x => x.id == id);
      if (!m) return;
      let text = `\${m.topic || 'Mistake Record'} (\${m.subject || 'General'}`;
      if (m.quiz_title) text += ` • \${m.quiz_title}`;
      text += `)\n\n`;
      if (m.question_text) text += `Question / Source:\n\${m.question_text}\n\n`;
      if (m.wrong_answer) text += `Wrong Attempt: \${m.wrong_answer}\n`;
      if (m.correct_answer) text += `Correct Answer: \${m.correct_answer}\n`;
      if (m.wrong_answer || m.correct_answer) text += `\n`;
      if (m.mistake_reason) text += `Trap / Why I Slipped:\n\${m.mistake_reason}\n\n`;
      if (m.key_takeaway) text += `Core Takeaway:\n\${m.key_takeaway}\n`;
      
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text.trim()).then(() => {
          showToast('Note copied to clipboard!');
        }).catch(() => {
          fallbackCopyText(text.trim());
        });
      } else {
        fallbackCopyText(text.trim());
      }
    }

    function fallbackCopyText(text) {
      const ta = document.createElement('textarea');
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      showToast('Note copied to clipboard!');
    }

    function toggleResolve(id, resolveState) {
      fetch(`/api/mistakes/\${id}/resolve`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ' + authToken
        },
        body: JSON.stringify({ resolved: resolveState })
      })
      .then(r => {
        if (r.status === 401) {
          logoutSession();
          return null;
        }
        return r.json();
      })
      .then(d => {
        if (!d) return;
        if (d.success) {
          const item = allMistakes.find(m => m.id === id);
          if (item) item.status = resolveState ? 'RESOLVED' : 'UNRESOLVED';
          updateStats();
          applyFilters();
          showToast(resolveState ? 'Marked mistake as resolved!' : 'Re-opened mistake for review.');
        }
      });
    }

    function deleteMistake(id) {
      if (!confirm('Are you sure you want to delete this mistake record from your phone?')) return;
      fetch(`/api/mistakes/\${id}`, {
        method: 'DELETE',
        headers: { 'Authorization': 'Bearer ' + authToken }
      })
      .then(r => {
        if (r.status === 401) {
          logoutSession();
          return null;
        }
        return r.json();
      })
      .then(d => {
        if (!d) return;
        if (d.success) {
          allMistakes = allMistakes.filter(m => m.id !== id);
          updateStats();
          applyFilters();
          showToast('Mistake record deleted.');
        }
      });
    }

    // Image Paste & File Dropzone
    const pasteZone = document.getElementById('pasteZone');
    const fileInput = document.getElementById('fileInput');
    const previewBox = document.getElementById('previewBox');
    const previewImg = document.getElementById('previewImg');
    const removeImgBtn = document.getElementById('removeImgBtn');

    pasteZone.addEventListener('click', () => fileInput.click());

    fileInput.addEventListener('change', (e) => {
      const file = e.target.files[0];
      if (file) handleImageFile(file);
    });

    window.addEventListener('paste', (e) => {
      const items = (e.clipboardData || e.originalEvent.clipboardData).items;
      for (let item of items) {
        if (item.type.indexOf('image') !== -1) {
          const file = item.getAsFile();
          handleImageFile(file);
          break;
        }
      }
    });

    function handleImageFile(file) {
      const reader = new FileReader();
      reader.onload = (e) => {
        pastedImageBase64 = e.target.result;
        previewImg.src = pastedImageBase64;
        previewBox.style.display = 'block';
        pasteZone.classList.add('has-image');
        showToast('Screenshot attached from clipboard!');
      };
      reader.readAsDataURL(file);
    }

    removeImgBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      pastedImageBase64 = null;
      previewImg.src = '';
      previewBox.style.display = 'none';
      pasteZone.classList.remove('has-image');
      fileInput.value = '';
    });

    // Form Submission
    document.getElementById('mistakeForm').addEventListener('submit', async (e) => {
      e.preventDefault();
      const submitBtn = document.getElementById('submitBtn');
      submitBtn.disabled = true;
      submitBtn.innerText = 'Logging to Phone...';

      const payload = {
        subject: document.getElementById('subjectInput').value.trim(),
        severity: document.getElementById('severitySelect').value,
        topic: document.getElementById('topicInput').value.trim(),
        question_text: document.getElementById('questionInput').value.trim(),
        quiz_title: document.getElementById('quizInput').value.trim(),
        correct_answer: document.getElementById('correctInput').value.trim(),
        wrong_answer: document.getElementById('wrongInput').value.trim(),
        mistake_reason: document.getElementById('reasonInput').value.trim(),
        key_takeaway: document.getElementById('takeawayInput').value.trim(),
        image_base64: pastedImageBase64,
      };

      try {
        const res = await fetch('/api/mistakes', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + authToken,
          },
          body: JSON.stringify(payload),
        });

        if (res.status === 401) {
          logoutSession();
          return;
        }

        const data = await res.json();
        if (res.ok && data.success) {
          showToast('Mistake logged successfully to phone!');
          // Clear inputs
          document.getElementById('topicInput').value = '';
          document.getElementById('questionInput').value = '';
          document.getElementById('correctInput').value = '';
          document.getElementById('wrongInput').value = '';
          document.getElementById('reasonInput').value = '';
          document.getElementById('takeawayInput').value = '';
          removeImgBtn.click();

          // Refresh mistake feed in background
          loadMistakes();
        } else {
          showToast('Error: ' + (data.error || 'Failed to log'));
        }
      } catch (err) {
        showToast('Network error logging blunder to phone');
      } finally {
        submitBtn.disabled = false;
        submitBtn.innerHTML = '<span>Save Mistake to Phone</span> <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-left: 6px;"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></svg>';
      }
    });

    // Check Auth on page load
    checkAuth();
  </script>
</body>
</html>
''';

    request.response.headers.contentType = ContentType.html;
    request.response.write(html);
    request.response.close();
  }
}
