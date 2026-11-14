import 'dart:convert';
import 'dart:io';
import 'dart:math';

class DesktopAuthHandler {
  String _currentPin = '202799';
  final Set<String> _activeSessions = {};

  String get currentPin => _currentPin;
  Set<String> get activeSessions => _activeSessions;

  void initialize(String pin) {
    _currentPin = pin;
  }

  String generateNewPin() {
    final rand = Random();
    _currentPin = (100000 + rand.nextInt(900000)).toString();
    _activeSessions.clear(); // Invalidate all active laptop sessions
    return _currentPin;
  }

  bool isSessionValid(String? token) {
    if (token == null || token.isEmpty) return false;
    return _activeSessions.contains(token);
  }

  void revokeSession(String? token) {
    if (token != null) {
      _activeSessions.remove(token);
    }
  }

  void revokeAllSessions() {
    _activeSessions.clear();
  }

  String? extractBearerToken(HttpRequest request) {
    final authHeader = request.headers.value('Authorization');
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      return authHeader.substring(7).trim();
    }
    return null;
  }

  Future<void> handleAuthVerify(HttpRequest request) async {
    try {
      final bodyStr = await utf8.decodeStream(request);
      final json = jsonDecode(bodyStr);
      final inputPin = json['pin']?.toString().trim() ?? '';

      if (inputPin == _currentPin) {
        final token = 'session_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
        _activeSessions.add(token);

        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'success': true,
          'token': token,
          'message': 'PIN verified successfully',
        }));
      } else {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'success': false,
          'error': 'Invalid 6-digit PIN. Please verify the code displayed on your phone app.',
        }));
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': false, 'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleAuthStatus(HttpRequest request) async {
    final token = extractBearerToken(request);
    final isAuthenticated = isSessionValid(token);

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'authenticated': isAuthenticated}));
    await request.response.close();
  }

  Future<void> handleAuthLogout(HttpRequest request) async {
    final token = extractBearerToken(request);
    revokeSession(token);

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'success': true, 'message': 'Logged out successfully'}));
    await request.response.close();
  }
}
