import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/services/app_update_service.dart';
import 'desktop/desktop_auth_handler.dart';
import 'desktop/desktop_notes_handler.dart';
import 'desktop/desktop_mistakes_handler.dart';
import 'desktop/desktop_web_template.dart';

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

    // 10. Google Keep Notes API (GET, POST)
    if (request.method == 'GET' && path == '/api/notes') {
      final notesHandler = DesktopNotesHandler(authHandler: DesktopAuthHandler());
      await notesHandler.handleGetNotes(request);
      return;
    }
    if (request.method == 'POST' && path == '/api/notes') {
      final notesHandler = DesktopNotesHandler(authHandler: DesktopAuthHandler());
      await notesHandler.handleCreateNote(request);
      return;
    }

    // 11. Google Keep Notes API (PATCH, PUT, DELETE)
    if ((request.method == 'PATCH' || request.method == 'PUT') && path.startsWith('/api/notes/')) {
      final noteId = path.substring('/api/notes/'.length).split('/').first;
      final notesHandler = DesktopNotesHandler(authHandler: DesktopAuthHandler());
      await notesHandler.handleUpdateNote(request, noteId);
      return;
    }
    if (request.method == 'DELETE' && path.startsWith('/api/notes/')) {
      final noteId = path.substring('/api/notes/'.length).split('/').first;
      final notesHandler = DesktopNotesHandler(authHandler: DesktopAuthHandler());
      await notesHandler.handleDeleteNote(request, noteId);
      return;
    }

    // 12. Serve Saved Screenshots with Path Traversal & Injection Defense
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
    final html = DesktopWebTemplate.render(
      localIp: _localIp ?? '127.0.0.1',
      port: _port,
      version: AppUpdateService.currentVersion,
    );

    request.response.headers.contentType = ContentType.html;
    request.response.write(html);
    request.response.close();
  }
}
